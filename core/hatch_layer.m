function segs = hatch_layer(contour2d, angle_deg, hatch_spacing, bbox, coord_mode, tol, varargin)
% HATCH_LAYER  Generate parallel scan lines at arbitrary angle, clipped to contour.
%
%   segs = hatch_layer(contour2d, angle_deg, hatch_spacing, bbox, coord_mode, tol)
%   segs = hatch_layer(..., 'Overrun', 0.001)
%
% INPUTS:
%   contour2d    - Nx4 matrix [x1 y1 x2 y2] of 2D contour segments defining
%                  the slice boundary at this Z layer.
%   angle_deg    - Scan angle in degrees:
%                    0   = X-directed scan (horizontal lines, Y increments)
%                    90  = Y-directed scan (vertical lines, X increments)
%                    45  = diagonal scan, etc.
%   hatch_spacing - Distance between parallel scan lines (mm)
%   bbox         - [xmin ymin xmax ymax] bounding box (mm)
%   coord_mode   - 'centers' or 'edges' (placement of segment endpoints)
%   tol          - Geometric tolerance (mm)
%
% OPTIONAL NAME-VALUE:
%   'Overrun'    - Extend each scan segment start/end by this amount (mm).
%                  Helps ensure full polymerization at boundaries. Default: 0.
%
% OUTPUT:
%   segs         - Mx4 matrix [x1 y1 x2 y2] of scan segments in original
%                  coordinate frame (mm). NOT yet serpentine-ordered.
%
% ALGORITHM:
%   1. Rotate contour segments by -angle_deg so desired scan direction
%      becomes horizontal.
%   2. Generate horizontal scan lines across the rotated bounding box.
%   3. For each scan line, find intersections with rotated contour (ray casting).
%   4. Pair intersections into inside-segments (handles holes correctly).
%   5. Rotate all segments back by +angle_deg to the original frame.
%
% This single code path handles ANY angle identically.
% Correctly handles: holes, islands, concave shapes, thin walls.
%
% See also: trace_contour, build_toolpath, order_serpentine, slice_mesh

    % ---- Parse optional arguments ----
    p = inputParser;
    addParameter(p, 'Overrun', 0, @isnumeric);
    parse(p, varargin{:});
    overrun = p.Results.Overrun;

    if isempty(contour2d) || hatch_spacing <= 0
        segs = zeros(0, 4);
        return;
    end

    if size(contour2d, 2) ~= 4
        error('hatch_layer:badInput', 'contour2d must be Nx4 [x1 y1 x2 y2].');
    end

    nContour = size(contour2d, 1);

    % ---- 1. Rotation setup ----
    theta = -angle_deg * pi / 180;
    cosA = cos(theta);  sinA = sin(theta);

    % Rotate contour segments (vectorized)
    rx1 = cosA * contour2d(:,1) - sinA * contour2d(:,2);
    ry1 = sinA * contour2d(:,1) + cosA * contour2d(:,2);
    rx2 = cosA * contour2d(:,3) - sinA * contour2d(:,4);
    ry2 = sinA * contour2d(:,3) + cosA * contour2d(:,4);

    % Rotated bounding box
    allRx = [rx1; rx2];
    allRy = [ry1; ry2];
    rXmin = min(allRx) - hatch_spacing;
    rXmax = max(allRx) + hatch_spacing;
    rYmin = min(allRy);
    rYmax = max(allRy);

    % ---- 2. Generate horizontal scan lines in rotated frame ----
    if strcmp(coord_mode, 'centers')
        yLines = (rYmin + hatch_spacing/2) : hatch_spacing : rYmax;
    else
        yLines = rYmin : hatch_spacing : rYmax;
    end

    if isempty(yLines)
        segs = zeros(0, 4);
        return;
    end

    % ---- 3. Vectorized ray-cast ----
    dy_seg = ry2 - ry1;
    dx_seg = rx2 - rx1;
    nonHoriz = abs(dy_seg) > tol;

    rx1f = rx1(nonHoriz);  ry1f = ry1(nonHoriz);
    ry2f = ry2(nonHoriz);
    dx_f = dx_seg(nonHoriz);
    dy_f = dy_seg(nonHoriz);

    nLines = numel(yLines);
    ryLoF = min(ry1f, ry2f);
    ryHiF = max(ry1f, ry2f);
    [buckets, useBuckets] = buildLineBuckets(ryLoF, ryHiF, yLines(1), hatch_spacing, nLines, tol);

    % Preallocate
    maxSegs = nLines * 10;
    segBuf = zeros(maxSegs, 4);
    segCount = 0;

    for li = 1:nLines
        yLine = yLines(li);

        % Parametric t for all contour segments
        idx = lineCandidateIndices(li, buckets, useBuckets, yLine, ry1f, ry2f, tol);
        if isempty(idx), continue; end

        t_all = (yLine - ry1f(idx)) ./ dy_f(idx);

        % Valid intersections: 0 <= t < 1
        valid = (t_all >= -tol) & (t_all < 1 + tol);
        if ~any(valid), continue; end

        % X coordinates of intersections
        hitIdx = idx(valid);
        xHits = rx1f(hitIdx) + t_all(valid) .* dx_f(hitIdx);
        xHits = sort(xHits);

        xHits = mergeHits(xHits, tol);

        % ---- Odd-crossing recovery ----
        % If odd number of crossings (degenerate tangent), try multiple strategies
        if mod(numel(xHits), 2) == 1
            % Strategy 1: Jitter the scan line slightly and re-intersect
            yJitter = yLine + hatch_spacing * 0.01;
            idxJ = find(yJitter >= ryLoF - tol & yJitter <= ryHiF + tol);
            t_j = (yJitter - ry1f(idxJ)) ./ dy_f(idxJ);
            valid_j = (t_j >= -tol) & (t_j < 1 + tol);
            if any(valid_j)
                hitIdxJ = idxJ(valid_j);
                xHitsJ = rx1f(hitIdxJ) + t_j(valid_j) .* dx_f(hitIdxJ);
                xHitsJ = sort(xHitsJ);
                xHitsJ = mergeHits(xHitsJ, tol);
                if mod(numel(xHitsJ), 2) == 0
                    xHits = xHitsJ;  % Use jittered result
                else
                    xHits = xHits(1:end-1);  % Fallback: drop last
                end
            else
                xHits = xHits(1:end-1);
            end
        end

        if numel(xHits) < 2, continue; end

        % ---- Create scan segments from entry/exit pairs ----
        % Pairs: (1,2), (3,4), ... correctly handles holes
        % A line crossing through a hole will produce: enter_outer, exit_outer_into_hole,
        % enter_outer_from_hole, exit_outer -> pairs: (1,2) and (3,4)
        for k = 1:2:numel(xHits)
            xStart = xHits(k);
            xEnd   = xHits(k+1);

            if abs(xEnd - xStart) < tol, continue; end

            % Apply overrun extension
            if overrun > 0
                xStart = xStart - overrun;
                xEnd   = xEnd   + overrun;
            end

            segCount = segCount + 1;
            if segCount > maxSegs
                segBuf = [segBuf; zeros(maxSegs, 4)]; %#ok<AGROW>
                maxSegs = maxSegs * 2;
            end
            segBuf(segCount, :) = [xStart, yLine, xEnd, yLine];
        end
    end

    rotSegs = segBuf(1:segCount, :);

    if segCount == 0
        segs = zeros(0, 4);
        return;
    end

    % ---- 5. Rotate segments back to original frame ----
    cosB = cos(-theta);  sinB = sin(-theta);

    ox1 = cosB * rotSegs(:,1) - sinB * rotSegs(:,2);
    oy1 = sinB * rotSegs(:,1) + cosB * rotSegs(:,2);
    ox2 = cosB * rotSegs(:,3) - sinB * rotSegs(:,4);
    oy2 = sinB * rotSegs(:,3) + cosB * rotSegs(:,4);

    segs = [ox1, oy1, ox2, oy2];
