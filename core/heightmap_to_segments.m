function [segments_mm, info] = heightmap_to_segments(height_map, varargin)
% HEIGHTMAP_TO_SEGMENTS  Rasterize a height map directly into write segments.
%
%   segments_mm = heightmap_to_segments(height_map, ...)
%
% This path does not slice STL contours. It treats height_map(row,col) as the
% maximum printable height at that XY cell and writes a grid point/line when
% height_map >= current layer center. This is the stable path for pixel-exact
% height-map STL/CSV data.
%
% Name-value parameters:
%   SourcePitch       : Source cell pitch in source units. Default 1.
%   TargetMaxXY       : Final max XY span in mm. Scalar or [maxX maxY].
%   BaseHeight        : Support base height in source units. Default 0.
%   BaseHeight_mm     : Support base height in mm. Default [].
%   HatchPitch_mm     : Output scanline pitch in mm. Default 0.0004.
%   LayerHeight_mm    : Z layer thickness in mm. Default 0.0005.
%   StageZConvention  : If true, output Z is negative. Default true.
%   WoodpileMode      : Alternate X/Y writing by layer. Default true.
%   Serpentine        : Alternate scan direction by line. Default true.
%   CoordMode         : 'edges' or 'centers'. Default 'edges'.
%   Tolerance_mm      : Height comparison tolerance. Default 1e-12.

    cfg = parse_inputs(varargin{:});

    assert(isnumeric(height_map) && ismatrix(height_map) && ~isempty(height_map), ...
        'heightmap_to_segments:badHeightMap', 'height_map must be a non-empty numeric matrix.');
    height_map = double(height_map);
    height_map(~isfinite(height_map)) = 0;
    height_map = max(height_map, 0);

    [nySrc, nxSrc] = size(height_map);
    sourcePitch = cfg.SourcePitch(:).';
    if numel(sourcePitch) == 1
        sourcePitch = [sourcePitch sourcePitch];
    end
    assert(numel(sourcePitch) == 2 && all(sourcePitch > 0), ...
        'heightmap_to_segments:badPitch', 'SourcePitch must be positive scalar or [xPitch yPitch].');

    spanX0 = nxSrc * sourcePitch(1);
    spanY0 = nySrc * sourcePitch(2);
    scaleToMm = choose_scale(spanX0, spanY0, cfg.TargetMaxXY);

    spanX = spanX0 * scaleToMm;
    spanY = spanY0 * scaleToMm;
    if isempty(cfg.BaseHeight_mm)
        baseHeightMm = cfg.BaseHeight * scaleToMm;
    else
        baseHeightMm = cfg.BaseHeight_mm;
    end
    height_mm = height_map * scaleToMm + baseHeightMm;

    dx = cfg.HatchPitch_mm;
    dy = cfg.HatchPitch_mm;
    nxOut = max(1, ceil(spanX / dx));
    nyOut = max(1, ceil(spanY / dy));

    xCenters = ((1:nxOut) - 0.5) * dx;
    yCenters = ((1:nyOut) - 0.5) * dy;
    xCenters = min(max(xCenters, 0), spanX);
    yCenters = min(max(yCenters, 0), spanY);

    srcCols = min(nxSrc, max(1, floor(xCenters / max(spanX, eps) * nxSrc) + 1));
    srcRows = min(nySrc, max(1, floor(yCenters / max(spanY, eps) * nySrc) + 1));

    zMax = max(height_mm(:));
    if zMax <= cfg.Tolerance_mm
        segments_mm = zeros(0, 6);
        info = make_info(nxSrc, nySrc, nxOut, nyOut, 0, 0, scaleToMm, ...
            spanX, spanY, sourcePitch, cfg.BaseHeight, baseHeightMm);
        return;
    end

    nLayers = max(1, ceil(zMax / cfg.LayerHeight_mm));
    zPlanes = ((1:nLayers) - 0.5) * cfg.LayerHeight_mm;

    segments_all = cell(max(1, 2*nLayers - 1), 1);
    outCell = 0;
    seedXY = [0 0];
    totalLayerRows = 0;

    for layer = 1:nLayers
        z = zPlanes(layer);
        zOut = z;
        if cfg.StageZConvention
            zOut = -zOut;
        end

        if cfg.WoodpileMode
            useVertical = mod(layer, 2) == 0;
        else
            useVertical = false;
        end

        if useVertical
            segL = raster_vertical(height_mm, z, srcRows, srcCols, ...
                xCenters, spanY, dx, dy, cfg.CoordMode, cfg.Serpentine, cfg.Tolerance_mm, zOut);
        else
            segL = raster_horizontal(height_mm, z, srcRows, srcCols, ...
                yCenters, spanX, dx, dy, cfg.CoordMode, cfg.Serpentine, cfg.Tolerance_mm, zOut);
        end

        if isempty(segL)
            lastXY = seedXY;
        else
            lastXY = segL(end, 4:5);
        end

        totalLayerRows = totalLayerRows + size(segL, 1);
        outCell = outCell + 1;
        segments_all{outCell} = segL;

        if layer < nLayers
            zNext = zPlanes(layer + 1);
            if cfg.StageZConvention
                zNext = -zNext;
            end
            outCell = outCell + 1;
            segments_all{outCell} = [lastXY(1) lastXY(2) zOut, lastXY(1) lastXY(2) zNext];
            seedXY = lastXY;
        end
    end

    segments_mm = vertcat(segments_all{1:outCell});
    info = make_info(nxSrc, nySrc, nxOut, nyOut, nLayers, totalLayerRows, scaleToMm, ...
        spanX, spanY, sourcePitch, cfg.BaseHeight, baseHeightMm);
