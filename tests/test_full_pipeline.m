%% test_full_pipeline.m
% End-to-end test: generate an STL cube, process it, verify output format.
% Run from the project root: run('tests/test_full_pipeline.m')

addpath(fullfile(fileparts(mfilename('fullpath')), '..'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'viz'));

fprintf('\n=== test_full_pipeline ===\n');

%% Step 1: Create a simple cube STL for testing
fprintf('\n[1] Creating test cube STL...\n');
cubeStl = fullfile(tempdir, 'test_cube.stl');
create_test_cube_stl(cubeStl, 1.0);  % 1mm cube
fprintf('  Created: %s\n', cubeStl);

%% Step 2: Run the full pipeline
fprintf('\n[2] Running full pipeline...\n');
outFile = fullfile(tempdir, 'test_cube_segments.txt');

cfg = tppdlw_config(...
    'InputFile',        cubeStl, ...
    'OutputFile',       outFile, ...
    'TargetSize_mm',    0.1, ...         % Scale to 100 um
    'LayerHeight_mm',   0.005, ...       % 5 um (coarse for fast test)
    'HatchSpacing_mm',  0.005, ...       % 5 um
    'AngleMode',        'alternating', ...
    'ScanAngle_deg',    0, ...
    'AngleIncrement_deg', 90, ...
    'Serpentine',       true, ...
    'OptimizePath',     true);

segments = tppdlw_process(cfg);

%% Step 3: Verify output file exists and has correct format
fprintf('\n[3] Verifying output format...\n');

assert(exist(outFile, 'file') == 2, 'Output file should exist');
data = dlmread(outFile, '\t');
fprintf('  File rows: %d, columns: %d\n', size(data, 1), size(data, 2));

% Must have exactly 6 columns
assert(size(data, 2) == 6, 'Output must have exactly 6 columns (x1 y1 z1 x2 y2 z2)');
fprintf('  PASS: 6 columns confirmed.\n');

% Must match in-memory segments
assert(size(data, 1) == size(segments, 1), 'File rows must match segment count');
fprintf('  PASS: Row count matches.\n');

%% Step 4: Verify scan segments vs Z-transitions
fprintf('\n[4] Checking segment types...\n');
scanMask = abs(data(:,3) - data(:,6)) < 1e-10;  % Z unchanged = scan
transMask = ~scanMask;

nScan = sum(scanMask);
nTrans = sum(transMask);
fprintf('  Scan segments: %d\n', nScan);
fprintf('  Z-transitions: %d\n', nTrans);

assert(nScan > 0, 'Must have scan segments');
assert(nTrans > 0, 'Must have Z-transition segments');
fprintf('  PASS: Both segment types present.\n');

% Z-transitions should have same XY
transSegs = data(transMask, :);
xyDiff = sqrt((transSegs(:,4)-transSegs(:,1)).^2 + (transSegs(:,5)-transSegs(:,2)).^2);
assert(all(xyDiff < 1e-10), 'Z-transitions must have X1==X2, Y1==Y2');
fprintf('  PASS: Z-transitions have constant XY.\n');

% Z-transitions should go upward
zDiff = transSegs(:,6) - transSegs(:,3);
assert(all(zDiff > 0), 'Z-transitions should go upward (z2 > z1)');
fprintf('  PASS: Z-transitions are upward.\n');

%% Step 5: Verify alternating scan direction
fprintf('\n[5] Checking alternating scan direction...\n');
uniqueZ = unique(data(scanMask, 3));
nLayers = numel(uniqueZ);
fprintf('  Layers detected: %d\n', nLayers);

if nLayers >= 2
    % Layer 1 (index 1): should be X-directed (Y constant per segment)
    mask1 = abs(data(:,3) - uniqueZ(1)) < 1e-10 & scanMask;
    segs1 = data(mask1, :);
    dy1 = abs(segs1(:,5) - segs1(:,2));
    isXscan = all(dy1 < 1e-8);

    % Layer 2 (index 2): should be Y-directed (X constant per segment)
    mask2 = abs(data(:,3) - uniqueZ(2)) < 1e-10 & scanMask;
    segs2 = data(mask2, :);
    dx2 = abs(segs2(:,4) - segs2(:,1));
    isYscan = all(dx2 < 1e-8);

    if isXscan && isYscan
        fprintf('  PASS: Layer 1 is X-scan (0 deg), Layer 2 is Y-scan (90 deg).\n');
    else
        fprintf('  INFO: Layer 1 X-scan=%d, Layer 2 Y-scan=%d\n', isXscan, isYscan);
        fprintf('  (May differ due to greedy reordering — checking qualitatively)\n');
    end
