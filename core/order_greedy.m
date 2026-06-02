function [segs, lastXY] = order_greedy(segs, seedXY)
% ORDER_GREEDY  Greedy nearest-neighbor segment chaining.
%
%   [segs, lastXY] = order_greedy(segs, seedXY)
%
% INPUTS:
%   segs    - Nx4 matrix [x1 y1 x2 y2] of scan segments
%   seedXY  - [x y] starting position for the greedy search
%
% OUTPUTS:
%   segs    - Nx4 matrix, reordered to minimize travel distance.
%             Segments may be flipped (start/end swapped) if that
%             brings the start closer to the previous endpoint.
%   lastXY  - [x y] final endpoint after all segments.
%
% The algorithm picks the nearest unvisited segment start (or end)
% from the current position, optionally flipping the segment to
% minimize travel.
%
% See also: order_serpentine, build_toolpath

    if isempty(segs)
        lastXY = seedXY;
        return;
    end

    N = size(segs, 1);
    cur = seedXY(:).';
    orderedSegs = zeros(N, 4);

    % Shrinking set of remaining segment indices (swap-remove on pick) avoids
    % rescanning a logical `used` mask every step.
    live  = (1:N).';
    nLive = N;

    for k = 1:N
        idx = live(1:nLive);
        P1 = segs(idx, 1:2);
        P2 = segs(idx, 3:4);
        d1 = sum((P1 - cur).^2, 2);
        d2 = sum((P2 - cur).^2, 2);
        [mn1, j1] = min(d1);
        [mn2, j2] = min(d2);
        if mn1 <= mn2
            j = j1;  bestFlip = false;
        else
            j = j2;  bestFlip = true;
        end

        s = segs(idx(j), :);
        if bestFlip
            s = [s(3) s(4) s(1) s(2)];  % flip segment direction
        end

        orderedSegs(k, :) = s;
        cur = s(3:4);  % move to endpoint

        live(j) = live(nLive);   % swap-remove picked index
        nLive   = nLive - 1;
    end

    segs = orderedSegs;
    lastXY = cur;
end
