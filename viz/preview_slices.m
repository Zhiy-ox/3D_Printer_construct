function preview_slices(F, V, cfg, varargin)
% PREVIEW_SLICES  Visualize cross-section contours at selected Z layers.
%
%   preview_slices(F, V, cfg)
%   preview_slices(F, V, cfg, 'EveryN', 10)      % show every 10th layer
%   preview_slices(F, V, cfg, 'Layers', [1 5 10]) % show specific layers
%
% Displays a grid of subplots, one per selected layer, showing the
% 2D contour segments at each Z height.
%
% See also: preview_toolpath, preview_3d, slice_mesh

    p = inputParser;
    addParameter(p, 'EveryN', 1, @isnumeric);
    addParameter(p, 'Layers', [], @isnumeric);
    addParameter(p, 'MaxPlots', 25, @isnumeric);
    parse(p, varargin{:});

    % Scale mesh
    Vs = V;
    if cfg.AutoScale && cfg.TargetSize_mm > 0
        spanX = max(V(:,1)) - min(V(:,1));
        spanY = max(V(:,2)) - min(V(:,2));
        baseSpan = max(spanX, spanY);
        if baseSpan > 0
            Vs = V * (cfg.TargetSize_mm / baseSpan);
        end
    end

    zmin = min(Vs(:,3));  zmax = max(Vs(:,3));
    nLayers = max(1, ceil((zmax - zmin) / cfg.LayerHeight_mm));
    zPlanes = zmin + ((1:nLayers) - 0.5) * cfg.LayerHeight_mm;

    % Select which layers to show
    if ~isempty(p.Results.Layers)
        showIdx = p.Results.Layers;
        showIdx = showIdx(showIdx >= 1 & showIdx <= nLayers);
    else
        showIdx = 1:p.Results.EveryN:nLayers;
    end
    if numel(showIdx) > p.Results.MaxPlots
        step = ceil(numel(showIdx) / p.Results.MaxPlots);
        showIdx = showIdx(1:step:end);
    end

    % Slice
    layers = slice_mesh(F, Vs, zPlanes, cfg.Tolerance_mm);

    % Grid layout
    nShow = numel(showIdx);
    nCols = ceil(sqrt(nShow));
    nRows = ceil(nShow / nCols);

    figure('Name', 'Layer Slices Preview', 'NumberTitle', 'off', ...
           'Position', [100 100 300*nCols 300*nRows]);

    for k = 1:nShow
        li = showIdx(k);
        subplot(nRows, nCols, k);
        hold on; axis equal; grid on;

        contour2d = layers{li};
        if ~isempty(contour2d)
            for s = 1:size(contour2d, 1)
                plot([contour2d(s,1) contour2d(s,3)], ...
                     [contour2d(s,2) contour2d(s,4)], 'b-', 'LineWidth', 1);
            end
        end

        title(sprintf('Layer %d (Z=%.4f mm)', li, zPlanes(li)), 'FontSize', 8);
        xlabel('X (mm)'); ylabel('Y (mm)');
    end

    sgtitle(sprintf('Slice Preview — %d layers, dZ=%.4f mm', nLayers, cfg.LayerHeight_mm));
end
