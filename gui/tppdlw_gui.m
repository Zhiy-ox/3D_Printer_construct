function tppdlw_gui()
% TPPDLW_GUI  Graphical interface for TPP-DLW toolpath generation.
%
%   tppdlw_gui()
%
% Panels:
%   LEFT  — Parameter cards (File, Slicing, Writing Direction, Path, Offset)
%   RIGHT — Preview axes + layer navigation + action toolbar + status bar
%
% Layer navigation: ◀ PREV | [layer#] / [total] | NEXT ▶  (integer, no slider)
% View toggle:      [2D Layer]  [3D Stack]  — mutually exclusive buttons
%
% Requires MATLAB R2020b+ (uifigure, uiaxes, uibutton, uilabel, etc.)
%
% See also: tppdlw_process, tppdlw_config

    % ---- Paths ----
    rootDir = fileparts(fileparts(mfilename('fullpath')));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'core'));
    addpath(fullfile(rootDir, 'viz'));

    % ---- Colours ----
    CLR_BG      = [0.96 0.97 0.98];
    CLR_CARD    = [1.00 1.00 1.00];
    CLR_HDR     = [0.20 0.44 0.72];
    CLR_BTN1    = [0.20 0.55 0.95];   % Preview (blue)
    CLR_BTN2    = [0.18 0.72 0.42];   % Generate (green)
    CLR_BTNGRAY = [0.55 0.55 0.60];   % secondary buttons

    % ---- State ----
    S.segments     = [];
    S.inputFile    = '';
    S.currentLayer = 1;
    S.nLayers      = 0;
    S.viewMode     = '2d';
    S.scanMask     = [];
    S.uniqueZ      = [];

    % =========================================================================
    %  MAIN FIGURE
    % =========================================================================
    fig = uifigure('Name', 'TPP-DLW Toolpath Generator', ...
                   'Position', [80 60 1160 760], ...
                   'Color', CLR_BG, ...
                   'Resize', 'on');

    % =========================================================================
    %  LEFT PANEL — Parameters (scrollable)
    % =========================================================================
    leftW = 310;
    leftPanel = uipanel(fig, ...
        'Position', [10 10 leftW 740], ...
        'BackgroundColor', CLR_BG, ...
        'BorderType', 'none');

    y = 700;   % top y, counting down

    % ---- Card: File ----
    y = card(leftPanel, y, '  FILE INPUT', CLR_HDR, 78);
    S.ui.fileEdit = uitextarea(leftPanel, ...
        'Value', {'(no file selected)'}, ...
        'Editable', 'off', ...
        'Position', [10 y-26 leftW-20 28], ...
        'FontColor', [0.45 0.45 0.45], ...
        'BackgroundColor', [0.94 0.95 0.96]);
    y = y - 34;
    uibutton(leftPanel, 'Text', '📂  Browse STEP / STL...', ...
        'Position', [10 y-26 leftW-20 28], ...
        'BackgroundColor', CLR_BTN1, 'FontColor', 'w', 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) cb_browse());
    y = y - 42;

    % ---- Card: Slicing ----
    y = card(leftPanel, y, '  SLICING', CLR_HDR, 112);
    [S.ui.targetSize, y] = nf(leftPanel, 'Target XY size (mm)', 0.1,  [1e-4 1000], y);
    [S.ui.autoScale,  y] = cb(leftPanel, 'Auto-scale model to target size', true, y);
    [S.ui.layerHt,    y] = nf(leftPanel, 'Layer height   (mm)', 5e-4, [1e-7 10],   y);
    [S.ui.hatchSp,    y] = nf(leftPanel, 'Hatch spacing  (mm)', 3e-4, [1e-7 10],   y);
    y = y - 6;

    % ---- Card: Writing Direction ----
    y = card(leftPanel, y, '  WRITING DIRECTION', CLR_HDR, 120);
    uilabel(leftPanel, 'Text', 'Angle mode', ...
        'Position', [12 y-20 120 18], 'FontSize', 11);
    S.ui.angleMode = uidropdown(leftPanel, ...
        'Items', {'alternating (0/90)', 'fixed', 'incremental'}, ...
        'Value', 'alternating (0/90)', ...
        'Position', [140 y-22 leftW-150 22], ...
        'FontSize', 11);
    y = y - 32;
    [S.ui.scanAngle, y] = nf(leftPanel, 'Start angle    (deg)', 0,  [-360 360], y);
    [S.ui.angleIncr, y] = nf(leftPanel, 'Angle increment(deg)', 90, [0 360],   y);
    y = y - 6;

    % ---- Card: Path Options ----
    y = card(leftPanel, y, '  PATH OPTIONS', CLR_HDR, 128);
    [S.ui.serpentine,    y] = cb(leftPanel, 'Serpentine scan (boustrophedon)', true,  y);
    [S.ui.optimizePath,  y] = cb(leftPanel, 'Optimize path (greedy NN)',       true,  y);
    [S.ui.traceContour,  y] = cb(leftPanel, 'Trace contour before hatching',   false, y);
    [S.ui.overrun,       y] = nf(leftPanel, 'Overrun (mm)', 0, [0 1], y);
    y = y - 6;

    % ---- Card: Offset ----
    y = card(leftPanel, y, '  ORIGIN / OFFSET', CLR_HDR, 118);
    [S.ui.centerOrigin,  y] = cb(leftPanel, 'Centre output at (0, 0)', false, y);
    [S.ui.offsetX,       y] = nf(leftPanel, 'Offset X (mm)', 0, [-1e4 1e4], y);
    [S.ui.offsetY,       y] = nf(leftPanel, 'Offset Y (mm)', 0, [-1e4 1e4], y);
    [S.ui.offsetZ,       y] = nf(leftPanel, 'Offset Z (mm)', 0, [-1e4 1e4], y);

    % =========================================================================
    %  RIGHT PANEL — Preview
    % =========================================================================
    rx = leftW + 18;
    rw = fig.Position(3) - rx - 10;

    % ---- Top toolbar: view toggle + layer nav ----
    tbH = 42;
    tbY = 700;

    % View-mode toggle buttons (mutually exclusive)
    S.ui.btn2D = uibutton(fig, 'state', ...
        'Text', '  2D  Layer  ', ...
        'Position', [rx tbY 110 tbH], ...
        'Value', true, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'BackgroundColor', CLR_BTN1, 'FontColor', 'w', ...
        'ValueChangedFcn', @(src,~) setViewMode(src, '2d'));

    S.ui.btn3D = uibutton(fig, 'state', ...
        'Text', '  3D  Stack  ', ...
        'Position', [rx+112 tbY 110 tbH], ...
        'Value', false, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'BackgroundColor', [0.88 0.89 0.90], 'FontColor', [0.3 0.3 0.3], ...
        'ValueChangedFcn', @(src,~) setViewMode(src, '3d'));

    % Layer navigation  ◀  [field] / [total]  ▶
    navX0 = rx + 240;
    uilabel(fig, 'Text', 'Layer:', ...
        'Position', [navX0 tbY+10 48 22], 'FontSize', 12);
    S.ui.btnPrev = uibutton(fig, 'Text', '◀', ...
        'Position', [navX0+50 tbY+6 32 32], ...
        'FontSize', 14, ...
        'ButtonPushedFcn', @(~,~) stepLayer(-1));
    S.ui.layerField = uieditfield(fig, 'numeric', ...
        'Value', 1, 'Limits', [1 1], ...
        'Position', [navX0+86 tbY+6 52 32], ...
        'HorizontalAlignment', 'center', 'FontSize', 13, ...
        'ValueChangedFcn', @(~,~) goToLayer());
    S.ui.layerTotalLabel = uilabel(fig, 'Text', '/ —', ...
        'Position', [navX0+142 tbY+8 48 24], 'FontSize', 12);
    S.ui.btnNext = uibutton(fig, 'Text', '▶', ...
        'Position', [navX0+192 tbY+6 32 32], ...
        'FontSize', 14, ...
        'ButtonPushedFcn', @(~,~) stepLayer(+1));

    % Info label (segments / layers / scan length)
    S.ui.infoLabel = uilabel(fig, ...
        'Text', 'No data.  Run Preview or Generate.', ...
        'Position', [navX0+235 tbY+10 max(20, rw-475) 22], ...
        'FontSize', 11, 'FontColor', [0.4 0.4 0.45]);

    % ---- Preview axes ----
    axH = tbY - 80;   % height: from top toolbar down to action row
    S.ui.ax = uiaxes(fig, ...
        'Position', [rx 72 rw axH], ...
        'BackgroundColor', 'w', ...
        'Box', 'on');
    grid(S.ui.ax, 'on');
    axis(S.ui.ax, 'equal');
    title(S.ui.ax, 'Load a file and click  ▶ Preview  or  💾 Generate');
    xlabel(S.ui.ax, 'X (mm)');  ylabel(S.ui.ax, 'Y (mm)');

    % ---- Action toolbar (bottom) ----
    btnY = 24;  bh = 38;
    uibutton(fig, 'Text', '▶  Preview', ...
        'Position', [rx btnY 120 bh], ...
        'FontWeight', 'bold', 'FontSize', 13, ...
        'BackgroundColor', CLR_BTN1, 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) cb_preview());

    uibutton(fig, 'Text', '💾  Generate .txt', ...
        'Position', [rx+128 btnY 148 bh], ...
        'FontWeight', 'bold', 'FontSize', 13, ...
        'BackgroundColor', CLR_BTN2, 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) cb_generate());

    uibutton(fig, 'Text', '▷  Animate', ...
        'Position', [rx+284 btnY 108 bh], ...
        'FontSize', 12, 'BackgroundColor', CLR_BTNGRAY, 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) cb_animate());

    uibutton(fig, 'Text', '≡  Compare', ...
        'Position', [rx+400 btnY 108 bh], ...
        'FontSize', 12, 'BackgroundColor', CLR_BTNGRAY, 'FontColor', 'w', ...
        'ButtonPushedFcn', @(~,~) cb_compare());

    uibutton(fig, 'Text', '📥  Load Config', ...
        'Position', [rx+516 btnY 120 bh], ...
        'FontSize', 12, 'BackgroundColor', [0.94 0.95 0.96], ...
        'ButtonPushedFcn', @(~,~) cb_loadConfig());

    uibutton(fig, 'Text', '📤  Save Config', ...
        'Position', [rx+644 btnY 120 bh], ...
        'FontSize', 12, 'BackgroundColor', [0.94 0.95 0.96], ...
        'ButtonPushedFcn', @(~,~) cb_saveConfig());

    % Status bar
    S.ui.statusBar = uilabel(fig, ...
        'Text', 'Ready.', ...
        'Position', [rx 4 rw 18], ...
        'FontSize', 10, 'FontColor', [0.35 0.35 0.40]);

    % =========================================================================
    %  CALLBACKS
    % =========================================================================

    function cb_browse()
        [fn, fp] = uigetfile( ...
            {'*.step;*.stp;*.stl','CAD Files (*.step, *.stp, *.stl)';'*.*','All Files'}, ...
            'Select 3D Model');
        if isequal(fn, 0), return; end
        S.inputFile = fullfile(fp, fn);
        S.ui.fileEdit.Value = {S.inputFile};
        S.ui.fileEdit.FontColor = [0.1 0.1 0.1];
        S.segments = [];  S.nLayers = 0;
        updateLayerNav();
        setStatus(sprintf('Loaded: %s', fn));
    end

    % ---- Build config from UI values ----
    function cfg = buildCfg()
        modeStr = lower(strtok(S.ui.angleMode.Value));
        cfg = tppdlw_config( ...
            'InputFile',          S.inputFile, ...
            'TargetSize_mm',      S.ui.targetSize.Value, ...
            'AutoScale',          S.ui.autoScale.Value, ...
            'LayerHeight_mm',     S.ui.layerHt.Value, ...
            'HatchSpacing_mm',    S.ui.hatchSp.Value, ...
            'ScanAngle_deg',      S.ui.scanAngle.Value, ...
            'AngleIncrement_deg', S.ui.angleIncr.Value, ...
            'AngleMode',          modeStr, ...
            'Serpentine',         S.ui.serpentine.Value, ...
            'OptimizePath',       S.ui.optimizePath.Value, ...
            'TraceContour',       S.ui.traceContour.Value, ...
            'ContourFirst',       S.ui.traceContour.Value, ...
            'Overrun_mm',         S.ui.overrun.Value, ...
            'CenterOrigin',       S.ui.centerOrigin.Value, ...
            'OffsetX_mm',         S.ui.offsetX.Value, ...
            'OffsetY_mm',         S.ui.offsetY.Value, ...
            'OffsetZ_mm',         S.ui.offsetZ.Value);
    end

    % ---- Preview (no file write) ----
    function cb_preview()
        if isempty(S.inputFile)
            uialert(fig,'Select a file first.','No File'); return;
        end
        setStatus('Computing toolpath...');  drawnow;
        try
            cfg = buildCfg();
            [F,V] = import_model(cfg.InputFile);
            S.segments = build_toolpath(F, V, cfg);
            afterCompute();
            setStatus(sprintf('Preview ready — %d segments, %d layers.', ...
                size(S.segments,1), S.nLayers));
        catch ME
            uialert(fig, ME.message, 'Error');
            setStatus(['Error: ' ME.message]);
        end
    end

    % ---- Generate + save ----
    function cb_generate()
        if isempty(S.inputFile)
            uialert(fig,'Select a file first.','No File'); return;
        end
        [fn,fp] = uiputfile({'*.txt','Segment File (*.txt)'},'Save As','output/segments.txt');
        if isequal(fn,0), return; end
        outPath = fullfile(fp, fn);
        setStatus('Generating...');  drawnow;
        try
            cfg = buildCfg();
            cfg.OutputFile = outPath;
            S.segments = tppdlw_process(cfg);
            afterCompute();
            setStatus(sprintf('Saved: %s  (%d segments, %d layers)', ...
                fn, size(S.segments,1), S.nLayers));
        catch ME
            uialert(fig, ME.message, 'Error');
            setStatus(['Error: ' ME.message]);
        end
    end

    function cb_animate()
        if isempty(S.segments)
            uialert(fig,'Run Preview or Generate first.','No Data'); return;
        end
        preview_toolpath(S.segments, 'Animate', true, 'AnimDelay', 0.08);
    end

    function cb_compare()
        if isempty(S.segments)
            uialert(fig,'Run Preview or Generate first.','No Data'); return;
        end
        n = S.nLayers;
        compare_layers(S.segments, round(linspace(1, n, min(n, 8))));
    end

    function cb_loadConfig()
        [fn,fp] = uigetfile({'*.json','Config File (*.json)'},'Load Config');
        if isequal(fn,0), return; end
        try
            jd = jsondecode(fileread(fullfile(fp,fn)));
            applyJsonToUI(jd);
            setStatus(['Config loaded: ' fn]);
        catch ME
            uialert(fig, ME.message, 'Error loading config');
        end
    end

    function cb_saveConfig()
        [fn,fp] = uiputfile({'*.json','Config File (*.json)'},'Save Config','my_config.json');
        if isequal(fn,0), return; end
        try
            cfg = buildCfg();
            cfg = rmfield(cfg, {'InputFile', 'OutputFile'});
            fid = fopen(fullfile(fp,fn),'w');
            fprintf(fid, '%s', jsonencode(cfg, 'PrettyPrint', true));
            fclose(fid);
            setStatus(['Config saved: ' fn]);
        catch ME
            uialert(fig, ME.message, 'Error saving config');
        end
    end

    % ---- View toggle callback ----
    function setViewMode(src, mode)
        if ~src.Value, src.Value = true; return; end
        is3d = strcmp(mode, '3d');
        S.viewMode = mode;
        [btnOn, btnOff] = deal(S.ui.btn2D, S.ui.btn3D);
        if is3d, [btnOn, btnOff] = deal(S.ui.btn3D, S.ui.btn2D); end
        btnOn.BackgroundColor  = CLR_BTN1;  btnOn.FontColor  = 'w';
        btnOff.Value = false;
        btnOff.BackgroundColor = [0.88 0.89 0.90]; btnOff.FontColor = [0.3 0.3 0.3];
        navEnable = 'on'; if is3d, navEnable = 'off'; end
        S.ui.layerField.Enable = navEnable;
        S.ui.btnPrev.Enable    = navEnable;
        S.ui.btnNext.Enable    = navEnable;
        refreshPreview();
    end

    % ---- Layer navigation ----
    function stepLayer(delta)
        if S.nLayers == 0, return; end
        newL = S.currentLayer + delta;
        newL = max(1, min(S.nLayers, newL));
        if newL == S.currentLayer, return; end
        S.currentLayer = newL;
        S.ui.layerField.Value = newL;
        refreshPreview();
    end

    function goToLayer()
        if S.nLayers == 0, return; end
        newL = round(S.ui.layerField.Value);
        newL = max(1, min(S.nLayers, newL));
        S.ui.layerField.Value = newL;
        S.currentLayer = newL;
        refreshPreview();
    end

    % ---- Called after compute completes ----
    function afterCompute()
        if isempty(S.segments)
            S.nLayers  = 0;
            S.scanMask = [];
            S.uniqueZ  = [];
        else
            S.scanMask = abs(S.segments(:,3) - S.segments(:,6)) < 1e-12;
            % Z is negated for stage convention, so the bottom (first-written)
            % layer is the largest value. Sort descending => Layer 1 = bottom.
            S.uniqueZ  = sort(unique(S.segments(S.scanMask, 3)), 'descend');
            S.nLayers  = numel(S.uniqueZ);
        end
        S.currentLayer = 1;
        updateLayerNav();
        updateInfoLabel();
        refreshPreview();
    end

    function updateLayerNav()
        nL = max(1, S.nLayers);
        S.ui.layerField.Limits = [1 nL];
        S.ui.layerField.Value  = min(S.currentLayer, nL);
        if S.nLayers > 0
            S.ui.layerTotalLabel.Text = sprintf('/ %d', S.nLayers);
        else
            S.ui.layerTotalLabel.Text = '/ —';
        end
    end

    function updateInfoLabel()
        if isempty(S.segments)
            S.ui.infoLabel.Text = 'No data.  Run Preview or Generate.';
            return;
        end
        nScan  = sum(S.scanMask);
        nTrans = sum(~S.scanMask);
        ss     = S.segments(S.scanMask, :);
        totalLen = sum(sqrt((ss(:,4)-ss(:,1)).^2 + (ss(:,5)-ss(:,2)).^2));
        S.ui.infoLabel.Text = sprintf( ...
            'Layers: %d   |   Scan segs: %d   |   Z-hops: %d   |   Path length: %.4f mm', ...
            S.nLayers, nScan, nTrans, totalLen);
    end

    % ---- Redraw preview axes ----
    function refreshPreview()
        ax = S.ui.ax;
        if isempty(S.segments)
            cla(ax);
            title(ax,'Load a file and click  ▶ Preview  or  💾 Generate');
            xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)');
            return;
        end

        cla(ax); hold(ax,'on'); grid(ax,'on'); box(ax,'on');

        if strcmpi(S.viewMode, '3d')
            % 3D view: all sampled layers, single vectorized plot3
            view(ax, 35, 25);
            axis(ax, 'auto');
            xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)'); zlabel(ax,'Z (mm)');

            nL   = numel(S.uniqueZ);
            step = max(1, floor(nL/200));
            sampledZ = S.uniqueZ(1:step:nL);
            ss = S.segments(S.scanMask & ismember(S.segments(:,3), sampledZ), :);

            if ~isempty(ss)
                n  = size(ss, 1);
                Xm = [ss(:,1)'; ss(:,4)'; nan(1,n)];
                Ym = [ss(:,2)'; ss(:,5)'; nan(1,n)];
                Zm = [ss(:,3)'; ss(:,6)'; nan(1,n)];
                plot3(ax, Xm(:), Ym(:), Zm(:), '-', ...
                      'Color', CLR_HDR, 'LineWidth', 0.4);
            end

            ts = S.segments(~S.scanMask, :);
            if ~isempty(ts)
                n  = size(ts, 1);
                Xt = [ts(:,1)'; ts(:,4)'; nan(1,n)];
                Yt = [ts(:,2)'; ts(:,5)'; nan(1,n)];
                Zt = [ts(:,3)'; ts(:,6)'; nan(1,n)];
                plot3(ax, Xt(:), Yt(:), Zt(:), '-', ...
                      'Color', [0.7 0.7 0.7], 'LineWidth', 0.3);
            end

            title(ax, sprintf('3D Stack — %d layers (every %d shown)', nL, step));

        else
            % 2D view: single layer
            view(ax, 0, 90);
            axis(ax, 'equal');
            xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)');

            nZ = numel(S.uniqueZ);
            li = max(1, min(S.currentLayer, nZ));
            z  = S.uniqueZ(li);
            ss = S.segments(abs(S.segments(:,3) - z) < 1e-10 & S.scanMask, :);

            if ~isempty(ss)
                n  = size(ss, 1);
                Xm = [ss(:,1)'; ss(:,4)'; nan(1,n)];
                Ym = [ss(:,2)'; ss(:,5)'; nan(1,n)];
                plot(ax, Xm(:), Ym(:), '-', 'Color', [0.85 0.15 0.15], 'LineWidth', 0.6);
                plot(ax, ss(1,1), ss(1,2), 'o', ...
                     'Color', [0.1 0.7 0.2], 'MarkerSize', 6, 'MarkerFaceColor', [0.1 0.7 0.2]);
                plot(ax, ss(end,4), ss(end,5), 's', ...
                     'Color', [0.9 0.5 0.1], 'MarkerSize', 6, 'MarkerFaceColor', [0.9 0.5 0.1]);
            end

            title(ax, sprintf('Layer %d / %d   —   Z = %.6f mm   —   %d segments', ...
                  li, nZ, z, size(ss,1)));
        end
    end

    % ---- Apply JSON config to UI fields ----
    function applyJsonToUI(jd)
        fn = fieldnames(jd);
        for k = 1:numel(fn)
            f = fn{k};  v = jd.(f);
            try
                switch lower(f)
                    case 'targetsize_mm',      S.ui.targetSize.Value = v;
                    case 'autoscale',           S.ui.autoScale.Value = logical(v);
                    case 'layerheight_mm',      S.ui.layerHt.Value = v;
                    case 'hatchspacing_mm',     S.ui.hatchSp.Value = v;
                    case 'scanangle_deg',       S.ui.scanAngle.Value = v;
                    case 'angleincrement_deg',  S.ui.angleIncr.Value = v;
                    case 'anglemode'
                        opts = S.ui.angleMode.Items;
                        hit = opts(contains(lower(opts), lower(v)));
                        if ~isempty(hit), S.ui.angleMode.Value = hit{1}; end
                    case 'serpentine',          S.ui.serpentine.Value = logical(v);
                    case 'optimizepath',        S.ui.optimizePath.Value = logical(v);
                    case 'tracecontour',        S.ui.traceContour.Value = logical(v);
                    case 'overrun_mm',          S.ui.overrun.Value = v;
                    case 'centerorigin',        S.ui.centerOrigin.Value = logical(v);
                    case 'offsetx_mm',          S.ui.offsetX.Value = v;
                    case 'offsety_mm',          S.ui.offsetY.Value = v;
                    case 'offsetz_mm',          S.ui.offsetZ.Value = v;
                end
            catch
            end
        end
    end

    function setStatus(msg)
        S.ui.statusBar.Text = msg;
        drawnow;
    end
