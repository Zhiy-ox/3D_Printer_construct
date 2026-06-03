function cfg = tppdlw_config(varargin)
% TPPDLW_CONFIG  Create configuration struct for TPP-DLW toolpath generation.
%
%   cfg = tppdlw_config()
%       Returns default configuration for micro-scale TPP-DLW.
%
%   cfg = tppdlw_config('Param1', val1, 'Param2', val2, ...)
%       Override any parameter via name-value pairs.
%
%   cfg = tppdlw_config('ConfigFile', 'path/to/config.json')
%       Load parameters from a JSON file, then apply any additional overrides.
%
% ---- Parameters (all lengths in mm) ----
%
%   InputFile        : Path to STEP or STL file              (default: '')
%   OutputFile       : Output .txt path                      (default: 'output/segments.txt')
%
%   TargetSize_mm    : Scale model so max(X,Y) = this value  (default: 0.1)
%   AutoScale        : If false, use model's native units     (default: true)
%
%   LayerHeight_mm   : Z step per layer                      (default: 0.0005 = 0.5 um)
%   FirstLayerZ_mm   : Z of first layer center ([] = auto)   (default: [])
%
%   HatchSpacing_mm  : Distance between parallel scan lines  (default: 0.0003 = 0.3 um)
%
%   ScanAngle_deg    : Initial scan angle (0 = X-directed)   (default: 0)
%   AngleIncrement_deg : Rotation per layer                  (default: 90)
%   AngleMode        : 'fixed' | 'alternating' | 'incremental' (default: 'alternating')
%
%   Serpentine       : Boustrophedon within each layer        (default: true)
%   OptimizePath     : Greedy nearest-neighbor reordering     (default: true)
%   OptimizeMaxSegments : Max layer segments for greedy path  (default: 15000)
%
%   TraceContour     : Trace boundary before hatching         (default: false)
%   ContourFirst     : true=contour then hatch; false=hatch only (default: true)
%   Overrun_mm       : Extend scan lines beyond boundary      (default: 0)
%
%   OutputSignificantDigits : TXT numeric precision           (default: 6)
%
%   OffsetX_mm       : Shift entire output in X               (default: 0)
%   OffsetY_mm       : Shift entire output in Y               (default: 0)
%   OffsetZ_mm       : Shift entire output in Z               (default: 0)
%   CenterOrigin     : Center XY at (0,0) before offset       (default: false)
%
%   CoordMode        : 'centers' | 'edges'                   (default: 'centers')
%   Margin_mm        : XY padding around bounding box        (default: 0)
%   Tolerance_mm     : Geometric tolerance                   (default: 1e-9)
%
% ---- Example ----
%   cfg = tppdlw_config('InputFile', 'part.step', ...
%                        'LayerHeight_mm', 0.0004, ...
%                        'AngleMode', 'incremental', ...
%                        'AngleIncrement_deg', 45);
%   tppdlw_process(cfg);
%
% See also: tppdlw_process, import_model, build_toolpath

    % ===================== Defaults =====================
    cfg = struct();

    % File I/O
    cfg.InputFile        = '';
    cfg.OutputFile       = 'output/segments.txt';

    % Scaling
    cfg.TargetSize_mm    = 0.1;        % 100 um
    cfg.AutoScale        = true;

    % Slicing
    cfg.LayerHeight_mm   = 0.0005;     % 0.5 um
    cfg.FirstLayerZ_mm   = [];         % auto: zmin + LayerHeight/2

    % Hatching
    cfg.HatchSpacing_mm  = 0.0003;     % 0.3 um

    % Writing direction
    cfg.ScanAngle_deg       = 0;       % 0 deg = X-directed scan
    cfg.AngleIncrement_deg  = 90;      % rotation per layer
    cfg.AngleMode           = 'alternating';  % 'fixed' | 'alternating' | 'incremental'

    % Path ordering
    cfg.Serpentine       = true;
    cfg.OptimizePath     = true;
    cfg.OptimizeMaxSegments = 15000;    % Greedy ordering is O(N^2)

    % Contour + hatch mode
    cfg.TraceContour     = false;      % Boundary tracing adds outline rows; keep hatch-only by default
    cfg.ContourFirst     = true;       % Used only when TraceContour is true
    cfg.Overrun_mm       = 0;          % Extend scan line endpoints (mm)
    cfg.OutputSignificantDigits = 6;   % Compact TXT output, e.g. 0.0002 instead of long decimals

    % Origin / offset control
    cfg.OffsetX_mm       = 0;          % Shift output X
    cfg.OffsetY_mm       = 0;          % Shift output Y
    cfg.OffsetZ_mm       = 0;          % Shift output Z
    cfg.CenterOrigin     = false;      % Center XY at (0,0) before applying offset

    % Coordinates
    cfg.CoordMode        = 'centers';  % 'centers' | 'edges'
    cfg.Margin_mm        = 0.0;
    cfg.Tolerance_mm     = 1e-9;

    % ===================== Load from JSON if specified =====================
    % Check if 'ConfigFile' is in varargin (before general parsing)
    idx = find(strcmpi(varargin, 'ConfigFile'));
    if ~isempty(idx)
        jsonPath = varargin{idx(end) + 1};
        assert(exist(jsonPath, 'file') == 2, 'Config file not found: %s', jsonPath);
        jsonData = jsondecode(fileread(jsonPath));
        cfg = merge_struct(cfg, jsonData);
        % Remove ConfigFile entries from varargin
        removeIdx = sort([idx, idx+1], 'descend');
        for ri = 1:numel(removeIdx)
            varargin(removeIdx(ri)) = [];
        end
    end

    % ===================== Apply name-value overrides =====================
    validFields = fieldnames(cfg);
    for k = 1:2:numel(varargin)
        name = varargin{k};
        val  = varargin{k+1};
        % Case-insensitive field matching
        matchIdx = strcmpi(validFields, name);
        if any(matchIdx)
            cfg.(validFields{matchIdx}) = val;
        else
            warning('tppdlw_config:unknownParam', ...
                'Unknown parameter: %s. Ignored.', name);
        end
    end

    % ===================== Validation =====================
    assert(cfg.LayerHeight_mm > 0,  'LayerHeight_mm must be > 0');
    assert(cfg.HatchSpacing_mm > 0, 'HatchSpacing_mm must be > 0');
    assert(ismember(lower(cfg.AngleMode), {'fixed','alternating','incremental'}), ...
        'AngleMode must be ''fixed'', ''alternating'', or ''incremental''.');
    cfg.AngleMode = lower(cfg.AngleMode);
    assert(ismember(lower(cfg.CoordMode), {'centers','edges'}), ...
        'CoordMode must be ''centers'' or ''edges''.');
    cfg.CoordMode = lower(cfg.CoordMode);
    assert(isnumeric(cfg.OptimizeMaxSegments) && isscalar(cfg.OptimizeMaxSegments) && ...
           cfg.OptimizeMaxSegments > 0, 'OptimizeMaxSegments must be a positive scalar.');
    assert(isnumeric(cfg.OutputSignificantDigits) && isscalar(cfg.OutputSignificantDigits) && ...
           cfg.OutputSignificantDigits >= 4 && cfg.OutputSignificantDigits <= 15, ...
           'OutputSignificantDigits must be between 4 and 15.');
    cfg.OutputSignificantDigits = round(cfg.OutputSignificantDigits);
    cfg.Tolerance_mm = max(cfg.Tolerance_mm, 1e-12);
end

% ===================== Helper: merge struct =====================
function base = merge_struct(base, overlay)
    fnames = fieldnames(overlay);
    baseFields = fieldnames(base);
    for i = 1:numel(fnames)
        matchIdx = strcmpi(baseFields, fnames{i});
        if any(matchIdx)
            base.(baseFields{matchIdx}) = overlay.(fnames{i});
        end
    end
end
