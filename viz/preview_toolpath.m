function preview_toolpath(segments_mm, varargin)
% PREVIEW_TOOLPATH  Visualize scan segments for one or more layers.
%
%   preview_toolpath(segments_mm)
%   preview_toolpath(segments_mm, 'Layer', 5)
%   preview_toolpath(segments_mm, 'Mode', '3d')
%   preview_toolpath(segments_mm, 'ShowContour', true)
%   preview_toolpath(segments_mm, 'Animate', true)
%
% OPTIONS:
%   'Layer'       - Show only this layer index (default: all)
%   'Mode'        - '2d' (top-down) or '3d' (perspective)  (default: '2d')
%   'ShowArrows'  - Show scan direction arrows              (default: false)
%   'ShowContour' - Highlight contour segments in blue      (default: false)
%   'Animate'     - Animate layer-by-layer build            (default: false)
%   'AnimDelay'   - Seconds between animation frames        (default: 0.1)
%
% COLORS:
%   Red   = hatch scan segments (laser on)
%   Blue  = contour segments (if ShowContour)
%   Gray  = Z-transition segments
%
% See also: preview_slices, preview_3d, tppdlw_process

    p = inputParser;
    addParameter(p, 'Layer', [], @isnumeric);
    addParameter(p, 'Mode', '2d', @ischar);
    addParameter(p, 'ShowArrows', false, @islogical);
    addParameter(p, 'ShowContour', false, @islogical);
    addParameter(p, 'Animate', false, @islogical);
    addParameter(p, 'AnimDelay', 0.1, @isnumeric);
    parse(p, varargin{:});

    if isempty(segments_mm)
        warning('preview_toolpath:empty', 'No segments to plot.');
        return;
    end

    % Classify segments
    scanMask = abs(segments_mm(:,3) - segments_mm(:,6)) < 1e-12;
    transMask = ~scanMask;
    % Z is negated for stage convention (bottom = largest value), so sort
    % descending => layer index 1 = bottom (first-written) layer.
    uniqueZ = sort(unique(segments_mm(scanMask, 3)), 'descend');

    % ---- Animate mode ----
    if p.Results.Animate
        animate_layers(segments_mm, scanMask, uniqueZ, p.Results.AnimDelay);
        return;
    end

    % ---- Filter by layer ----
    if ~isempty(p.Results.Layer)
        layerIdx = p.Results.Layer;
        if layerIdx > numel(uniqueZ)
            warning('Layer %d does not exist (%d layers).', layerIdx, numel(uniqueZ));
            return;
        end
        targetZ = uniqueZ(layerIdx);
        keepMask = abs(segments_mm(:,3) - targetZ) < 1e-10 & scanMask;
        segments_mm = segments_mm(keepMask, :);
        scanMask = true(size(segments_mm, 1), 1);
        transMask = false(size(segments_mm, 1), 1);
    end

    figure('Name', 'Toolpath Preview', 'NumberTitle', 'off', ...
           'Position', [100 100 800 700]);

    if strcmpi(p.Results.Mode, '3d')
        plot_3d(segments_mm, scanMask, transMask, p.Results.ShowArrows);
    else
        plot_2d(segments_mm, scanMask, transMask, p.Results);
    end
end

% =====================================================================
function plot_2d(seg, scanMask, transMask, opts)
    hold on; grid on; axis equal;

    % Scan segments
    if any(scanMask)
        ss = seg(scanMask, :);
        X = [ss(:,1)'; ss(:,4)'; nan(1,size(ss,1))];
        Y = [ss(:,2)'; ss(:,5)'; nan(1,size(ss,1))];
        plot(X(:), Y(:), 'r-', 'LineWidth', 0.5);
    end

    % Direction arrows
    if opts.ShowArrows && any(scanMask)
        ss = seg(scanMask, :);
        step = max(1, floor(size(ss,1)/40));
        for i = 1:step:size(ss,1)
            mx = (ss(i,1)+ss(i,4))/2;  my = (ss(i,2)+ss(i,5))/2;
            dx = ss(i,4)-ss(i,1);  dy = ss(i,5)-ss(i,2);
            len = sqrt(dx^2+dy^2);
            if len > 0
                quiver(mx,my, dx/len*0.003, dy/len*0.003, 0, 'k', 'MaxHeadSize',2);
            end
        end
    end

    xlabel('X (mm)'); ylabel('Y (mm)');

    uniqueZ = unique(seg(scanMask, 3));
    if numel(uniqueZ) == 1
        title(sprintf('Z = %.6f mm  |  %d segments', uniqueZ(1), sum(scanMask)));
    else
        title(sprintf('%d layers  |  %d scan segments', numel(uniqueZ), sum(scanMask)));
    end
end

% =====================================================================
function plot_3d(seg, scanMask, transMask, showArrows)
    hold on; grid on; axis equal; view(3);

    if any(scanMask)
        ss = seg(scanMask, :);
        X = [ss(:,1)'; ss(:,4)'; nan(1,size(ss,1))];
        Y = [ss(:,2)'; ss(:,5)'; nan(1,size(ss,1))];
        Z = [ss(:,3)'; ss(:,6)'; nan(1,size(ss,1))];
        plot3(X(:), Y(:), Z(:), 'r-', 'LineWidth', 0.5);
    end

    if any(transMask)
        ts = seg(transMask, :);
        X = [ts(:,1)'; ts(:,4)'; nan(1,size(ts,1))];
        Y = [ts(:,2)'; ts(:,5)'; nan(1,size(ts,1))];
        Z = [ts(:,3)'; ts(:,6)'; nan(1,size(ts,1))];
        plot3(X(:), Y(:), Z(:), '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.3);
    end

    xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
    title('3D Toolpath Preview');
end

% =====================================================================
function animate_layers(seg, scanMask, uniqueZ, delay)
    figure('Name', 'Layer Animation', 'NumberTitle', 'off', ...
           'Position', [100 100 800 700]);

    % Compute global axis limits
    allX = [seg(scanMask,1); seg(scanMask,4)];
    allY = [seg(scanMask,2); seg(scanMask,5)];
    xLim = [min(allX)-0.005, max(allX)+0.005];
    yLim = [min(allY)-0.005, max(allY)+0.005];

    nLayers = numel(uniqueZ);

    for li = 1:nLayers
        z = uniqueZ(li);
        mask = abs(seg(:,3) - z) < 1e-10 & scanMask;
        ss = seg(mask, :);

        cla; hold on; grid on; axis equal;
        xlim(xLim); ylim(yLim);

        if ~isempty(ss)
            X = [ss(:,1)'; ss(:,4)'; nan(1,size(ss,1))];
            Y = [ss(:,2)'; ss(:,5)'; nan(1,size(ss,1))];
            plot(X(:), Y(:), 'r-', 'LineWidth', 0.8);
        end

        title(sprintf('Layer %d/%d  |  Z = %.6f mm  |  %d segs', ...
              li, nLayers, z, size(ss,1)));
        xlabel('X (mm)'); ylabel('Y (mm)');
        drawnow;
        pause(delay);
    end
    title(sprintf('Animation complete — %d layers', nLayers));
end