end

function cfg = parse_inputs(varargin)
    cfg.SourcePitch = 1;
    cfg.TargetMaxXY = [];
    cfg.BaseHeight = 0;
    cfg.BaseHeight_mm = [];
    cfg.HatchPitch_mm = 0.0004;
    cfg.LayerHeight_mm = 0.0005;
    cfg.StageZConvention = true;
    cfg.WoodpileMode = true;
    cfg.Serpentine = true;
    cfg.CoordMode = 'edges';
    cfg.Tolerance_mm = 1e-12;

    assert(mod(numel(varargin), 2) == 0, ...
        'heightmap_to_segments:nameValue', 'Arguments must be name-value pairs.');
    for k = 1:2:numel(varargin)
        name = varargin{k};
        val = varargin{k + 1};
        assert(ischar(name) || isstring(name), ...
            'heightmap_to_segments:nameValue', 'Parameter names must be strings.');
        name = char(name);
        switch lower(name)
            case 'sourcepitch'
                cfg.SourcePitch = val;
            case 'targetmaxxy'
                cfg.TargetMaxXY = val;
            case {'baseheight','baseheight_source','baseheight_sourceunits'}
                cfg.BaseHeight = val;
            case {'baseheight_mm','baseheightmm'}
                cfg.BaseHeight_mm = val;
            case 'hatchpitch_mm'
                cfg.HatchPitch_mm = val;
            case 'layerheight_mm'
                cfg.LayerHeight_mm = val;
            case 'stagezconvention'
                cfg.StageZConvention = logical(val);
            case 'woodpilemode'
                cfg.WoodpileMode = logical(val);
            case 'serpentine'
                cfg.Serpentine = logical(val);
            case 'coordmode'
                cfg.CoordMode = char(val);
            case 'tolerance_mm'
                cfg.Tolerance_mm = val;
            otherwise
                error('heightmap_to_segments:unknownParam', 'Unknown parameter: %s', name);
        end
    end

    if isempty(cfg.BaseHeight)
        cfg.BaseHeight = 0;
    end
    assert(cfg.HatchPitch_mm > 0, 'HatchPitch_mm must be > 0.');
    assert(cfg.LayerHeight_mm > 0, 'LayerHeight_mm must be > 0.');
    assert(isempty(cfg.TargetMaxXY) || all(cfg.TargetMaxXY(:) > 0), 'TargetMaxXY must be positive.');
    assert(isnumeric(cfg.BaseHeight) && isscalar(cfg.BaseHeight) && ...
        isfinite(cfg.BaseHeight) && cfg.BaseHeight >= 0, ...
        'BaseHeight must be a non-negative scalar in source units.');
    if ~isempty(cfg.BaseHeight_mm)
        assert(isnumeric(cfg.BaseHeight_mm) && isscalar(cfg.BaseHeight_mm) && ...
            isfinite(cfg.BaseHeight_mm) && cfg.BaseHeight_mm >= 0, ...
            'BaseHeight_mm must be a non-negative scalar in mm.');
        if cfg.BaseHeight > 0 && cfg.BaseHeight_mm > 0
            error('heightmap_to_segments:baseHeightConflict', ...
                'Use either BaseHeight or BaseHeight_mm, not both.');
        end
    end
    assert(any(strcmpi(cfg.CoordMode, {'edges','centers'})), 'CoordMode must be edges or centers.');
    cfg.Tolerance_mm = max(cfg.Tolerance_mm, 1e-15);
