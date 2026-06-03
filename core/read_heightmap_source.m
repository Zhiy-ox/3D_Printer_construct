function hm = read_heightmap_source(source_path, varargin)
% READ_HEIGHTMAP_SOURCE  Load a height map from CSV/TXT or pixel-exact STL.
%
%   hm = read_heightmap_source(source_path, ...)
%
% Returns a struct with:
%   Height       : Ny-by-Nx height matrix in source numeric units
%   SourcePitch  : [xPitch yPitch] in the same source units
%   Units        : Unit label from source/header when available
%   BaseHeight   : Base height from STL header when available
%   SourceType   : 'csv' or 'stl'

    cfg = parse_inputs(varargin{:});
    assert(~isempty(source_path) && (ischar(source_path) || isstring(source_path)), ...
        'read_heightmap_source:badPath', 'source_path must be a non-empty string.');
    source_path = char(source_path);
    assert(exist(source_path, 'file') == 2, ...
        'read_heightmap_source:notFound', 'Height-map source not found: %s', source_path);

    [~, ~, ext] = fileparts(source_path);
    ext = lower(ext);

    switch ext
        case '.stl'
            hm = recover_heightmap_from_stl(source_path, 'PixelPitch', cfg.PixelPitch);
        case {'.csv', '.txt', '.tsv'}
            height = read_numeric_grid(source_path);
            sourcePitch = cfg.PixelPitch;
            if isempty(sourcePitch)
                sourcePitch = 1;
            end
            if numel(sourcePitch) == 1
                sourcePitch = [sourcePitch sourcePitch];
            end
            hm = struct();
            hm.Height = height + cfg.AddBaseHeight;
            hm.SourcePitch = sourcePitch;
            hm.Units = cfg.Units;
            hm.BaseHeight = cfg.AddBaseHeight;
            hm.SourceType = 'csv';
            hm.SourcePath = source_path;
        otherwise
            error('read_heightmap_source:unsupported', ...
                'Unsupported height-map source: %s. Use .stl, .csv, .txt, or .tsv.', ext);
    end
end

function cfg = parse_inputs(varargin)
    cfg.PixelPitch = [];
    cfg.AddBaseHeight = 0;
    cfg.Units = 'source';

    assert(mod(numel(varargin), 2) == 0, ...
        'read_heightmap_source:nameValue', 'Arguments must be name-value pairs.');
    for k = 1:2:numel(varargin)
        name = lower(char(varargin{k}));
        val = varargin{k + 1};
        switch name
            case 'pixelpitch'
                cfg.PixelPitch = val;
            case 'addbaseheight'
                cfg.AddBaseHeight = val;
            case 'units'
                cfg.Units = char(val);
            otherwise
                error('read_heightmap_source:unknownParam', 'Unknown parameter: %s', name);
        end
    end
end

function height = read_numeric_grid(path)
    try
        height = readmatrix(path);
    catch
        try
            height = dlmread(path);
        catch ME
            error('read_heightmap_source:readFailed', ...
                'Could not read numeric height map %s: %s', path, ME.message);
        end
    end

    height = double(height);
    height = height(all(isfinite(height), 2), :);
    height = height(:, all(isfinite(height), 1));
    assert(~isempty(height), 'read_heightmap_source:emptyGrid', ...
        'No numeric height values found in %s.', path);
end

function hm = recover_heightmap_from_stl(stl_path, varargin)
    cfg = parse_stl_inputs(varargin{:});
    meta = parse_stl_header(stl_path);

    [F, V] = read_stl_any_raw(stl_path);
    assert(~isempty(F) && ~isempty(V), ...
        'read_heightmap_source:stlImportFailed', 'Could not import STL: %s', stl_path);

    zMin = min(V(:, 3));
    xMin = min(V(:, 1));
    xMax = max(V(:, 1));
    yMin = min(V(:, 2));
    yMax = max(V(:, 2));

    sourcePitch = cfg.PixelPitch;
    if isempty(sourcePitch)
        sourcePitch = meta.Pitch;
    end
    if isempty(sourcePitch)
        sourcePitch = infer_pitch(V(:, 1), V(:, 2));
    end
    if numel(sourcePitch) == 1
        sourcePitch = [sourcePitch sourcePitch];
    end

    nx = max(1, round((xMax - xMin) / sourcePitch(1)));
    ny = max(1, round((yMax - yMin) / sourcePitch(2)));

    triZ = reshape(V(F, 3), size(F));
    zSpread = max(triZ, [], 2) - min(triZ, [], 2);
    tol = max(1e-9, max(sourcePitch) * 1e-9);
    flatTop = zSpread <= tol & max(triZ, [], 2) > zMin + tol;

    assert(any(flatTop), ...
        'read_heightmap_source:noTopFaces', ...
        'No flat top faces found. This STL may not be a pixel-exact height map.');

    tri = F(flatTop, :);
    cx = mean(reshape(V(tri, 1), size(tri)), 2);
    cy = mean(reshape(V(tri, 2), size(tri)), 2);
    cz = mean(reshape(V(tri, 3), size(tri)), 2);

    col = floor((cx - xMin) / sourcePitch(1)) + 1;
    row = floor((cy - yMin) / sourcePitch(2)) + 1;
    valid = row >= 1 & row <= ny & col >= 1 & col <= nx & isfinite(cz);

    height = accumarray([row(valid) col(valid)], cz(valid), [ny nx], @max, NaN);
    missing = isnan(height);
    if any(missing(:))
        warning('read_heightmap_source:missingCells', ...
            'Recovered height map has %d missing cell(s); filling them with 0.', sum(missing(:)));
        height(missing) = 0;
    end

    hm = struct();
    hm.Height = height;
    hm.SourcePitch = sourcePitch;
    hm.Units = meta.Units;
    hm.BaseHeight = meta.BaseHeight;
    hm.SourceType = 'stl';
    hm.SourcePath = stl_path;
    hm.SourceBounds = [xMin yMin zMin; xMax yMax max(V(:, 3))];
