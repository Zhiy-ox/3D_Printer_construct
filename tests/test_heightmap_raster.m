%% test_heightmap_raster.m
% Verify direct height-map raster output does not emit contour fragments.
% Run from the project root: run('tests/test_heightmap_raster.m')

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));

fprintf('\n=== test_heightmap_raster ===\n');

height = ones(3, 3);  % source units
[segments, info] = heightmap_to_segments(height, ...
    'SourcePitch', 1, ...
    'TargetMaxXY', 0.003, ...
    'HatchPitch_mm', 0.001, ...
    'LayerHeight_mm', 0.001, ...
    'StageZConvention', true, ...
    'WoodpileMode', true, ...
    'Serpentine', true, ...
    'CoordMode', 'edges');

assert(info.LayerCount == 1, 'Expected one layer.');
assert(size(segments, 1) == 3, 'Expected one full-width segment per scanline.');

expected = [
    0.000 0.0005 -0.0005 0.003 0.0005 -0.0005
    0.003 0.0015 -0.0005 0.000 0.0015 -0.0005
    0.000 0.0025 -0.0005 0.003 0.0025 -0.0005
];

assert(max(abs(segments(:) - expected(:))) < 1e-12, ...
    'Height-map raster output does not match expected full-width serpentine rows.');

fprintf('  PASS: full-height map exports clean full-width serpentine scanlines.\n');
fprintf('\n=== test_heightmap_raster complete ===\n\n');