end

function scaleToMm = choose_scale(spanX0, spanY0, targetMaxXY)
    if isempty(targetMaxXY)
        scaleToMm = 1;
        return;
    end

    target = targetMaxXY(:).';
    assert(numel(target) == 1 || numel(target) == 2, ...
        'TargetMaxXY must be scalar or [maxX maxY].');

    if numel(target) == 1
        scaleToMm = target / max(spanX0, spanY0);
    else
        scaleToMm = min([target(1) / spanX0, target(2) / spanY0]);
    end
end

function segs = raster_horizontal(height_mm, z, srcRows, srcCols, yCenters, spanX, dx, dy, mode, serpentine, tol, zOut)
    nyOut = numel(srcRows);
    est = max(1024, nyOut);
    segs = zeros(est, 6);
    n = 0;

    for row = 1:nyOut
        active = height_mm(srcRows(row), srcCols) >= z - tol;
        runs = logical_runs(active);
        if isempty(runs), continue; end

        if serpentine && mod(row, 2) == 0
            runOrder = size(runs, 1):-1:1;
        else
            runOrder = 1:size(runs, 1);
        end

        for rr = runOrder
            c1 = runs(rr, 1);
            c2 = runs(rr, 2);
            [x1, x2] = run_edges(c1, c2, dx, spanX, mode);
            y = yCenters(row);
            if serpentine && mod(row, 2) == 0
                tmp = x1; x1 = x2; x2 = tmp;
            end
            [segs, n] = append_segment(segs, n, [x1 y zOut x2 y zOut]);
        end
    end

    segs = segs(1:n, :);
end

function segs = raster_vertical(height_mm, z, srcRows, srcCols, xCenters, spanY, dx, dy, mode, serpentine, tol, zOut)
    nxOut = numel(srcCols);
    est = max(1024, nxOut);
    segs = zeros(est, 6);
    n = 0;

    for col = 1:nxOut
        active = height_mm(srcRows, srcCols(col)) >= z - tol;
        runs = logical_runs(active(:).');
        if isempty(runs), continue; end

        if serpentine && mod(col, 2) == 0
            runOrder = size(runs, 1):-1:1;
        else
            runOrder = 1:size(runs, 1);
        end

        for rr = runOrder
            r1 = runs(rr, 1);
            r2 = runs(rr, 2);
            [y1, y2] = run_edges(r1, r2, dy, spanY, mode);
            x = xCenters(col);
            if serpentine && mod(col, 2) == 0
                tmp = y1; y1 = y2; y2 = tmp;
            end
            [segs, n] = append_segment(segs, n, [x y1 zOut x y2 zOut]);
        end
    end

    segs = segs(1:n, :);
end

function runs = logical_runs(active)
    if ~any(active)
        runs = zeros(0, 2);
        return;
    end
    active = active(:).';
    d = diff([false active false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    runs = [starts(:) ends(:)];
end

function [v1, v2] = run_edges(i1, i2, pitch, span, mode)
    if strcmpi(mode, 'centers')
        v1 = (i1 - 0.5) * pitch;
        v2 = (i2 - 0.5) * pitch;
    else
        v1 = (i1 - 1.0) * pitch;
        v2 = min(i2 * pitch, span);
    end
end

function [segs, n] = append_segment(segs, n, row)
    n = n + 1;
    if n > size(segs, 1)
        segs = [segs; zeros(size(segs, 1), 6)]; %#ok<AGROW>
    end
    segs(n, :) = row;
end

function info = make_info(nxSrc, nySrc, nxOut, nyOut, nLayers, totalLayerRows, scaleToMm, spanX, spanY, sourcePitch, baseHeightSource, baseHeightMm)
    info = struct();
    info.SourceSize = [nySrc nxSrc];
    info.OutputGridSize = [nyOut nxOut];
    info.LayerCount = nLayers;
    info.LayerRows = totalLayerRows;
    info.ScaleToMm = scaleToMm;
    info.SpanXY_mm = [spanX spanY];
    info.SourcePitch = sourcePitch;
    info.SourcePitch_mm = sourcePitch * scaleToMm;
    info.BaseHeightSource = baseHeightSource;
    info.BaseHeight_mm = baseHeightMm;
end
