function preview_3d(segments_mm, varargin)
% PREVIEW_3D  3D visualization of all toolpath segments.
%
%   preview_3d(segments_mm)
%   preview_3d(segments_mm, 'EveryN', 5)  % show every 5th layer for speed
%   preview_3d(segments_mm, 'ColorByLayer', true)
%
% Provides a rotatable 3D view of the full toolpath, with scan segments
% colored by layer height and Z-transitions shown as dashed gray lines.
%
% See also: preview_toolpath, preview_slices

    p = inputParser;
    addParameter(p, 'EveryN', 1, @isnumeric);
    addParameter(p, 'ColorByLayer', true, @islogical);
    parse(p, varargin{:});

    if isempty(segments_mm)
        warning('preview_3d:empty', 'No segments to plot.');
        return;
    end

    scanMask = abs(segments_mm(:,3) - segments_mm(:,6)) < 1e-12;
    scanSegs = segments_mm(scanMask, :);
    transSegs = segments_mm(~scanMask, :);

    % Z is negated for stage convention (bottom = largest value), so sort
    % descending => layer index 1 = bottom (first-written) layer.
    uniqueZ = sort(unique(scanSegs(:,3)), 'descend');
    nLayers = numel(uniqueZ);

    % Filter by EveryN
    if p.Results.EveryN > 1
        showZ = uniqueZ(1:p.Results.EveryN:end);
    else
        showZ = uniqueZ;
    end

    figure('Name', '3D Toolpath', 'NumberTitle', 'off', ...
           'Position', [100 100 900 700]);
    hold on; grid on; axis equal; view(3);

    if p.Results.ColorByLayer
        cmap = parula(numel(showZ));
    end

    for zi = 1:numel(showZ)
        z = showZ(zi);
        mask = abs(scanSegs(:,3) - z) < 1e-12;
        ss = scanSegs(mask, :);

        if p.Results.ColorByLayer
            col = cmap(zi, :);
        else
            col = [1 0 0];
        end

        % Plot scan segments as colored lines
        for i = 1:size(ss, 1)
            plot3([ss(i,1) ss(i,4)], [ss(i,2) ss(i,5)], ...
                  [ss(i,3) ss(i,6)], '-', 'Color', col, 'LineWidth', 0.5);
        end
    end

    % Z-transitions (gray)
    for i = 1:size(transSegs, 1)
        plot3([transSegs(i,1) transSegs(i,4)], ...
              [transSegs(i,2) transSegs(i,5)], ...
              [transSegs(i,3) transSegs(i,6)], ...
              '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.3);
    end

    xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
    title(sprintf('3D Toolpath — %d layers, showing every %d', ...
          nLayers, p.Results.EveryN));

    if p.Results.ColorByLayer
        colormap(parula);
        cb = colorbar;
        cb.Label.String = 'Z height (mm)';
        clim([min(uniqueZ), max(uniqueZ)]);
    end

    rotate3d on;
end
