function [F, V] = import_model(filepath)
% IMPORT_MODEL  Import a STEP or STL file into triangle mesh.
%
%   [F, V] = import_model(filepath)
%
% INPUTS:
%   filepath - Path to a .step, .stp, or .stl file
%
% OUTPUTS:
%   F - Nx3 face connectivity (indices into V)
%   V - Mx3 vertex coordinates [x y z] in the model's native units
%       (typically mm for STEP files)
%
% IMPORT STRATEGIES (tried in order):
%
%   For STEP (.step, .stp):
%     1. PDE Toolbox: importGeometry() + generateMesh()  [R2021a+]
%     2. Custom: shell out to FreeCAD to convert STEP -> STL, then read STL
%
%   For STL (.stl):
%     1. Built-in: stlread() [R2018b+]
%     2. Custom:   read_stl_any() — ASCII + binary parser (no toolbox)
%
% See also: tppdlw_process, build_toolpath, stlread

    assert(~isempty(filepath) && (ischar(filepath) || isstring(filepath)), ...
        'import_model:badInput', 'filepath must be a non-empty string.');
    filepath = char(filepath);
    assert(exist(filepath, 'file') == 2, ...
        'import_model:notFound', 'File not found: %s', filepath);

    [~, ~, ext] = fileparts(filepath);
    ext = lower(ext);

    switch ext
        case {'.step', '.stp'}
            [F, V] = import_step(filepath);
        case '.stl'
            [F, V] = import_stl(filepath);
        otherwise
            error('import_model:unsupported', ...
                'Unsupported file format: %s\nSupported: .step, .stp, .stl', ext);
    end

    fprintf('  Imported: %s\n', filepath);
    fprintf('  Vertices: %d, Faces: %d\n', size(V,1), size(F,1));
    fprintf('  Bounding box: X[%.6g, %.6g] Y[%.6g, %.6g] Z[%.6g, %.6g]\n', ...
        min(V(:,1)), max(V(:,1)), min(V(:,2)), max(V(:,2)), ...
        min(V(:,3)), max(V(:,3)));
end