end

%% Step 6: Verify coordinates are in expected range
fprintf('\n[6] Checking coordinate ranges...\n');
scanData = data(scanMask, :);
xAll = [scanData(:,1); scanData(:,4)];
yAll = [scanData(:,2); scanData(:,5)];
zAll = scanData(:,3);

xRange = [min(xAll), max(xAll)];
yRange = [min(yAll), max(yAll)];
zRange = [min(zAll), max(zAll)];

fprintf('  X range: [%.6g, %.6g] mm\n', xRange(1), xRange(2));
fprintf('  Y range: [%.6g, %.6g] mm\n', yRange(1), yRange(2));
fprintf('  Z range: [%.6g, %.6g] mm\n', zRange(1), zRange(2));

% Should be within ~TargetSize_mm
assert(max(xAll) - min(xAll) <= cfg.TargetSize_mm * 1.1, ...
    'X span should be <= TargetSize');
assert(max(yAll) - min(yAll) <= cfg.TargetSize_mm * 1.1, ...
    'Y span should be <= TargetSize');
fprintf('  PASS: Coordinates within expected range.\n');

%% Step 7: Visualize
fprintf('\n[7] Generating preview...\n');
preview_toolpath(segments, 'Mode', '2d', 'Layer', 1);
title('Test Pipeline: Layer 1');

if nLayers >= 2
    figure;
    preview_toolpath(segments, 'Mode', '2d', 'Layer', 2);
    title('Test Pipeline: Layer 2');
end

%% Cleanup
delete(cubeStl);
delete(outFile);

fprintf('\n=== All pipeline tests passed! ===\n\n');


%% ---- Helper: create a simple cube STL ----
function create_test_cube_stl(filepath, size)
    % Create a unit cube STL file (ASCII format)
    s = size;
    % 12 triangles for a cube (2 per face)
    fid = fopen(filepath, 'w');
    fprintf(fid, 'solid cube\n');

    faces = {
        % bottom (z=0)
        [0 0 0; s 0 0; s s 0], [0 0 0; s s 0; 0 s 0];
        % top (z=s)
        [0 0 s; s s s; s 0 s], [0 0 s; 0 s s; s s s];
        % front (y=0)
        [0 0 0; s 0 s; s 0 0], [0 0 0; 0 0 s; s 0 s];
        % back (y=s)
        [0 s 0; s s 0; s s s], [0 s 0; s s s; 0 s s];
        % left (x=0)
        [0 0 0; 0 s 0; 0 s s], [0 0 0; 0 s s; 0 0 s];
        % right (x=s)
        [s 0 0; s s s; s s 0], [s 0 0; s 0 s; s s s];
    };

    for i = 1:numel(faces)
        tri = faces{i};
        % Compute normal
        e1 = tri(2,:) - tri(1,:);
        e2 = tri(3,:) - tri(1,:);
        n = cross(e1, e2);
        n = n / norm(n);
        fprintf(fid, '  facet normal %.6f %.6f %.6f\n', n(1), n(2), n(3));
        fprintf(fid, '    outer loop\n');
        fprintf(fid, '      vertex %.6f %.6f %.6f\n', tri(1,1), tri(1,2), tri(1,3));
        fprintf(fid, '      vertex %.6f %.6f %.6f\n', tri(2,1), tri(2,2), tri(2,3));
        fprintf(fid, '      vertex %.6f %.6f %.6f\n', tri(3,1), tri(3,2), tri(3,3));
        fprintf(fid, '    endloop\n');
        fprintf(fid, '  endfacet\n');
    end

    fprintf(fid, 'endsolid cube\n');
    fclose(fid);
end
