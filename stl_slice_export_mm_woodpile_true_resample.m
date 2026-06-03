%% stl_slice_export_mm_woodpile_true_resample.m
% STL -> XY raster line segments (mm), with:
%   - Scaling to TargetMaxXY/TargetMaxDim
%   - True orthogonal resampling for woodpile:
%       Odd layers: horizontal scanlines (X-directed writing)
%       Even layers: vertical scanlines (Y-directed writing)
%   - Optional serpentine traversal within each layer
%   - Greedy nearest-neighbor path ordering within each layer
%   - Per-layer relative XY (corner origin at 0,0)
%   - Z-hop at CURRENT XY to the next layer (no return-to-origin)
% Output rows: [X1 Y1 Z1 X2 Y2 Z2] in mm, TAB-separated.
%
% Speed/progress changes in this version:
%   - Console progress with elapsed time and ETA.
%   - Candidate triangle prefiltering by each triangle's Z range.
%   - Preallocated run buffers instead of repeated array growth.
%   - Scanline bucketing so each row/column checks only nearby contours.
%   - Vectorized binary STL reading.
%   - Vectorized greedy nearest-neighbor ordering.
%   - Safer Z plane placement and scanline index rounding.

% ========================= USER PARAMETERS (mm) =========================
STLPath      = fullfile('examples','models','final_lut_height_map_6um_pixel_exact_base0p5um.stl');
OutTxt       = fullfile('output','Final_YH_05um.txt');   % tab-separated text

% Footprint & in-plane resolution (mm)
TargetMaxXY  = 1.005;      % scalar max XY span, or [maxX maxY] fit box
XYPitch      = 0.0004;     % grid pitch / hatch spacing (0.0004 mm = 0.4 um)
SquareGrid   = true;       % force Nx==Ny (recommended for woodpile)

% Vertical slicing (mm)
DZ           = 0.0005;     % slice thickness (0.0005 mm = 0.5 um)

% Layer direction & path controls
WoodpileMode = true;       % TRUE orthogonal resampling (overrides SwapXYOnOdd)
SwapXYOnOdd  = false;      % legacy fallback only when WoodpileMode=false
Serpentine   = true;       % boustrophedon traversal within each layer
OptimizePath = true;       % greedy nearest-neighbor ordering (segment chaining)

% Greedy ordering is O(N^2). If a layer has more rows than this, keep the
% serpentine order for that layer. Set to Inf to force greedy ordering always.
OptimizeMaxSegments = 15000;

% Z values in file
ZAsIndex     = false;      % false: physical Z in mm; true: layer indices (1..nLayers)
StageZConvention = true;   % true: write physical Z as negative stage motion

% Coordinate placement along runs
% 'centers' -> follow grid centers (recommended)
% 'edges'   -> span voxel edges along the scan direction
CoordMode    = 'centers';

% Optional overall scaling overrides (mm)
Scale        = 1.0;        % used only if both TargetMaxXY and TargetMaxDim are empty
TargetMaxDim = [];         % final max(X,Y,Z) span; used only if TargetMaxXY empty

% Misc
Margin       = 0.0;        % extra XY padding (mm)
Tol          = 1e-9;       % geometric tolerance (mm)
OutputSignificantDigits = 6; % compact TXT output, e.g. 0.0002

% Progress reminders
Verbose              = true;
ProgressEveryLayers  = 10; % also reports first/last layer
ProgressEverySeconds = 5;  % report if this much time passed since last reminder
% =======================================================================