end

function cfg = parse_stl_inputs(varargin)
    cfg.PixelPitch = [];
    assert(mod(numel(varargin), 2) == 0, ...
        'recover_heightmap_from_stl:nameValue', 'Arguments must be name-value pairs.');
    for k = 1:2:numel(varargin)
        name = lower(char(varargin{k}));
        val = varargin{k + 1};
        switch name
            case 'pixelpitch'
                cfg.PixelPitch = val;
            otherwise
                error('recover_heightmap_from_stl:unknownParam', 'Unknown parameter: %s', name);
        end
    end
end

function meta = parse_stl_header(path)
    meta = struct('Units', 'source', 'Pitch', [], 'BaseHeight', []);
    fid = fopen(path, 'r');
    assert(fid >= 0, 'Could not open STL: %s', path);
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    header = char(fread(fid, 80, '*uint8')');

    tok = regexp(header, 'units\s*=\s*([A-Za-z]+)', 'tokens', 'once');
    if ~isempty(tok), meta.Units = tok{1}; end

    tok = regexp(header, 'pitch\s*=\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s*([A-Za-z]*)', 'tokens', 'once');
    if ~isempty(tok)
        meta.Pitch = str2double(tok{1});
    end

    tok = regexp(header, 'base\s*=\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s*([A-Za-z]*)', 'tokens', 'once');
    if ~isempty(tok)
        meta.BaseHeight = str2double(tok{1});
    end
end

function pitch = infer_pitch(x, y)
    ux = unique(x(:));
    uy = unique(y(:));
    dx = diff(ux);
    dy = diff(uy);
    dx = dx(dx > 0);
    dy = dy(dy > 0);
    candidates = [dx(:); dy(:)];
    candidates = candidates(isfinite(candidates) & candidates > 0);
    assert(~isempty(candidates), ...
        'read_heightmap_source:pitchUnknown', ...
        'Could not infer pixel pitch. Pass PixelPitch explicitly.');
    pitch = min(candidates);
end

function [F, V] = read_stl_any_raw(fname)
    F = []; V = [];
    fid = fopen(fname, 'r');
    if fid < 0, return; end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    hdr = fread(fid, 256, '*uint8')';
    frewind(fid);

    isAscii = false;
    if numel(hdr) >= 5
        h = char(hdr(1:min(80, end)));
        if strncmpi(strtrim(h), 'solid', 5)
            isAscii = true;
        end
    end

    if isAscii
        try
            txt = fread(fid, '*char')';
            if ~isempty(regexpi(txt, 'facet', 'once')) && ...
               ~isempty(regexpi(txt, 'vertex', 'once'))
                pat = ['(?i)vertex\s+([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+' ...
                       '([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+' ...
                       '([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)'];
                tok = regexp(txt, pat, 'tokens');
                if ~isempty(tok)
                    rows = cellfun(@(t) [str2double(t{1}) str2double(t{2}) str2double(t{3})], ...
                        tok, 'UniformOutput', false);
                    V = vertcat(rows{:});
                    nfaces = size(V, 1) / 3;
                    if abs(nfaces - round(nfaces)) < 1e-9
                        F = reshape(1:size(V, 1), 3, []).';
                        return;
                    end
                end
            end
        catch
        end
        frewind(fid);
    end

    fseek(fid, 80, 'bof');
    nfaces = fread(fid, 1, 'uint32', 'l');
    if isempty(nfaces) || nfaces == 0, return; end
    raw = fread(fid, nfaces * 50, 'uint8=>uint8');
    if numel(raw) ~= nfaces * 50
        error('read_heightmap_source:truncatedSTL', ...
            'Binary STL is truncated: expected %d face bytes, found %d.', ...
            nfaces * 50, numel(raw));
    end
    raw = reshape(raw, 50, nfaces);
    vraw = raw(13:48, :);
    V = double(reshape(typecast(vraw(:), 'single'), 3, nfaces * 3).');
    F = reshape(1:size(V, 1), 3, []).';
end
