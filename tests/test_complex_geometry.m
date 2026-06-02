%% test_complex_geometry.m
% Test the pipeline with complex geometry: hollow cylinder, thin walls, multi-body.
% Run from the project root: run('tests/test_complex_geometry.m')

addpath(fullfile(fileparts(mfilename('fullpath')), '..'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'viz'));

fprintf('\n=== test_complex_geometry ===\n');

%% Test 1: Hollow cylinder (hole in cross-section)
fprintf('\n--- Test 1: Hollow Cylinder (annular cross-section) ---\n');
[F1, V1] = create_hollow_cylinder(1.0, 0.8, 0.5, 32);
stlFile1 = fullfile(tempdir, 'test_hollow_cyl.stl');
write_stl_ascii(stlFile1, F1, V1);

cfg1 = tppdlw_config(...
    'InputFile', stlFile1, ...
    'OutputFile', fullfile(tempdir, 'hollow_cyl.txt'), ...
    'TargetSize_mm', 0.1, ...
    'LayerHeight_mm', 0.01, ...
    'HatchSpacing_mm', 0.005, ...
    'AngleMode', 'alternating', ...
    'TraceContour', true, ...
    'ContourFirst', true, ...
    'Serpentine', true, ...
    'OptimizePath', true);

segs1 = tppdlw_process(cfg1);
assert(~isempty(segs1), 'Hollow cylinder should produce segments');

% Verify: scan segments at any layer should have a gap (the hole)
scanMask1 = abs(segs1(:,3) - segs1(:,6)) < 1e-10;
uniqueZ1 = unique(segs1(scanMask1, 3));
z_mid = uniqueZ1(round(numel(uniqueZ1)/2));
layerSegs = segs1(abs(segs1(:,3) - z_mid) < 1e-10 & scanMask1, :);
fprintf('  Mid-layer (%d segs): checking for hole gap...\n', size(layerSegs,1));

% With a hole, a horizontal scan line should produce 2 separate segments
% (enter outer wall, exit into hole, enter outer wall again, exit)
% Count scan lines with same Y (for 0-deg layer)
if ~isempty(layerSegs)
    yVals = round(layerSegs(:,2) * 1e6);  % round to group
    [uniqueY, ~, ic] = unique(yVals);
    counts = accumarray(ic, 1);
    multiSegLines = sum(counts >= 2);
    fprintf('  Scan lines with 2+ segments (hole detected): %d / %d\n', ...
        multiSegLines, numel(uniqueY));
end

figure('Name', 'Hollow Cylinder - Layer', 'Position', [100 100 800 400]);
subplot(1,2,1);
preview_toolpath(segs1, 'Layer', round(numel(uniqueZ1)/2), 'Mode', '2d');
title('Hollow Cylinder: Mid Layer');
subplot(1,2,2);
preview_toolpath(segs1, 'Layer', 1, 'Mode', '2d');
title('Hollow Cylinder: Layer 1');

fprintf('  PASS: Hollow cylinder processed successfully.\n');

%% Test 2: Thin wall (single-hatch-line thickness)
fprintf('\n--- Test 2: Thin Wall ---\n');
[F2, V2] = create_thin_wall(2.0, 0.002, 0.5);  % 2mm long, 2um thin, 0.5mm tall
stlFile2 = fullfile(tempdir, 'test_thin_wall.stl');
write_stl_ascii(stlFile2, F2, V2);

cfg2 = tppdlw_config(...
    'InputFile', stlFile2, ...
    'OutputFile', fullfile(tempdir, 'thin_wall.txt'), ...
    'TargetSize_mm', 0.1, ...
    'LayerHeight_mm', 0.01, ...
    'HatchSpacing_mm', 0.003, ...
    'AngleMode', 'fixed', ...
    'ScanAngle_deg', 0, ...
    'TraceContour', true);

segs2 = tppdlw_process(cfg2);
assert(~isempty(segs2), 'Thin wall should produce at least contour segments');
fprintf('  PASS: Thin wall processed (%d segments).\n', size(segs2, 1));

