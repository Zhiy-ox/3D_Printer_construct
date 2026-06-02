%% example_angle_modes.m
% Demonstrate the three writing direction modes on a test cube.
%
% This creates three .txt files, one for each angle mode, and
% visualizes layer 1 and layer 2 side by side to show the difference.

addpath(fullfile(fileparts(mfilename('fullpath')), '..'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'viz'));

%% Create test cube STL
cubeStl = fullfile(tempdir, 'test_cube_angles.stl');
fid = fopen(cubeStl, 'w');
fprintf(fid, 'solid cube\n');
s = 1.0;
faces = {
    [0 0 0; s 0 0; s s 0], [0 0 0; s s 0; 0 s 0];
    [0 0 s; s s s; s 0 s], [0 0 s; 0 s s; s s s];
    [0 0 0; s 0 s; s 0 0], [0 0 0; 0 0 s; s 0 s];
    [0 s 0; s s 0; s s s], [0 s 0; s s s; 0 s s];
    [0 0 0; 0 s 0; 0 s s], [0 0 0; 0 s s; 0 0 s];
    [s 0 0; s s s; s s 0], [s 0 0; s 0 s; s s s];
};
for i = 1:numel(faces)
    tri = faces{i};
    e1 = tri(2,:)-tri(1,:); e2 = tri(3,:)-tri(1,:);
    n = cross(e1,e2); n = n/norm(n);
    fprintf(fid, '  facet normal %.6f %.6f %.6f\n', n);
    fprintf(fid, '    outer loop\n');
    for v = 1:3, fprintf(fid, '      vertex %.6f %.6f %.6f\n', tri(v,:)); end
    fprintf(fid, '    endloop\n  endfacet\n');
end
fprintf(fid, 'endsolid cube\n');
fclose(fid);

%% Common settings (coarse for visualization)
baseCfg = tppdlw_config(...
    'InputFile',        cubeStl, ...
    'TargetSize_mm',    0.1, ...
    'LayerHeight_mm',   0.01, ...       % 10 um (coarse for demo)
    'HatchSpacing_mm',  0.005, ...      % 5 um
    'ScanAngle_deg',    0, ...
    'Serpentine',       true, ...
    'OptimizePath',     false);         % off for cleaner visualization

modes = {'fixed', 'alternating', 'incremental'};
increments = [0, 90, 45];
descriptions = {
    'Fixed 0° — all layers same direction'
    'Alternating 0°/90° — woodpile pattern'
    'Incremental +45° — 0°, 45°, 90°, 135°...'
};

figure('Name', 'Angle Modes Comparison', 'Position', [50 50 1400 800]);

for m = 1:3
    cfg = baseCfg;
    cfg.AngleMode = modes{m};
    cfg.AngleIncrement_deg = increments(m);
    cfg.OutputFile = fullfile(tempdir, sprintf('test_%s.txt', modes{m}));

    segments = tppdlw_process(cfg);

    % Get unique Z for layer selection
    scanMask = abs(segments(:,3) - segments(:,6)) < 1e-10;
    uniqueZ = unique(segments(scanMask, 3));

    % Show first 3 layers
    for li = 1:min(3, numel(uniqueZ))
        subplot(3, 3, (li-1)*3 + m);
        hold on; axis equal; grid on;

        z = uniqueZ(li);
        layerMask = abs(segments(:,3) - z) < 1e-10 & scanMask;
        ss = segments(layerMask, :);

        for i = 1:size(ss, 1)
            plot([ss(i,1) ss(i,4)], [ss(i,2) ss(i,5)], 'r-', 'LineWidth', 0.8);
        end

        if li == 1
            title(sprintf('%s\n(L%d)', descriptions{m}, li), 'FontSize', 9);
        else
            title(sprintf('Layer %d', li), 'FontSize', 9);
        end
        xlabel('X'); ylabel('Y');
    end
end

sgtitle('Writing Direction Modes — Layers 1, 2, 3', 'FontSize', 14);

% Cleanup
delete(cubeStl);
for m = 1:3
    f = fullfile(tempdir, sprintf('test_%s.txt', modes{m}));
    if exist(f, 'file'), delete(f); end
end

fprintf('\nDone! Compare the three columns to see how writing direction changes.\n');