end

% ==========================================================================
%  UI helpers (external functions — available to nested scope via varargin)
% ==========================================================================

function yOut = card(parent, y, title, hdrClr, cardH)
    leftW = 300;
    uipanel(parent, ...
        'Position', [8  y-cardH  leftW  cardH], ...
        'BackgroundColor', [1 1 1], ...
        'BorderType', 'line', ...
        'HighlightColor', [0.80 0.83 0.88]);
    uipanel(parent, ...
        'Position', [8  y-20  leftW  22], ...
        'BackgroundColor', hdrClr, ...
        'BorderType', 'none');
    uilabel(parent, 'Text', title, ...
        'Position', [12  y-18  leftW-8  18], ...
        'FontColor', 'w', 'FontWeight', 'bold', 'FontSize', 11);
    yOut = y - 26;
end

function [ctrl, yOut] = nf(parent, lbl, defVal, limits, y)
% Numeric field row: label on left, editfield on right.
    dy = 28;  lblW = 160;  fldW = 120;  fldX = 168;
    uilabel(parent, 'Text', lbl, ...
        'Position', [14 y-20 lblW 18], 'FontSize', 11);
    ctrl = uieditfield(parent, 'numeric', ...
        'Value', defVal, 'Limits', limits, ...
        'LowerLimitInclusive', 'on', ...
        'Position', [fldX y-22 fldW 22], ...
        'HorizontalAlignment', 'right', ...
        'FontSize', 11, ...
        'ValueDisplayFormat', '%.8g');
    yOut = y - dy;
end

function [ctrl, yOut] = cb(parent, lbl, defVal, y)
% Checkbox row.
    dy = 26;
    ctrl = uicheckbox(parent, 'Text', lbl, 'Value', defVal, ...
        'Position', [14 y-20 280 20], 'FontSize', 11);
    yOut = y - dy;
end