%% Test 3: Overrun parameter
fprintf('\n--- Test 3: Overrun Extension ---\n');
cfg3_no = tppdlw_config(...
    'InputFile', stlFile1, ...
    'OutputFile', fullfile(tempdir, 'no_overrun.txt'), ...
    'TargetSize_mm', 0.1, ...
    'LayerHeight_mm', 0.02, ...
    'HatchSpacing_mm', 0.005, ...
    'Overrun_mm', 0, ...
    'TraceContour', false);
segs3_no = tppdlw_process(cfg3_no);

cfg3_yes = cfg3_no;
cfg3_yes.Overrun_mm = 0.002;
cfg3_yes.OutputFile = fullfile(tempdir, 'with_overrun.txt');
segs3_yes = tppdlw_process(cfg3_yes);

% With overrun, scan segments should be slightly longer
if ~isempty(segs3_no) && ~isempty(segs3_yes)
    sm_no = abs(segs3_no(:,3) - segs3_no(:,6)) < 1e-10;
    sm_yes = abs(segs3_yes(:,3) - segs3_yes(:,6)) < 1e-10;
    len_no = mean(sqrt(sum((segs3_no(sm_no,4:5)-segs3_no(sm_no,1:2)).^2, 2)));
    len_yes = mean(sqrt(sum((segs3_yes(sm_yes,4:5)-segs3_yes(sm_yes,1:2)).^2, 2)));
    fprintf('  Avg segment length: no overrun=%.6f mm, with overrun=%.6f mm\n', len_no, len_yes);
    assert(len_yes > len_no, 'Overrun should make segments longer');
    fprintf('  PASS: Overrun extends segments.\n');
end

%% Test 4: CenterOrigin and Offset
fprintf('\n--- Test 4: CenterOrigin + Offset ---\n');
cfg4 = tppdlw_config(...
    'InputFile', stlFile1, ...
    'OutputFile', fullfile(tempdir, 'centered.txt'), ...
    'TargetSize_mm', 0.1, ...
    'LayerHeight_mm', 0.02, ...
    'HatchSpacing_mm', 0.005, ...
    'CenterOrigin', true, ...
    'OffsetX_mm', 0.05, ...
    'OffsetY_mm', 0.05, ...
    'TraceContour', false);
segs4 = tppdlw_process(cfg4);

if ~isempty(segs4)
    sm4 = abs(segs4(:,3) - segs4(:,6)) < 1e-10;
    xCenter = mean([min(segs4(sm4,1)), max(segs4(sm4,4))]);
    yCenter = mean([min(segs4(sm4,2)), max(segs4(sm4,5))]);
    fprintf('  Center of scan area: (%.6f, %.6f) mm\n', xCenter, yCenter);
    fprintf('  Expected near: (0.05, 0.05) mm\n');
    assert(abs(xCenter - 0.05) < 0.01, 'X center should be near offset');
    assert(abs(yCenter - 0.05) < 0.01, 'Y center should be near offset');
    fprintf('  PASS: CenterOrigin + Offset working.\n');
end

%% Test 5: 45-degree incremental mode
fprintf('\n--- Test 5: Incremental 45-degree mode ---\n');
cfg5 = tppdlw_config(...
    'InputFile', stlFile1, ...
    'OutputFile', fullfile(tempdir, 'incremental45.txt'), ...
    'TargetSize_mm', 0.1, ...
    'LayerHeight_mm', 0.02, ...
    'HatchSpacing_mm', 0.005, ...
    'AngleMode', 'incremental', ...
    'ScanAngle_deg', 0, ...
    'AngleIncrement_deg', 45, ...
    'TraceContour', false);
segs5 = tppdlw_process(cfg5);
assert(~isempty(segs5), 'Incremental 45 should produce segments');
fprintf('  PASS: Incremental 45-degree mode works.\n');

% Show first 4 layers
figure('Name', 'Incremental 45 deg');
compare_layers(segs5, [1 2 3 4]);

%% Cleanup
delete(stlFile1); delete(stlFile2);
tmpFiles = dir(fullfile(tempdir, '*.txt'));
for i = 1:numel(tmpFiles)
    if startsWith(tmpFiles(i).name, {'hollow','thin','no_over','with_over','centered','incremental'})
        delete(fullfile(tempdir, tmpFiles(i).name));
    end
end

fprintf('\n=== All complex geometry tests passed! ===\n\n');


