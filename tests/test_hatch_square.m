%% test_hatch_square.m
% Test hatch_layer() on a simple 100um x 100um square at various angles.
% Run from the project root: run('tests/test_hatch_square.m')

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'viz'));

fprintf('\n=== test_hatch_square ===\n');

% Define a 0.1 x 0.1 mm square as contour segments (4 edges)
sq = [0 0 0.1 0;      % bottom edge
      0.1 0 0.1 0.1;  % right edge
      0.1 0.1 0 0.1;  % top edge
      0 0.1 0 0];     % left edge

bbox = [0 0 0.1 0.1];
spacing = 0.001;  % 1 um hatch spacing (coarse for testing)
tol = 1e-9;

%% Test 1: 0 degree (X-directed scan)
fprintf('\nTest 1: angle=0 deg (X-directed scan)...\n');
segs0 = hatch_layer(sq, 0, spacing, bbox, 'centers', tol);
fprintf('  Segments: %d\n', size(segs0, 1));
assert(~isempty(segs0), 'Should produce segments for 0 deg hatch');

% At 0 deg, all segments should be horizontal (Y constant per segment)
dy = abs(segs0(:,4) - segs0(:,2));
assert(all(dy < tol), 'At 0 deg, all segments should be horizontal (Y1==Y2)');
fprintf('  PASS: All segments are horizontal.\n');

%% Test 2: 90 degree (Y-directed scan)
fprintf('\nTest 2: angle=90 deg (Y-directed scan)...\n');
segs90 = hatch_layer(sq, 90, spacing, bbox, 'centers', tol);
fprintf('  Segments: %d\n', size(segs90, 1));
assert(~isempty(segs90), 'Should produce segments for 90 deg hatch');

% At 90 deg, all segments should be vertical (X constant per segment)
dx = abs(segs90(:,4) - segs90(:,2));  % Note: checking rotated correctly
% Actually for 90-deg: x1 should equal x2
dxCheck = abs(segs90(:,3) - segs90(:,1));
assert(all(dxCheck < tol*1000), 'At 90 deg, all segments should be vertical (X1==X2)');
fprintf('  PASS: All segments are vertical.\n');

%% Test 3: 45 degree (diagonal scan)
fprintf('\nTest 3: angle=45 deg (diagonal scan)...\n');
segs45 = hatch_layer(sq, 45, spacing, bbox, 'centers', tol);
fprintf('  Segments: %d\n', size(segs45, 1));
assert(~isempty(segs45), 'Should produce segments for 45 deg hatch');

% At 45 deg, each segment should have |dx| ≈ |dy|
dx45 = abs(segs45(:,3) - segs45(:,1));
dy45 = abs(segs45(:,4) - segs45(:,2));
ratio = dx45 ./ max(dy45, 1e-15);
% For non-degenerate segments, ratio should be close to 1
validSegs = dx45 > tol & dy45 > tol;
if any(validSegs)
    assert(all(abs(ratio(validSegs) - 1) < 0.1), ...
        'At 45 deg, dx and dy should be approximately equal');
    fprintf('  PASS: Diagonal segments have dx ≈ dy.\n');
else
    fprintf('  SKIP: No non-degenerate diagonal segments to verify.\n');
end

%% Test 4: Serpentine ordering
fprintf('\nTest 4: Serpentine ordering at 0 deg...\n');
segsS = order_serpentine(segs0, 0, tol);
fprintf('  Ordered segments: %d\n', size(segsS, 1));
assert(size(segsS, 1) == size(segs0, 1), 'Serpentine should not change segment count');

% Check alternating direction: line 1 should go left→right, line 2 right→left
if size(segsS, 1) >= 2
    dir1 = segsS(1, 3) - segsS(1, 1);  % dx of first segment
    dir2 = segsS(2, 3) - segsS(2, 1);  % dx of second segment
    assert(dir1 * dir2 < 0, 'Adjacent lines should have opposite X direction');
    fprintf('  PASS: Serpentine alternation confirmed.\n');
end

%% Test 5: Greedy ordering
fprintf('\nTest 5: Greedy path ordering...\n');
[segsG, lastXY] = order_greedy(segs0, [0, 0]);
fprintf('  Ordered segments: %d, last XY: [%.4f, %.4f]\n', ...
    size(segsG, 1), lastXY(1), lastXY(2));
assert(size(segsG, 1) == size(segs0, 1), 'Greedy should not change segment count');
fprintf('  PASS: Greedy ordering completed.\n');

%% Test 6: Segment count vs expected
fprintf('\nTest 6: Segment count check...\n');
expectedLines = floor(0.1 / spacing);  % 100 lines for 0.1mm / 0.001mm
fprintf('  Expected ~%d lines, got %d\n', expectedLines, size(segs0, 1));
% Allow some tolerance (edge effects)
assert(abs(size(segs0, 1) - expectedLines) < expectedLines * 0.2, ...
    'Segment count should be close to expected');
fprintf('  PASS: Segment count within 20%% of expected.\n');

%% Visualization
fprintf('\nGenerating preview plots...\n');
figure('Name', 'Hatch Test: 0°, 45°, 90°', 'Position', [100 100 1200 400]);

subplot(1,3,1); hold on; axis equal; grid on;
for i = 1:size(segs0,1)
    plot([segs0(i,1) segs0(i,3)], [segs0(i,2) segs0(i,4)], 'r-');
end
title('0° (X-scan)'); xlabel('X (mm)'); ylabel('Y (mm)');

subplot(1,3,2); hold on; axis equal; grid on;
for i = 1:size(segs45,1)
    plot([segs45(i,1) segs45(i,3)], [segs45(i,2) segs45(i,4)], 'g-');
end
title('45° (diagonal)'); xlabel('X (mm)'); ylabel('Y (mm)');

subplot(1,3,3); hold on; axis equal; grid on;
for i = 1:size(segs90,1)
    plot([segs90(i,1) segs90(i,3)], [segs90(i,2) segs90(i,4)], 'b-');
end
title('90° (Y-scan)'); xlabel('X (mm)'); ylabel('Y (mm)');

sgtitle('Hatch Layer Test: 100um Square');

fprintf('\n=== All tests passed! ===\n\n');
