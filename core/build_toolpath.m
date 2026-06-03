function segments_mm = build_toolpath(F, V, cfg)
% BUILD_TOOLPATH  Full pipeline: mesh -> slice -> hatch -> order -> segments.
%
%   segments_mm = build_toolpath(F, V, cfg)
%
% INPUTS:
%   F    - Nx3 face connectivity (triangle indices into V)
%   V    - Mx3 vertex coordinates [x y z] (mm)
%   cfg  - Configuration struct from tppdlw_config()
%
% OUTPUT:
%   segments_mm - Px6 matrix [x1 y1 z1 x2 y2 z2] of all scan segments
%                 and Z-transition segments, ready for write_segments().
%
% PIPELINE (per layer):
%   1. Get 2D contour from slice_mesh
%   2. Compute scan angle for this layer
%   3. (Optional) Trace contour boundary
%   4. Generate hatching at that angle via hatch_layer
%   5. Apply serpentine ordering
%   6. Apply greedy path optimization
%   7. Append Z-transition segment to next layer
%   8. Apply XY/Z offsets
%
% See also: tppdlw_process, slice_mesh, hatch_layer, trace_contour,
%           order_serpentine, order_greedy, write_segments

    if ~isfield(cfg, 'StageZConvention') || isempty(cfg.StageZConvention)
        cfg.StageZConvention = true;
    else
        cfg.StageZConvention = logical(cfg.StageZConvention);
    end

    % ---- Scaling ----
    if cfg.AutoScale && cfg.TargetSize_mm > 0
        spanX = max(V(:,1)) - min(V(:,1));
        spanY = max(V(:,2)) - min(V(:,2));
        baseSpan = max(spanX, spanY);
        if baseSpan > 0
            S = cfg.TargetSize_mm / baseSpan;
            V = V * S;
        end
    end

    % ---- Bounding box (mm) ----
    xmin = min(V(:,1)) - cfg.Margin_mm;
    xmax = max(V(:,1)) + cfg.Margin_mm;
    ymin = min(V(:,2)) - cfg.Margin_mm;
    ymax = max(V(:,2)) + cfg.Margin_mm;
    zmin = min(V(:,3));
    zmax = max(V(:,3));
    bbox = [xmin ymin xmax ymax];

    % ---- Z planes ----
    nLayers = max(1, ceil((zmax - zmin) / cfg.LayerHeight_mm));
    if isempty(cfg.FirstLayerZ_mm)
        zPlanes = zmin + ((1:nLayers) - 0.5) * cfg.LayerHeight_mm;
    else
        zPlanes = cfg.FirstLayerZ_mm + (0:nLayers-1) * cfg.LayerHeight_mm;
    end
    zPlanes = zPlanes(zPlanes >= zmin - cfg.Tolerance_mm & ...
                      zPlanes <= zmax + cfg.Tolerance_mm);
    nLayers = numel(zPlanes);

    fprintf('  Slicing: %d layers, Z = [%.6g .. %.6g] mm\n', ...
        nLayers, zPlanes(1), zPlanes(end));
    fprintf('  Layer height: %.6g mm (%.2f um)\n', ...
        cfg.LayerHeight_mm, cfg.LayerHeight_mm * 1000);
    fprintf('  Hatch spacing: %.6g mm (%.2f um)\n', ...
        cfg.HatchSpacing_mm, cfg.HatchSpacing_mm * 1000);
    fprintf('  Angle mode: %s (start=%.1f deg, incr=%.1f deg)\n', ...
        cfg.AngleMode, cfg.ScanAngle_deg, cfg.AngleIncrement_deg);
    fprintf('  Contour tracing: %s | Overrun: %.4g mm\n', ...
        bool2str(cfg.TraceContour && cfg.ContourFirst), cfg.Overrun_mm);
    fprintf('  Stage Z convention: %s\n', bool2str(cfg.StageZConvention));

    % ---- Slice mesh ----
    layers = slice_mesh(F, V, zPlanes, cfg.Tolerance_mm);

    % ---- Process each layer ----
    segments_all = cell(nLayers * 2, 1);
    cellIdx = 0;
    seedXY = [0, 0];
    emptyLayers = 0;
    skippedGreedyLayers = 0;
    t0 = tic;

    if isfield(cfg, 'OptimizeMaxSegments') && ~isempty(cfg.OptimizeMaxSegments)
        optimizeMaxSegments = cfg.OptimizeMaxSegments;
    else
        optimizeMaxSegments = inf;
    end

    for L = 1:nLayers
        z = zPlanes(L);
        contour2d = layers{L};

        if isempty(contour2d)
            emptyLayers = emptyLayers + 1;
            continue;
        end

        % Compute scan angle for this layer
        angle = scan_angle_for_layer(cfg, L);

        % ---- Contour tracing (boundary outline) ----
        contourSegs4 = zeros(0, 4);
        if cfg.TraceContour && cfg.ContourFirst
            contourSegs4 = trace_contour(contour2d, cfg.Tolerance_mm);
        end
        hasContour = cfg.ContourFirst && ~isempty(contourSegs4);

        % ---- Hatching (fill) ----
        hatchSegs = hatch_layer(contour2d, angle, cfg.HatchSpacing_mm, ...
                                bbox, cfg.CoordMode, cfg.Tolerance_mm, ...
                                'Overrun', cfg.Overrun_mm);

        % Serpentine reorders the hatch fill only; the traced contour stays first.
        if cfg.Serpentine && ~isempty(hatchSegs)
            hatchSegs = order_serpentine(hatchSegs, angle, cfg.Tolerance_mm);
        end

        % ---- Combine: contour first, then hatch ----
        if hasContour
            scanSegs = [contourSegs4; hatchSegs];
        else
            scanSegs = hatchSegs;
        end

        if isempty(scanSegs)
            emptyLayers = emptyLayers + 1;
            continue;
        end

        % Greedy nearest-neighbor path optimization
        if cfg.OptimizePath && size(scanSegs, 1) <= optimizeMaxSegments
            [scanSegs, lastXY] = order_greedy(scanSegs, seedXY);
        elseif cfg.OptimizePath
            skippedGreedyLayers = skippedGreedyLayers + 1;
            lastXY = scanSegs(end, 3:4);
        else
            lastXY = scanSegs(end, 3:4);
        end

        % Build 6-column segments [x1 y1 z1 x2 y2 z2]
        nSeg = size(scanSegs, 1);
        zCol = repmat(z, nSeg, 1);
        layerSegs6 = [scanSegs(:,1:2), zCol, scanSegs(:,3:4), zCol];

        cellIdx = cellIdx + 1;
        segments_all{cellIdx} = layerSegs6;

        % Z-transition segment to next layer
        if L < nLayers
            z_next = zPlanes(L + 1);
            transition = [lastXY(1) lastXY(2) z, lastXY(1) lastXY(2) z_next];
            cellIdx = cellIdx + 1;
            segments_all{cellIdx} = transition;
            seedXY = lastXY;
        end

        % Progress bar
        if mod(L, max(1, floor(nLayers/20))) == 0 || L == nLayers
            pct = 100 * L / nLayers;
            elapsed = toc(t0);
            eta = elapsed / L * (nLayers - L);
            fprintf('  [%3.0f%%] Layer %d/%d (%.1f deg, %d segs) ETA %.1fs\n', ...
                pct, L, nLayers, angle, nSeg, eta);
        end
    end

    % ---- Concatenate ----
    if cellIdx == 0
        segments_mm = zeros(0, 6);
        warning('build_toolpath:noSegments', 'No segments generated. Check input geometry.');
        return;
    end
    segments_mm = vertcat(segments_all{1:cellIdx});

    % ---- Apply origin centering ----
    if cfg.CenterOrigin
        scanMask = abs(segments_mm(:,3) - segments_mm(:,6)) < cfg.Tolerance_mm;
        if any(scanMask)
            allX = [segments_mm(scanMask,1); segments_mm(scanMask,4)];
            allY = [segments_mm(scanMask,2); segments_mm(scanMask,5)];
            cx = (min(allX) + max(allX)) / 2;
            cy = (min(allY) + max(allY)) / 2;
            segments_mm(:, [1 4]) = segments_mm(:, [1 4]) - cx;
            segments_mm(:, [2 5]) = segments_mm(:, [2 5]) - cy;
        end
    end

    % ---- Invert Z to stage convention ----
    % Geometry is sliced positive-up. Some stage controllers expect higher
    % build layers as negative Z motion; keep that as the default.
    if cfg.StageZConvention
        segments_mm(:, [3 6]) = -segments_mm(:, [3 6]);
    end

    % ---- Apply XYZ offsets ----
    if cfg.OffsetX_mm ~= 0
        segments_mm(:, [1 4]) = segments_mm(:, [1 4]) + cfg.OffsetX_mm;
    end
    if cfg.OffsetY_mm ~= 0
        segments_mm(:, [2 5]) = segments_mm(:, [2 5]) + cfg.OffsetY_mm;
    end
    if cfg.OffsetZ_mm ~= 0
        segments_mm(:, [3 6]) = segments_mm(:, [3 6]) + cfg.OffsetZ_mm;
    end

    % ---- Summary ----
    fprintf('  Total segments: %d  (empty layers skipped: %d)\n', ...
        size(segments_mm, 1), emptyLayers);
    if skippedGreedyLayers > 0
        fprintf('  Greedy path ordering skipped on %d layer(s) above OptimizeMaxSegments=%g.\n', ...
            skippedGreedyLayers, optimizeMaxSegments);
    end
end

% ===================== Helpers =====================
function angle = scan_angle_for_layer(cfg, layer_index)
    switch cfg.AngleMode
        case 'fixed'
            angle = cfg.ScanAngle_deg;
        case 'alternating'
            angle = cfg.ScanAngle_deg + ...
                    mod(layer_index - 1, 2) * cfg.AngleIncrement_deg;
        case 'incremental'
            angle = cfg.ScanAngle_deg + ...
                    (layer_index - 1) * cfg.AngleIncrement_deg;
        otherwise
            angle = cfg.ScanAngle_deg;
    end
end

function s = bool2str(b)
    if b, s = 'ON'; else, s = 'OFF'; end
end