%% Main
ExitCode = 1; ErrMsg = ''; Segments_mm = zeros(0,6);
try
    tJob = tic;

    assert(~isempty(STLPath) && (ischar(STLPath) || isstring(STLPath)), 'STLPath required.');
    STLPath = char(STLPath);
    assert(exist(STLPath,'file')==2, 'STL not found: %s', STLPath);
    if isempty(OutTxt), OutTxt = 'stl_slices_mm_woodpile.tsv'; end
    OutTxt = char(OutTxt);

    assert(DZ > 0, 'DZ must be > 0 (mm)');
    assert(XYPitch > 0, 'XYPitch must be > 0 (mm)');
    assert(OutputSignificantDigits >= 4 && OutputSignificantDigits <= 15, 'OutputSignificantDigits must be between 4 and 15.');
    OutputSignificantDigits = round(OutputSignificantDigits);
    assert(ischar(CoordMode) || isstring(CoordMode), 'CoordMode must be centers or edges.');
    CoordMode = char(CoordMode);
    assert(any(strcmpi(CoordMode, {'centers','edges'})), 'CoordMode must be centers or edges.');
    Tol = max(Tol,1e-12);
    ProgressEveryLayers = max(1, round(ProgressEveryLayers));
    ProgressEverySeconds = max(0.1, ProgressEverySeconds);

    % ---- Read STL ----
    if Verbose, fprintf('[%s] Reading STL: %s\n', datestr(now,'HH:MM:SS'), STLPath); end
    [F,V] = read_stl_any(STLPath);
    assert(~isempty(F) && ~isempty(V), 'Failed to parse STL geometry.');

    % ---- Compute scaling to target mm size ----
    xmin0 = min(V(:,1)); xmax0 = max(V(:,1));
    ymin0 = min(V(:,2)); ymax0 = max(V(:,2));
    zmin0 = min(V(:,3)); zmax0 = max(V(:,3));
    spanX0 = xmax0 - xmin0; spanY0 = ymax0 - ymin0; spanZ0 = zmax0 - zmin0;

    S = choose_scale(spanX0, spanY0, spanZ0, Scale, TargetMaxXY, TargetMaxDim);
    V = V * S;  % isotropic scaling; treat as mm

    % ---- Bounding boxes & grid (mm) ----
    xmin = min(V(:,1)); xmax = max(V(:,1));
    ymin = min(V(:,2)); ymax = max(V(:,2));
    zmin = min(V(:,3)); zmax = max(V(:,3));

    xmin = xmin - Margin; xmax = xmax + Margin;
    ymin = ymin - Margin; ymax = ymax + Margin;

    dx = XYPitch; dy = XYPitch;
    spanX = xmax - xmin; spanY = ymax - ymin;

    if SquareGrid
        maxSpan = max(spanX, spanY);
        Nx = max(1, ceil(maxSpan/dx));
        Ny = Nx;
        xmax = xmin + Nx*dx;
        ymax = ymin + Ny*dy;
    else
        Nx = max(1, ceil(spanX/dx));
        Ny = max(1, ceil(spanY/dy));
        xmax = xmin + Nx*dx;
        ymax = ymin + Ny*dy;
    end

    % Z-planes are placed at the center of each slice slab. The final layer
    % is centered inside the remaining partial slab instead of above zmax.
    zHeight = zmax - zmin;
    assert(zHeight >= -Tol, 'Invalid STL Z bounds.');
    if zHeight <= Tol
        nLayers = 1;
        zPlanes = (zmin + zmax) / 2;
    else
        nLayers = max(1, ceil(zHeight/DZ));
        zBottoms = zmin + (0:nLayers-1) * DZ;
        zTops = min(zBottoms + DZ, zmax);
        zPlanes = (zBottoms + zTops) / 2;
    end

    % Precompute triangle Z ranges so each layer only checks triangles that
    % can actually intersect that layer's plane.
    vz = V(:,3);
    triZ = vz(F);
    triZmin = min(triZ, [], 2);
    triZmax = max(triZ, [], 2);

    if Verbose
        fprintf('[%s] STL: %d faces, %d vertices, scale=%.10g\n', datestr(now,'HH:MM:SS'), size(F,1), size(V,1), S);
        fprintf('[%s] Grid: Nx=%d, Ny=%d, layers=%d, pitch=%.10g mm, DZ=%.10g mm\n', datestr(now,'HH:MM:SS'), Nx, Ny, nLayers, XYPitch, DZ);
        fprintf('[%s] Output target: %s\n', datestr(now,'HH:MM:SS'), OutTxt);
    end

    % ---- Slice & rasterize ----
    segments_all = cell(max(1, 2*nLayers-1), 1);
    outCell = 0;

    % Starting seed for first layer (relative coords use corner origin)
    seedXY = [0, 0];
    tLastProgress = tic;
    totalLayerRows = 0;
    totalRuns = 0;
    totalContours = 0;
    totalOddScanlines = 0;
    skippedGreedyLayers = 0;

    for L = 1:nLayers
        tLayer = tic;
        z = zPlanes(L);  % mm
        cand = find(triZmin <= z + Tol & triZmax >= z - Tol);

        if Verbose && should_report_start(L, nLayers, ProgressEveryLayers, tLastProgress, ProgressEverySeconds)
            fprintf('[%s] Layer %d/%d started: z=%.10g, candidate triangles=%d\n', datestr(now,'HH:MM:SS'), L, nLayers, z, numel(cand));
            tLastProgress = tic;
        end

        % 1) Intersections with plane z = const -> seg2d: Mx4 [x1 y1 x2 y2] (mm abs)
        seg2d = slice_triangles_at_z(F, V, z, Tol, cand);
        totalContours = totalContours + size(seg2d,1);

        % 2) TRUE orientation-specific scanline fill (woodpile)
        runs = zeros(0,3);   % [lineIndex, startIdx, endIdx] in the scan direction
        X1mm=[]; Y1mm=[]; X2mm=[]; Y2mm=[]; % ensure existence

        if ~isempty(seg2d)
            if WoodpileMode
                useVertical = mod(L,2)==0; % even layers are Y-directed
            else
                useVertical = SwapXYOnOdd && mod(L,2)==1;
            end

            if useVertical
                % EVEN LAYER: VERTICAL SCANLINES (constant X) -> Y-directed segments
                [runs, oddScanlines] = scanline_runs_vertical(seg2d, xmin, ymin, dx, dy, Nx, Ny, Tol);
                totalOddScanlines = totalOddScanlines + oddScanlines;
                totalRuns = totalRuns + size(runs,1);

                Xi1 = runs(:,1);  Yi1 = runs(:,2);
                Xi2 = runs(:,1);  Yi2 = runs(:,3);

                if Serpentine && ~isempty(runs)
                    [Xi1,Yi1,Xi2,Yi2] = serpentine_vertical(Xi1,Yi1,Xi2,Yi2);
                end

                [X1mm,Y1mm,X2mm,Y2mm] = idx_to_mm_vertical(Xi1,Yi1,Xi2,Yi2,dx,dy,CoordMode);
            else
                % ODD LAYER: HORIZONTAL SCANLINES (constant Y) -> X-directed segments
                [runs, oddScanlines] = scanline_runs_horizontal(seg2d, xmin, ymin, dx, dy, Nx, Ny, Tol);
                totalOddScanlines = totalOddScanlines + oddScanlines;
                totalRuns = totalRuns + size(runs,1);

                Yi1 = runs(:,1);  Xi1 = runs(:,2);
                Yi2 = runs(:,1);  Xi2 = runs(:,3);

                if Serpentine && ~isempty(runs)
                    [Xi1,Yi1,Xi2,Yi2] = serpentine_horizontal(Xi1,Yi1,Xi2,Yi2);
                end

                [X1mm,Y1mm,X2mm,Y2mm] = idx_to_mm_horizontal(Xi1,Yi1,Xi2,Yi2,dx,dy,CoordMode);
            end
        end

        % 3) Build layer segments with correct Z
        segL = zeros(0,6);
        if ~isempty(X1mm)
            Zval = L;
            if ~ZAsIndex
                Zval = z;
                if StageZConvention
                    Zval = -Zval;
                end
            end
            Z1mm = repmat(Zval, size(X1mm));
            Z2mm = Z1mm;
            segL = [X1mm(:) Y1mm(:) Z1mm(:)  X2mm(:) Y2mm(:) Z2mm(:)];

            % ---- Path optimization: greedy nearest-neighbor ----
            if OptimizePath && size(segL,1) <= OptimizeMaxSegments
                [segL, lastXY] = order_segments_greedy(segL, seedXY);
            elseif OptimizePath
                skippedGreedyLayers = skippedGreedyLayers + 1;
                lastXY = segL(end,4:5);
            else
                lastXY = segL(end,4:5);
            end
        else
            lastXY = seedXY; % empty layer
        end

        totalLayerRows = totalLayerRows + size(segL,1);

        % Append this layer's segments
        outCell = outCell + 1;
        segments_all{outCell,1} = segL;

        % ---- Inter-layer transition: Z-hop at CURRENT XY (no return to origin) ----
        if L < nLayers
            z_next = zPlanes(L+1);
            if ZAsIndex
                ZcurVal = L;       ZnxtVal = L + 1;
            else
                ZcurVal = z;       ZnxtVal = z_next;
                if StageZConvention
                    ZcurVal = -ZcurVal;
                    ZnxtVal = -ZnxtVal;
                end
            end
            outCell = outCell + 1;
            segments_all{outCell,1} = [lastXY(1) lastXY(2) ZcurVal,  lastXY(1) lastXY(2) ZnxtVal];
            seedXY = lastXY;
        end

        if Verbose && should_report_done(L, nLayers, ProgressEveryLayers, tLastProgress, ProgressEverySeconds)
            elapsed = toc(tJob);
            eta = elapsed * (nLayers - L) / max(L,1);
            fprintf('[%s] Layer %d/%d done (%.1f%%): contours=%d, runs=%d, rows=%d, layer=%s, elapsed=%s, ETA=%s\n', ...
                datestr(now,'HH:MM:SS'), L, nLayers, 100*L/nLayers, size(seg2d,1), size(runs,1), size(segL,1), ...
                format_duration(toc(tLayer)), format_duration(elapsed), format_duration(eta));
            tLastProgress = tic;
        end
    end

    % ---- Concatenate and write TAB-separated file ----
    Segments_mm = vertcat(segments_all{1:outCell});
    [zeroLengthRows, outOfBoundsRows] = segment_quality_counts(Segments_mm, Nx, Ny, dx, dy, Tol);

    outDir = fileparts(OutTxt);
    if ~isempty(outDir) && ~exist(outDir,'dir'), mkdir(outDir); end
    fidw = fopen(OutTxt,'w');
    assert(fidw>=0, 'Cannot open output file: %s', OutTxt);
    cleanupFile = onCleanup(@() fclose(fidw));
    valueFmt = sprintf('%%.%dg', OutputSignificantDigits);
    fmt = [valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\n'];
    fprintf(fidw, fmt, Segments_mm.');
    clear cleanupFile;

    % ---- Report ----
    fprintf('Export (mm) complete: TRUE woodpile resampling, serpentine=%d, greedy=%d.\n', Serpentine, OptimizePath);
    fprintf(' Grid: Nx=%d, Ny=%d, layers=%d\n', Nx, Ny, nLayers);
    fprintf(' Target XY: %s ; pitch=%.10g mm ; DZ=%.10g mm ; stageZ=%d\n', format_target(TargetMaxXY), XYPitch, DZ, StageZConvention);
    fprintf(' Contour segments checked into runs: %d ; raster runs: %d\n', totalContours, totalRuns);
    fprintf(' Layer writing rows: %d ; Z-hop rows: %d\n', totalLayerRows, max(0,nLayers-1));
    if totalOddScanlines > 0
        warning('Skipped %d scanline(s) with unresolved odd contour-intersection counts. This can indicate an open/non-manifold STL or a slicing degeneracy.', totalOddScanlines);
    end
    if outOfBoundsRows > 0
        warning('Output contains %d row(s) with XY coordinates outside the generated grid bounds.', outOfBoundsRows);
    end
    if zeroLengthRows > 0
        fprintf(' Note: %d zero-length row(s) found. In centers mode these can happen for one-voxel runs; use CoordMode=''edges'' if your printer ignores point-like writes.\n', zeroLengthRows);
    end
    if skippedGreedyLayers > 0
        fprintf(' Greedy path ordering skipped on %d layer(s) above OptimizeMaxSegments=%g.\n', skippedGreedyLayers, OptimizeMaxSegments);
    end
    fprintf(' Segments written: %d rows -> %s\n', size(Segments_mm,1), OutTxt);
    fprintf(' Total elapsed: %s\n', format_duration(toc(tJob)));
    ExitCode = 0;

catch ME
    ErrMsg = ME.message;
    warning('stl_slice_export_mm_woodpile_true_resample error: %s', ErrMsg);
    ExitCode = 1;
end

%% ------------------ Local helpers (no toolboxes) -------------------
function S = choose_scale(spanX0, spanY0, spanZ0, Scale, TargetMaxXY, TargetMaxDim)
S = Scale;
if ~isempty(TargetMaxXY)
    target = TargetMaxXY(:).';
    assert(numel(target)==1 || numel(target)==2, 'TargetMaxXY must be scalar or [maxX maxY].');
    assert(all(isfinite(target)) && all(target > 0), 'TargetMaxXY must be positive.');
    if numel(target) == 1
        base = max(spanX0, spanY0);
        assert(base > 0, 'Zero XY span in STL.');
        S = target / base;
    else
        ratios = [];
        if spanX0 > 0, ratios(end+1) = target(1) / spanX0; end %#ok<AGROW>
        if spanY0 > 0, ratios(end+1) = target(2) / spanY0; end %#ok<AGROW>
        assert(~isempty(ratios), 'Zero XY span in STL.');
        S = min(ratios);
    end
elseif ~isempty(TargetMaxDim)
    assert(isscalar(TargetMaxDim) && isfinite(TargetMaxDim) && TargetMaxDim > 0, 'TargetMaxDim must be positive scalar.');
    base = max([spanX0, spanY0, spanZ0]);
    assert(base > 0, 'Zero size in STL.');
    S = TargetMaxDim / base;
end
assert(isfinite(S) && S > 0, 'Scale must be > 0');
end

function seg2d = slice_triangles_at_z(F, V, z, Tol, cand)
% Intersect candidate triangles with plane z = const.
edges = [1 2; 2 3; 3 1];
seg2d = zeros(numel(cand),4);
nseg = 0;

for ci = 1:numel(cand)
    tri = V(F(cand(ci),:),:);
    d = tri(:,3) - z;
    P = zeros(3,3);
    np = 0;

    for e = 1:3
        i1 = edges(e,1); i2 = edges(e,2);
        d1 = d(i1); d2 = d(i2);
        p1 = tri(i1,:); p2 = tri(i2,:);

        if abs(d1)<=Tol && abs(d2)<=Tol
            continue; % coplanar edge: ignored for zero-thickness slicing
        elseif abs(d1)<=Tol
            np = np + 1; P(np,:) = p1;
        elseif abs(d2)<=Tol
            np = np + 1; P(np,:) = p2;
        elseif d1*d2 < 0
            t = d1/(d1 - d2);
            np = np + 1; P(np,:) = p1 + t*(p2-p1);
        end
    end

    if np < 2, continue; end
    Pu = unique_tol_rows(P(1:np,:), Tol);
    if size(Pu,1) == 2
        pA = Pu(1,:); pB = Pu(2,:);
    elseif size(Pu,1) > 2
        [pA,pB] = farthest_pair(Pu);
    else
        continue;
    end

    nseg = nseg + 1;
    seg2d(nseg,:) = [pA(1) pA(2) pB(1) pB(2)];
end

seg2d = seg2d(1:nseg,:);
end

function Pu = unique_tol_rows(P, Tol)
Pr = round(P./Tol).*Tol;
[~, ia] = unique(Pr,'rows','stable');
Pu = P(ia,:);
end

function [runs, oddScanlines] = scanline_runs_vertical(seg2d, xmin, ymin, dx, dy, Nx, Ny, Tol)
% Vertical scanlines (constant X) -> runs along Y.
x1s = seg2d(:,1); y1s = seg2d(:,2);
x2s = seg2d(:,3); y2s = seg2d(:,4);
denom = x2s - x1s;
valid = abs(denom) > Tol; % ignore segments parallel to scanline

x1s = x1s(valid); y1s = y1s(valid);
x2s = x2s(valid); y2s = y2s(valid);
denom = denom(valid);
xloSeg = min(x1s, x2s);
xhiSeg = max(x1s, x2s);
[buckets, useBuckets] = build_scanline_buckets(xloSeg, xhiSeg, xmin, dx, Nx, Tol);

runs = zeros(max(1024, Nx), 3);
nr = 0;
oddScanlines = 0;

for j = 1:Nx
    xj = xmin + (j-0.5)*dx;
    idx = scanline_candidate_indices(j, buckets, useBuckets, xj, xloSeg, xhiSeg, Tol);
    if isempty(idx), continue; end

    t_all = (xj - x1s(idx)) ./ denom(idx);
    sel = (t_all >= 0) & (t_all < 1);
    if ~any(sel), continue; end

    y1a = y1s(idx);
    y2a = y2s(idx);
    yhit = y1a(sel) + t_all(sel).*(y2a(sel) - y1a(sel));
    yhit = sort(yhit);

    if mod(numel(yhit),2)==1
        oddScanlines = oddScanlines + 1;
        continue;
    end
    for k = 1:2:numel(yhit)
        ylo = yhit(k);
        yhi = yhit(k+1);
        if yhi <= ylo + Tol, continue; end
        [yStart, yEnd] = interval_to_center_indices(ylo, yhi, ymin, dy, Ny, Tol);
        if yEnd < yStart, continue; end
        [runs, nr] = append_run(runs, nr, j, yStart, yEnd);
    end
end

runs = runs(1:nr,:);
end

function [runs, oddScanlines] = scanline_runs_horizontal(seg2d, xmin, ymin, dx, dy, Nx, Ny, Tol)
% Horizontal scanlines (constant Y) -> runs along X.
x1s = seg2d(:,1); y1s = seg2d(:,2);
x2s = seg2d(:,3); y2s = seg2d(:,4);
denom = y2s - y1s;
valid = abs(denom) > Tol; % ignore segments parallel to scanline

x1s = x1s(valid); y1s = y1s(valid);
x2s = x2s(valid); y2s = y2s(valid);
denom = denom(valid);
yloSeg = min(y1s, y2s);
yhiSeg = max(y1s, y2s);
[buckets, useBuckets] = build_scanline_buckets(yloSeg, yhiSeg, ymin, dy, Ny, Tol);

runs = zeros(max(1024, Ny), 3);
nr = 0;
oddScanlines = 0;

for irow = 1:Ny
    yi = ymin + (irow-0.5)*dy;
    idx = scanline_candidate_indices(irow, buckets, useBuckets, yi, yloSeg, yhiSeg, Tol);
    if isempty(idx), continue; end

    t_all = (yi - y1s(idx)) ./ denom(idx);
    sel = (t_all >= 0) & (t_all < 1);
    if ~any(sel), continue; end

    x1a = x1s(idx);
    x2a = x2s(idx);
    xhit = x1a(sel) + t_all(sel).*(x2a(sel) - x1a(sel));
    xhit = sort(xhit);

    if mod(numel(xhit),2)==1
        oddScanlines = oddScanlines + 1;
        continue;
    end
    for k = 1:2:numel(xhit)
        xlo = xhit(k);
        xhi = xhit(k+1);
        if xhi <= xlo + Tol, continue; end
        [xStart, xEnd] = interval_to_center_indices(xlo, xhi, xmin, dx, Nx, Tol);
        if xEnd < xStart, continue; end
        [runs, nr] = append_run(runs, nr, irow, xStart, xEnd);
    end
end

runs = runs(1:nr,:);
end

function [buckets, useBuckets] = build_scanline_buckets(loSeg, hiSeg, origin, pitch, nLines, Tol)
% Map each contour segment to the scanlines whose centers can intersect it.
% If a pathological layer would require a huge bucket expansion, fall back
% to the old per-line range mask to avoid a large temporary allocation.
buckets = cell(nLines, 1);
useBuckets = true;

nSeg = numel(loSeg);
if nSeg == 0
    return;
end

tolIdx = Tol / pitch;
firstLine = ceil((loSeg - origin) / pitch + 0.5 - tolIdx);
lastLine  = floor((hiSeg - origin) / pitch + 0.5 + tolIdx);

valid = firstLine <= nLines & lastLine >= 1;
if ~any(valid)
    return;
end

src = find(valid);
firstLine = max(1, firstLine(src));
lastLine  = min(nLines, lastLine(src));
lineCounts = lastLine - firstLine + 1;
totalPairs = sum(lineCounts);

% A local height-map contour usually touches only a few scanlines. If that
% stops being true, buckets can cost more memory than they save in runtime.
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
    j = lineIdx(breaks(b));
    buckets{j} = segIdx(breaks(b):breaks(b+1)-1);
end
end

function idx = scanline_candidate_indices(lineNumber, buckets, useBuckets, lineCoord, loSeg, hiSeg, Tol)
if useBuckets
    idx = buckets{lineNumber};
else
    idx = find(lineCoord >= loSeg - Tol & lineCoord <= hiSeg + Tol);
end
end

function [iStart, iEnd] = interval_to_center_indices(lo, hi, origin, pitch, nMax, Tol)
% Select grid-center indices whose centers lie inside [lo, hi].
tolIdx = min(0.49, Tol / pitch);
iStart = ceil((lo - origin)/pitch + 0.5 - tolIdx);
iEnd   = floor((hi - origin)/pitch + 0.5 + tolIdx);
iStart = max(1, min(nMax, iStart));
iEnd   = max(1, min(nMax, iEnd));
end

function [runs, nr] = append_run(runs, nr, lineIdx, startIdx, endIdx)
nr = nr + 1;
if nr > size(runs,1)
    growBy = max(1024, size(runs,1));
    runs = [runs; zeros(growBy, 3)]; %#ok<AGROW>
end
runs(nr,:) = [lineIdx, startIdx, endIdx];
end

function [Xi1,Yi1,Xi2,Yi2] = serpentine_vertical(Xi1,Yi1,Xi2,Yi2)
% Alternate traversal by column without dynamic output concatenation.
N = numel(Xi1);
order = zeros(N,1);
pos = 0;
cols = unique(Xi1, 'stable');

for k = 1:numel(cols)
    ii = find(Xi1==cols(k));
    [~,ord] = sort(Yi1(ii), 'ascend');
    ii = ii(ord);
    if mod(k,2)==0
        tmp = Yi1(ii); Yi1(ii) = Yi2(ii); Yi2(ii) = tmp;
        ii = flipud(ii);
    end
    n = numel(ii);
    order(pos+1:pos+n) = ii;
    pos = pos + n;
end

order = order(1:pos);
Xi1 = Xi1(order); Yi1 = Yi1(order);
Xi2 = Xi2(order); Yi2 = Yi2(order);
end

function [Xi1,Yi1,Xi2,Yi2] = serpentine_horizontal(Xi1,Yi1,Xi2,Yi2)
% Alternate traversal by row without dynamic output concatenation.
N = numel(Xi1);
order = zeros(N,1);
pos = 0;
rows = unique(Yi1, 'stable');

for k = 1:numel(rows)
    ii = find(Yi1==rows(k));
    [~,ord] = sort(Xi1(ii), 'ascend');
    ii = ii(ord);
    if mod(k,2)==0
        tmp = Xi1(ii); Xi1(ii) = Xi2(ii); Xi2(ii) = tmp;
        ii = flipud(ii);
    end
    n = numel(ii);
    order(pos+1:pos+n) = ii;
    pos = pos + n;
end

order = order(1:pos);
Xi1 = Xi1(order); Yi1 = Yi1(order);
Xi2 = Xi2(order); Yi2 = Yi2(order);
end

function [X1mm, Y1mm, X2mm, Y2mm] = idx_to_mm_vertical(Xi1, Yi1, Xi2, Yi2, dx, dy, mode)
% Vertical scanlines (constant X at column centers) -> Y-directed segments
if strcmpi(mode,'centers')
    X1mm = (Xi1 - 0.5) * dx;   X2mm = (Xi2 - 0.5) * dx;
    Y1mm = (Yi1 - 0.5) * dy;   Y2mm = (Yi2 - 0.5) * dy;
else % 'edges'
    X1mm = (Xi1 - 0.5) * dx;   X2mm = (Xi2 - 0.5) * dx;
    Y1mm = (Yi1 - 1.0) * dy;   Y2mm = (Yi2 - 0.0) * dy;
end
end

function [X1mm, Y1mm, X2mm, Y2mm] = idx_to_mm_horizontal(Xi1, Yi1, Xi2, Yi2, dx, dy, mode)
% Horizontal scanlines (constant Y at row centers) -> X-directed segments
if strcmpi(mode,'centers')
    Y1mm = (Yi1 - 0.5) * dy;   Y2mm = (Yi2 - 0.5) * dy;
    X1mm = (Xi1 - 0.5) * dx;   X2mm = (Xi2 - 0.5) * dx;
else % 'edges'
    Y1mm = (Yi1 - 0.5) * dy;   Y2mm = (Yi2 - 0.5) * dy;
    X1mm = (Xi1 - 1.0) * dx;   X2mm = (Xi2 - 0.0) * dx;
end
end

function [segOrd, lastXY] = order_segments_greedy(seg, seedXY)
% Vectorized greedy nearest-neighbor chaining of segments (can flip segments).
% seg: Nx6 [x1 y1 z1 x2 y2 z2], seedXY: [x y]
if isempty(seg)
    segOrd = seg; lastXY = seedXY; return;
end

N = size(seg,1);
remaining = (1:N).';
cur = seedXY(:).';
segOrd = zeros(N,6);

for k = 1:N
    srem = seg(remaining,:);
    d1 = hypot(srem(:,1)-cur(1), srem(:,2)-cur(2));
    d2 = hypot(srem(:,4)-cur(1), srem(:,5)-cur(2));

    [bestD1, idx1] = min(d1);
    [bestD2, idx2] = min(d2);
    if bestD2 < bestD1
        localIdx = idx2;
        bestflip = true;
    else
        localIdx = idx1;
        bestflip = false;
    end

    best = remaining(localIdx);
    s = seg(best,:);
    if bestflip
        s = [s(4) s(5) s(6)  s(1) s(2) s(3)];
    end

    segOrd(k,:) = s;
    cur = s(4:5);

    % Remove selected row by swapping with the end; order of remaining rows
    % is irrelevant for nearest-neighbor search and this avoids O(N) shifting.
    remaining(localIdx) = remaining(end);
    remaining(end) = [];
end

lastXY = cur;
end

function [pA,pB] = farthest_pair(P)
% Brute-force farthest pair in small point sets.
m = size(P,1); dmax = -inf; ia=1; ib=2;
for a=1:m-1
    for b=a+1:m
        dd = sum((P(a,:)-P(b,:)).^2);
        if dd>dmax, dmax=dd; ia=a; ib=b; end
    end
end
pA = P(ia,:); pB = P(ib,:);
end

function [F,V] = read_stl_any(fname)
% Minimal STL (ASCII or binary). Returns Faces (Nx3) and Vertices (Mx3).
F = []; V = [];
fid = fopen(fname,'r'); if fid<0, return; end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
hdr = fread(fid, 256, '*uint8')'; frewind(fid);
isAscii = false;
if numel(hdr)>=5
    h = char(hdr(1:min(80,end)));
    if strncmpi(strtrim(h), 'solid', 5), isAscii = true; end
end
if isAscii
    try
        txt = fread(fid,'*char')';
        if ~isempty(regexpi(txt,'facet','once')) && ~isempty(regexpi(txt,'vertex','once'))
            pat = '(?i)vertex\s+([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)\s+([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)';
            tok = regexp(txt, pat, 'tokens');
            if ~isempty(tok)
                Vlist = cellfun(@(t) [str2double(t{1}) str2double(t{2}) str2double(t{3})], tok, 'UniformOutput', false);
                Vlist = vertcat(Vlist{:});
                nfaces = size(Vlist,1)/3;
                if abs(nfaces - round(nfaces)) < 1e-9
                    [V,ix] = unique_rows_stable_with_inverse(Vlist);
                    F = reshape(ix, 3, []).';
                end
            end
        end
    catch
        % Fall through to binary.
    end
    if isempty(F) || isempty(V)
        frewind(fid); isAscii = false;
    end
end
if ~isAscii
    fseek(fid,80,'bof');
    nfaces = fread(fid,1,'uint32','l');
    if isempty(nfaces) || nfaces==0, F=[]; V=[]; return; end
    raw = fread(fid, nfaces * 50, 'uint8=>uint8');
    if numel(raw) ~= nfaces * 50
        F=[]; V=[]; return;
    end
    raw = reshape(raw, 50, nfaces);
    vraw = raw(13:48, :); % 9 float32 vertex coordinates per face
    Vlist = double(reshape(typecast(vraw(:), 'single'), 3, nfaces * 3).');
    V = Vlist;
    F = reshape(1:size(Vlist,1), 3, []).';
end
end

function [V, ix] = unique_rows_stable_with_inverse(Vlist)
% Stable unique rows plus inverse index, without relying on newer MATLAB
% unique(...,'stable') third-output behavior.
[Vsorted, ~, icSorted] = unique(Vlist, 'rows');
firstIdx = accumarray(icSorted, (1:size(Vlist,1)).', [], @min);
[~, stableOrder] = sort(firstIdx);
sortedToStable = zeros(size(stableOrder));
sortedToStable(stableOrder) = 1:numel(stableOrder);
V = Vsorted(stableOrder,:);
ix = sortedToStable(icSorted);
end

function [zeroLengthRows, outOfBoundsRows] = segment_quality_counts(seg, Nx, Ny, dx, dy, Tol)
if isempty(seg)
    zeroLengthRows = 0;
    outOfBoundsRows = 0;
    return;
end

finiteRows = all(isfinite(seg), 2);
if any(~finiteRows)
    warning('Output contains %d row(s) with NaN or Inf values.', sum(~finiteRows));
end

dxyz = sqrt((seg(:,4)-seg(:,1)).^2 + (seg(:,5)-seg(:,2)).^2 + (seg(:,6)-seg(:,3)).^2);
zeroLengthRows = sum(dxyz <= Tol);

xBad = seg(:,1) < -Tol | seg(:,4) < -Tol | seg(:,1) > Nx*dx + Tol | seg(:,4) > Nx*dx + Tol;
yBad = seg(:,2) < -Tol | seg(:,5) < -Tol | seg(:,2) > Ny*dy + Tol | seg(:,5) > Ny*dy + Tol;
outOfBoundsRows = sum(xBad | yBad);
end

function tf = should_report_start(L, nLayers, progressEveryLayers, tLastProgress, progressEverySeconds)
tf = L == 1 || L == nLayers || mod(L-1, progressEveryLayers) == 0 || toc(tLastProgress) >= progressEverySeconds;
end

function tf = should_report_done(L, nLayers, progressEveryLayers, tLastProgress, progressEverySeconds)
tf = L == 1 || L == nLayers || mod(L, progressEveryLayers) == 0 || toc(tLastProgress) >= progressEverySeconds;
end

function s = format_duration(sec)
if ~isfinite(sec) || sec < 0
    s = 'unknown';
    return;
end
if sec < 60
    s = sprintf('%.1fs', sec);
elseif sec < 3600
    total = round(sec);
    s = sprintf('%dm%02ds', floor(total/60), mod(total,60));
else
    total = round(sec);
    s = sprintf('%dh%02dm', floor(total/3600), floor(mod(total,3600)/60));
end
end

function s = format_target(TargetMaxXY)
if isempty(TargetMaxXY)
    s = 'not set';
elseif isscalar(TargetMaxXY)
    s = sprintf('%.10g mm max XY span', TargetMaxXY);
else
    s = sprintf('[%.10g %.10g] mm fit box', TargetMaxXY(1), TargetMaxXY(2));
end
end
