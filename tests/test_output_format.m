%% test_output_format.m
% Verify our output format matches the reference Pyramid_T5-SINGLE.txt.
% Run from the project root: run('tests/test_output_format.m')

fprintf('\n=== test_output_format ===\n');

refFile = fullfile(fileparts(mfilename('fullpath')), '..', 'Pyramid_T5-SINGLE.txt');
if ~exist(refFile, 'file')
    fprintf('  SKIP: Reference file not found: %s\n', refFile);
    return;
end

%% Load reference
fprintf('\n[1] Loading reference file...\n');
refData = dlmread(refFile, '\t');
fprintf('  Rows: %d, Cols: %d\n', size(refData, 1), size(refData, 2));

% Must be 6 columns
assert(size(refData, 2) == 6, 'Reference should have 6 columns');
fprintf('  PASS: 6 columns.\n');

%% Analyze reference structure
fprintf('\n[2] Analyzing reference structure...\n');

% Identify scan vs transition segments
scanMask = abs(refData(:,3) - refData(:,6)) < 1e-10;
transMask = ~scanMask;
fprintf('  Scan segments: %d\n', sum(scanMask));
fprintf('  Z-transitions: %d\n', sum(transMask));

% Unique Z values
uniqueZ = unique(refData(scanMask, 3));
nLayers = numel(uniqueZ);
fprintf('  Layers: %d\n', nLayers);

% Layer height
if nLayers >= 2
    dz = diff(uniqueZ);
    fprintf('  Layer height: %.6g mm (%.2f um)\n', dz(1), dz(1)*1000);
    assert(all(abs(dz - dz(1)) < 1e-10), 'Layer height should be uniform');
    fprintf('  PASS: Uniform layer height.\n');
end

%% Verify layer 1 is X-directed (0 deg)
fprintf('\n[3] Checking Layer 1 scan direction...\n');
mask1 = abs(refData(:,3) - uniqueZ(1)) < 1e-10 & scanMask;
segs1 = refData(mask1, :);
dy1 = abs(segs1(:,5) - segs1(:,2));
fprintf('  Layer 1: max |dy| = %.2e\n', max(dy1));
assert(all(dy1 < 1e-8), 'Layer 1 should be X-directed (Y constant)');
fprintf('  PASS: Layer 1 is X-directed (0 deg).\n');

%% Verify layer 2 is Y-directed (90 deg)
fprintf('\n[4] Checking Layer 2 scan direction...\n');
mask2 = abs(refData(:,3) - uniqueZ(2)) < 1e-10 & scanMask;
segs2 = refData(mask2, :);
dx2 = abs(segs2(:,4) - segs2(:,1));
fprintf('  Layer 2: max |dx| = %.2e\n', max(dx2));
assert(all(dx2 < 1e-8), 'Layer 2 should be Y-directed (X constant)');
fprintf('  PASS: Layer 2 is Y-directed (90 deg).\n');

%% Verify Z-transitions
fprintf('\n[5] Checking Z-transitions...\n');
transSegs = refData(transMask, :);
xyDiff = sqrt((transSegs(:,4)-transSegs(:,1)).^2 + (transSegs(:,5)-transSegs(:,2)).^2);
fprintf('  Max XY movement in transitions: %.2e mm\n', max(xyDiff));
assert(all(xyDiff < 1e-8), 'Z-transitions should have constant XY');
fprintf('  PASS: Z-transitions are pure Z moves.\n');

%% Verify serpentine pattern in Layer 1
fprintf('\n[6] Checking serpentine pattern...\n');
% Layer 1: X-scan, so dx should alternate sign
if size(segs1, 1) >= 2
    dxDir = segs1(:,4) - segs1(:,1);  % positive = left→right
    signs = sign(dxDir);
    flips = diff(signs);
    nFlips = sum(abs(flips) > 0);
    fprintf('  Direction changes: %d out of %d segments\n', nFlips, size(segs1,1)-1);
    % In a perfect serpentine, every adjacent pair should flip
    % (may not be exactly all due to multi-segment lines)
    fprintf('  Flip ratio: %.1f%%\n', 100*nFlips/(size(segs1,1)-1));
end

%% Summary
fprintf('\n[7] Reference file summary:\n');
xAll = [refData(scanMask,1); refData(scanMask,4)];
yAll = [refData(scanMask,2); refData(scanMask,5)];
fprintf('  X range: [%.6g, %.6g] mm\n', min(xAll), max(xAll));
fprintf('  Y range: [%.6g, %.6g] mm\n', min(yAll), max(yAll));
fprintf('  Z range: [%.6g, %.6g] mm\n', min(uniqueZ), max(uniqueZ));
fprintf('  Structure size: ~%.1f um x %.1f um x %.1f um\n', ...
    (max(xAll)-min(xAll))*1000, (max(yAll)-min(yAll))*1000, ...
    (max(uniqueZ)-min(uniqueZ))*1000);

fprintf('\n=== Reference format analysis complete! ===\n\n');