end

function [buckets, useBuckets] = buildLineBuckets(loSeg, hiSeg, firstLineCoord, spacing, nLines, tol)
    buckets = cell(nLines, 1);
    useBuckets = true;

    nSeg = numel(loSeg);
    if nSeg == 0
        return;
    end

    firstLine = ceil((loSeg - tol - firstLineCoord) / spacing + 1);
    lastLine  = floor((hiSeg + tol - firstLineCoord) / spacing + 1);
    valid = firstLine <= nLines & lastLine >= 1;
    if ~any(valid)
        return;
    end

    src = find(valid);
    firstLine = max(1, firstLine(src));
    lastLine  = min(nLines, lastLine(src));
    lineCounts = lastLine - firstLine + 1;
    totalPairs = sum(lineCounts);
    maxPairs = max(1000000, 50 * nSeg);

    if totalPairs > maxPairs
        buckets = cell(0, 1);
        useBuckets = false;
        return;
    end

    lineIdx = zeros(totalPairs, 1);
    segIdx = zeros(totalPairs, 1);
    pos = 1;
    for q = 1:numel(src)
        n = lineCounts(q);
        dst = pos:(pos + n - 1);
        lineIdx(dst) = firstLine(q):lastLine(q);
        segIdx(dst) = src(q);
        pos = pos + n;
    end

    [lineIdx, order] = sort(lineIdx);
    segIdx = segIdx(order);
    breaks = [1; find(diff(lineIdx) ~= 0) + 1; numel(lineIdx) + 1];
    for b = 1:numel(breaks)-1
        lineNumber = lineIdx(breaks(b));
        buckets{lineNumber} = segIdx(breaks(b):breaks(b+1)-1);
    end
end

function idx = lineCandidateIndices(lineNumber, buckets, useBuckets, lineCoord, y1, y2, tol)
    if useBuckets
        idx = buckets{lineNumber};
    else
        idx = find(lineCoord >= min(y1, y2) - tol & lineCoord <= max(y1, y2) + tol);
    end
end

function merged = mergeHits(hits, tol)
    if numel(hits) <= 1
        merged = hits;
        return;
    end
    merged = hits(1);
    for k = 2:numel(hits)
        if hits(k) - merged(end) > tol
            merged(end+1) = hits(k); %#ok<AGROW>
        end
    end
    merged = merged(:);
end
