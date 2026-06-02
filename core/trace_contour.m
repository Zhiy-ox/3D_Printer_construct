function segs = trace_contour(contour2d, tol)
% TRACE_CONTOUR  Order contour segments into continuous chains for boundary tracing.
%
%   segs = trace_contour(contour2d, tol)
%
% INPUTS:
%   contour2d - Nx4 matrix [x1 y1 x2 y2] of unordered 2D contour segments
%   tol       - Tolerance for connecting segment endpoints (mm)
%
% OUTPUT:
%   segs      - Mx4 matrix [x1 y1 x2 y2] of ordered contour segments,
%               forming continuous chains. Multiple closed loops are
%               concatenated in sequence.
%
% This function chains individual contour segments into continuous paths
% (closed loops) using a nearest-endpoint greedy algorithm. It handles:
%   - Multiple disjoint loops (e.g., outer boundary + hole boundaries)
%   - Open chains (if the contour is not perfectly closed)
%   - Segment direction flipping to maintain continuity
%
% In TPP-DLW, tracing the contour before hatching improves dimensional
% accuracy at the boundary of the structure.
%
% See also: hatch_layer, build_toolpath

    if isempty(contour2d)
        segs = zeros(0, 4);
        return;
    end

    N = size(contour2d, 1);
    unusedSet = (1:N).';   % integer index set — removal is O(N) but N is small
    chains = {};

    while ~isempty(unusedSet)
        % Start a new chain from the first unused segment
        startIdx = unusedSet(1);
        unusedSet(1) = [];

        chain = contour2d(startIdx, :);
        curEnd    = chain(end, 3:4);
        chainStart = chain(1, 1:2);

        changed = true;
        while changed && ~isempty(unusedSet)
            changed = false;

            % Vectorized nearest-endpoint search over remaining candidates
            P1 = contour2d(unusedSet, 1:2);
            P2 = contour2d(unusedSet, 3:4);
            d1 = sum((P1 - curEnd).^2, 2);
            d2 = sum((P2 - curEnd).^2, 2);
            [mn1, j1] = min(d1);
            [mn2, j2] = min(d2);
            if mn1 <= mn2
                jBest = j1;  bestFlip = false;  bestDist = sqrt(mn1);
            else
                jBest = j2;  bestFlip = true;   bestDist = sqrt(mn2);
            end

            if bestDist < tol * 1000  % generous connection tolerance
                bestIdx = unusedSet(jBest);
                unusedSet(jBest) = [];
                s = contour2d(bestIdx, :);
                if bestFlip
                    s = [s(3) s(4) s(1) s(2)];
                end
                chain(end+1, :) = s; %#ok<AGROW>
                curEnd = s(3:4);
                changed = true;

                % Check if we've closed the loop
                if hypot(curEnd(1)-chainStart(1), curEnd(2)-chainStart(2)) < tol * 100
                    break;
                end
            end
        end

        chains{end+1} = chain; %#ok<AGROW>
    end

    % Concatenate all chains
    segs = vertcat(chains{:});
end