%% =================== Helper: create hollow cylinder STL ===================
function [F, V] = create_hollow_cylinder(rOuter, rInner, height, nSides)
    if nargin < 4, nSides = 32; end
    theta = linspace(0, 2*pi, nSides+1); theta(end) = [];
    V = []; F = [];

    % Outer cylinder
    for i = 1:nSides
        j = mod(i, nSides) + 1;
        v1 = [rOuter*cos(theta(i)), rOuter*sin(theta(i)), 0];
        v2 = [rOuter*cos(theta(j)), rOuter*sin(theta(j)), 0];
        v3 = [rOuter*cos(theta(j)), rOuter*sin(theta(j)), height];
        v4 = [rOuter*cos(theta(i)), rOuter*sin(theta(i)), height];
        base = size(V,1);
        V = [V; v1; v2; v3; v4]; %#ok<AGROW>
        F = [F; base+[1 2 3]; base+[1 3 4]]; %#ok<AGROW>
    end

    % Inner cylinder (reversed normals)
    for i = 1:nSides
        j = mod(i, nSides) + 1;
        v1 = [rInner*cos(theta(i)), rInner*sin(theta(i)), 0];
        v2 = [rInner*cos(theta(j)), rInner*sin(theta(j)), 0];
        v3 = [rInner*cos(theta(j)), rInner*sin(theta(j)), height];
        v4 = [rInner*cos(theta(i)), rInner*sin(theta(i)), height];
        base = size(V,1);
        V = [V; v1; v2; v3; v4]; %#ok<AGROW>
        F = [F; base+[1 3 2]; base+[1 4 3]]; %#ok<AGROW>
    end

    % Top and bottom annular caps
    for i = 1:nSides
        j = mod(i, nSides) + 1;
        % Bottom (z=0)
        vo1 = [rOuter*cos(theta(i)), rOuter*sin(theta(i)), 0];
        vo2 = [rOuter*cos(theta(j)), rOuter*sin(theta(j)), 0];
        vi1 = [rInner*cos(theta(i)), rInner*sin(theta(i)), 0];
        vi2 = [rInner*cos(theta(j)), rInner*sin(theta(j)), 0];
        base = size(V,1);
        V = [V; vo1; vo2; vi2; vi1]; %#ok<AGROW>
        F = [F; base+[1 3 2]; base+[1 4 3]]; %#ok<AGROW>

        % Top (z=height)
        vo1(3) = height; vo2(3) = height; vi1(3) = height; vi2(3) = height;
        base = size(V,1);
        V = [V; vo1; vo2; vi2; vi1]; %#ok<AGROW>
        F = [F; base+[1 2 3]; base+[1 3 4]]; %#ok<AGROW>
    end

    % Deduplicate vertices
    [V, ~, ic] = unique(V, 'rows', 'stable');
    F = ic(F);
end

%% =================== Helper: create thin wall STL ===================
function [F, V] = create_thin_wall(length, thickness, height)
    % Simple rectangular box: length x thickness x height
    x = length; y = thickness; z = height;
    V = [0 0 0; x 0 0; x y 0; 0 y 0;
         0 0 z; x 0 z; x y z; 0 y z];
    F = [1 2 3; 1 3 4;    % bottom
         5 7 6; 5 8 7;    % top
         1 6 2; 1 5 6;    % front
         4 3 7; 4 7 8;    % back
         1 4 8; 1 8 5;    % left
         2 6 7; 2 7 3];   % right
end

%% =================== Helper: write ASCII STL ===================
function write_stl_ascii(filepath, F, V)
    fid = fopen(filepath, 'w');
    fprintf(fid, 'solid test\n');
    for i = 1:size(F, 1)
        tri = V(F(i,:), :);
        e1 = tri(2,:)-tri(1,:); e2 = tri(3,:)-tri(1,:);
        n = cross(e1,e2); nn = norm(n);
        if nn > 0, n = n/nn; else, n = [0 0 1]; end
        fprintf(fid, '  facet normal %.6f %.6f %.6f\n', n);
        fprintf(fid, '    outer loop\n');
        for v = 1:3
            fprintf(fid, '      vertex %.10f %.10f %.10f\n', tri(v,:));
        end
        fprintf(fid, '    endloop\n  endfacet\n');
    end
    fprintf(fid, 'endsolid test\n');
    fclose(fid);
end
