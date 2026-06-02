function segs = order_serpentine(segs, angle_deg, tol)
% ORDER_SERPENTINE  Apply boustrophedon (serpentine) ordering to scan segments.
%
%   segs = order_serpentine(segs, angle_deg, tol)
%
% INPUTS:
%   segs      - Nx4 matrix [x1 y1 x2 y2] of scan segments (all at same Z)
%   angle_deg - Scan angle used to generate these segments (degrees)
%   tol       - Tolerance for grouping segments into scan lines (mm)
%
% OUTPUT:
%   segs      - Nx4 matrix, reordered so adjacent scan lines alternate
%               direction (left-right, then right-left, etc.)
%
% The function groups segments by their "scan line coordinate" (the
% coordinate perpendicular to the scan direction), sorts them, and
% alternates the sweep direction on even-indexed lines.
%
% See also: hatch_layer, order_greedy, build_toolpath

    if nargin < 3 || isempty(tol), tol = 1e-9; end
    if isempty(segs), return; end

    nSegs = size(segs, 1);

    % ---- Rotate into scan frame (scan direction = X, line index = Y) ----
    theta = -angle_deg * pi / 180;
    cosA = cos(theta);  sinA = sin(theta);

    % Rotate start and end points
    rx1 = cosA * segs(:,1) - sinA * segs(:,2);
    ry1 = sinA * segs(:,1) + cosA * segs(:,2);
    rx2 = cosA * segs(:,3) - sinA * segs(:,4);
    ry2 = sinA * segs(:,3) + cosA * segs(:,4);

    % In the rotated frame, scan direction is X and line position is Y.
    % ry1 and ry2 should be the same (horizontal lines), use average.
    lineY = (ry1 + ry2) / 2;

    % ---- Group by scan line Y coordinate ----
    [sortedY, sortIdx] = sort(lineY);

    % Find unique scan line positions (within tolerance)
    lineBreaks = [1; find(diff(sortedY) > tol) + 1; nSegs + 1];
    nLines = numel(lineBreaks) - 1;

    % ---- Reorder: serpentine ----
    outIdx = zeros(nSegs, 1);
    for li = 1:nLines
        span = lineBreaks(li) : lineBreaks(li+1)-1;
        idxRange = sortIdx(span);

        [~, xOrd] = sort(rx1(idxRange), 'ascend');
        idxRange = idxRange(xOrd);

        if mod(li, 2) == 0
            idxRange = flipud(idxRange(:));
            segs(idxRange, :) = segs(idxRange, [3 4 1 2]);  % vectorized flip
        end

        outIdx(span) = idxRange;
    end

    segs = segs(outIdx, :);
end
