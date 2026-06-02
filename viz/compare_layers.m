function compare_layers(segments_mm, layerIndices)
% COMPARE_LAYERS  Side-by-side comparison of multiple layers.
%
%   compare_layers(segments_mm, [1 2 5 10])
%
% Shows the specified layers in a subplot grid for quick visual comparison
% of scan direction, fill density, and geometry changes across Z.
%
% See also: preview_toolpath, preview_3d

    if nargin < 2 || isempty(layerIndices)
        layerIndices = 1:4;  % default: first 4 layers
    end

    scanMask = abs(segments_mm(:,3) - segments_mm(:,6)) < 1e-12;
    % Z is negated for stage convention (bottom = largest value), so sort
    % descending => layer index 1 = bottom (first-written) layer.
    uniqueZ = sort(unique(segments_mm(scanMask, 3)), 'descend');
    nTotal = numel(uniqueZ);

    layerIndices = layerIndices(layerIndices >= 1 & layerIndices <= nTotal);
    nShow = numel(layerIndices);
    if nShow == 0
        warning('compare_layers: No valid layer indices.');
        return;
    end

    nCols = min(nShow, 4);
    nRows = ceil(nShow / nCols);

    % Global XY limits
    allX = [segments_mm(scanMask,1); segments_mm(scanMask,4)];
    allY = [segments_mm(scanMask,2); segments_mm(scanMask,5)];
    xLim = [min(allX)-0.002, max(allX)+0.002];
    yLim = [min(allY)-0.002, max(allY)+0.002];

    figure('Name', 'Layer Comparison', 'NumberTitle', 'off', ...
           'Position', [50 50 350*nCols 350*nRows]);

    for k = 1:nShow
        li = layerIndices(k);
        z = uniqueZ(li);
        mask = abs(segments_mm(:,3) - z) < 1e-10 & scanMask;
        ss = segments_mm(mask, :);

        subplot(nRows, nCols, k);
        hold on; grid on; axis equal;
        xlim(xLim); ylim(yLim);

        if ~isempty(ss)
            X = [ss(:,1)'; ss(:,4)'; nan(1,size(ss,1))];
            Y = [ss(:,2)'; ss(:,5)'; nan(1,size(ss,1))];
            plot(X(:), Y(:), 'r-', 'LineWidth', 0.6);

            % Show start point
            plot(ss(1,1), ss(1,2), 'go', 'MarkerSize', 4, 'MarkerFaceColor', 'g');
        end

        title(sprintf('L%d  Z=%.5f mm  (%d segs)', li, z, size(ss,1)), 'FontSize', 9);
        xlabel('X'); ylabel('Y');
    end

    sgtitle(sprintf('Layer Comparison — %d of %d layers', nShow, nTotal));
end