% =====================================================================
%  STEP IMPORT
% =====================================================================
function [F, V] = import_step(filepath)
    % Strategy 1: PDE Toolbox (importGeometry + generateMesh)
    if has_pde_toolbox()
        try
            fprintf('  Using PDE Toolbox importGeometry()...\n');
            model = createpde();
            gm = importGeometry(model, filepath);

            % Generate a surface mesh
            msh = generateMesh(model, 'GeometricOrder', 'linear', ...
                                      'Hmax', estimate_hmax(gm));

            % Extract surface triangulation
            % For 3D PDE mesh: Elements is 4xN (tetrahedra)
            % We need to extract the surface faces
            if size(msh.Elements, 1) == 4
                % Tetrahedral mesh -> extract boundary faces
                [F, V] = extract_surface_from_tet(msh);
            else
                % 2D or surface mesh
                F = msh.Elements';
                V = msh.Nodes';
            end
            return;
        catch ME
            warning('import_model:pdeFailed', ...
                'PDE Toolbox import failed: %s\nTrying fallback...', ME.message);
        end
    end

    % Strategy 2: Convert via FreeCAD CLI
    if has_freecad()
        try
            fprintf('  Using FreeCAD to convert STEP -> STL...\n');
            tmpStl = [tempname, '.stl'];
            cmd = sprintf(['FreeCADCmd -c "import Part; ' ...
                           's=Part.read(''%s''); ' ...
                           'Part.export([s], ''%s'')"'], ...
                           strrep(filepath, '''', ''''''), tmpStl);
            [status, ~] = system(cmd);
            if status == 0 && exist(tmpStl, 'file')
                [F, V] = import_stl(tmpStl);
                delete(tmpStl);
                return;
            end
        catch ME
            warning('import_model:freecadFailed', ...
                'FreeCAD conversion failed: %s', ME.message);
        end
    end

    % Strategy 3: Try MATLAB's native readGeometry (R2023a+)
    try
        fprintf('  Trying readGeometry() [R2023a+]...\n');
        TR = readGeometry(filepath);
        F = TR.ConnectivityList;
        V = TR.Points;
        return;
    catch
        % Not available
    end

    error('import_model:noMethod', ...
        ['Cannot import STEP file. Options:\n' ...
         '  1. Install PDE Toolbox (recommended)\n' ...
         '  2. Install FreeCAD (free, https://freecad.org)\n' ...
         '  3. Convert STEP to STL externally, then import the STL\n' ...
         '  4. Use MATLAB R2023a+ (has readGeometry built-in)']);
end

% =====================================================================
%  STL IMPORT
% =====================================================================
function [F, V] = import_stl(filepath)
    % Strategy 1: Built-in stlread (R2018b+)
    try
        TR = stlread(filepath);
        F = TR.ConnectivityList;
        V = TR.Points;
        return;
    catch
        % Fall through to custom parser
    end

    % Strategy 2: Custom STL reader (no toolbox needed)
    [F, V] = read_stl_any(filepath);
    if isempty(F) || isempty(V)
        error('import_model:stlFailed', 'Failed to parse STL: %s', filepath);
    end
end

% =====================================================================
%  HELPER: Custom STL reader
% =====================================================================
function [F, V] = read_stl_any(fname)
    F = []; V = [];
    fid = fopen(fname, 'r');
    if fid < 0, return; end
    c = onCleanup(@() fclose(fid));

    hdr = fread(fid, 256, '*uint8')';
    frewind(fid);

    isAscii = false;
    if numel(hdr) >= 5
        h = char(hdr(1:min(80,end)));
        if startsWith(strtrim(string(h)), "solid", 'IgnoreCase', true)
            isAscii = true;
        end
    end

    if isAscii
        try
            txt = fread(fid, '*char')';
            if contains(txt, 'facet', 'IgnoreCase', true) && ...
               contains(txt, 'vertex', 'IgnoreCase', true)
                pat = ['(?i)vertex\s+([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+' ...
                       '([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+' ...
                       '([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)'];
                tok = regexp(txt, pat, 'tokens');
                if ~isempty(tok)
                    Vlist = cellfun(@(t) [str2double(t{1}) str2double(t{2}) str2double(t{3})], ...
                                   tok, 'UniformOutput', false);
                    Vlist = vertcat(Vlist{:});
                    nfaces = size(Vlist, 1) / 3;
                    if abs(nfaces - round(nfaces)) < 1e-9
                        [V, ~, ix] = unique(Vlist, 'rows', 'stable');
                        F = reshape(ix, 3, []).';
                    end
                end
            end
        catch
        end
        if isempty(F) || isempty(V)
            frewind(fid);
            isAscii = false;
        end
    end

    if ~isAscii
        fseek(fid, 80, 'bof');
        nfaces = fread(fid, 1, 'uint32', 'l');
        if isempty(nfaces) || nfaces == 0, return; end
        % Binary STL: 50 bytes per face — 12 normal + 12+12+12 vertices + 2 attr.
        % Read entire face block in one call; typecast vertices directly.
        raw = fread(fid, nfaces * 50, 'uint8=>uint8');
        if numel(raw) < nfaces * 50
            error('import_model:truncatedSTL', ...
                ['Binary STL is truncated: header declares %d faces ' ...
                 '(%d bytes) but only %d bytes follow.'], ...
                nfaces, nfaces * 50, numel(raw));
        end
        raw = reshape(raw, 50, nfaces);        % 50 bytes per face (column-major)
        vraw = raw(13:48, :);                  % bytes 13-48: 9 float32 per face
        % STL is little-endian; typecast uses native byte order (all supported
        % MATLAB platforms are little-endian, matching the spec).
        Vlist = double(reshape(typecast(vraw(:), 'single'), 3, nfaces * 3).');
        [V, ~, ix] = unique(Vlist, 'rows', 'stable');
        F = reshape(ix, 3, []).';
    end
end

% =====================================================================
%  HELPER: Check for PDE Toolbox
% =====================================================================
function tf = has_pde_toolbox()
    persistent result
    if isempty(result)
        v = ver;
        result = any(strcmpi({v.Name}, 'Partial Differential Equation Toolbox'));
    end
    tf = result;
end

% =====================================================================
%  HELPER: Check for FreeCAD
% =====================================================================
function tf = has_freecad()
    persistent result
    if isempty(result)
        [status, ~] = system('FreeCADCmd --version 2>/dev/null');
        result = (status == 0);
    end
    tf = result;
end

% =====================================================================
%  HELPER: Estimate mesh Hmax from geometry
% =====================================================================
function hmax = estimate_hmax(gm)
    % Use ~1/50 of the smallest dimension for a reasonable mesh density
    try
        bb = boundingBox(gm);
        spans = [bb(2)-bb(1), bb(4)-bb(3), bb(6)-bb(5)];
        hmax = min(spans(spans > 0)) / 50;
        hmax = max(hmax, 1e-6);  % safety floor
    catch
        hmax = 0.01;  % fallback: 10 um
    end
end

% =====================================================================
%  HELPER: Extract surface triangles from tetrahedral mesh
% =====================================================================
function [F, V] = extract_surface_from_tet(msh)
    V = msh.Nodes';
    tets = msh.Elements';  % Nx4

    % All faces of all tetrahedra (4 faces per tet)
    faces = [tets(:,[1 2 3]);
             tets(:,[1 2 4]);
             tets(:,[1 3 4]);
             tets(:,[2 3 4])];

    % Sort each face row so we can find duplicates
    facesSorted = sort(faces, 2);

    % Surface faces appear exactly once (interior faces appear twice)
    [~, ~, ic] = unique(facesSorted, 'rows');
    counts = accumarray(ic, 1);
    surfMask = counts(ic) == 1;

    F = faces(surfMask, :);
end
