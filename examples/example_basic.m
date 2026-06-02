%% example_basic.m
% Basic example: process an STL or STEP file with default settings.
%
% USAGE:
%   1. Place your .stl or .step file in the project folder
%   2. Edit the InputFile path below
%   3. Run this script
%
% This generates a segment .txt file compatible with the LabVIEW interface.

%% Add paths
addpath(fullfile(fileparts(mfilename('fullpath')), '..'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'viz'));

%% ==================== EDIT THESE PARAMETERS ====================

cfg = tppdlw_config(...
    ... % ---- File I/O ----
    'InputFile',          'your_model.stl', ...       % <-- CHANGE THIS
    'OutputFile',         'output/my_print.txt', ...
    ...
    ... % ---- Scale ----
    'TargetSize_mm',      0.1, ...       % max(X,Y) = 100 um
    'AutoScale',          true, ...
    ...
    ... % ---- Slicing ----
    'LayerHeight_mm',     0.0005, ...    % 0.5 um layers
    ...
    ... % ---- Hatching ----
    'HatchSpacing_mm',    0.0003, ...    % 0.3 um line spacing
    ...
    ... % ---- Writing Direction ----
    'ScanAngle_deg',      0, ...         % Start at 0 deg (X-scan)
    'AngleIncrement_deg', 90, ...        % Rotate 90 deg each layer
    'AngleMode',          'alternating', ... % 0, 90, 0, 90, ...
    ...
    ... % ---- Path Optimization ----
    'Serpentine',         true, ...      % Boustrophedon scan
    'OptimizePath',       true ...       % Nearest-neighbor reorder
);

%% ==================== RUN PIPELINE ====================

segments = tppdlw_process(cfg);

%% ==================== PREVIEW ====================

% 2D view of layer 1
figure;
preview_toolpath(segments, 'Layer', 1, 'Mode', '2d');

% 2D view of layer 2 (should be 90 deg rotated)
figure;
preview_toolpath(segments, 'Layer', 2, 'Mode', '2d');

% 3D overview (every 10th layer for speed)
preview_3d(segments, 'EveryN', 10);

fprintf('Done! Output written to: %s\n', cfg.OutputFile);
