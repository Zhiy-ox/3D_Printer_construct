function segments_mm = tppdlw_process(cfg)
% TPPDLW_PROCESS  Main entry point: STEP/STL -> .txt segment file.
%
%   segments_mm = tppdlw_process(cfg)
%
% INPUT:
%   cfg - Configuration struct from tppdlw_config(). Must include at
%         minimum cfg.InputFile pointing to a valid STEP or STL file.
%
% OUTPUT:
%   segments_mm - Nx6 matrix [x1 y1 z1 x2 y2 z2] of all segments (mm).
%                 Also written to cfg.OutputFile as tab-separated .txt.
%
% USAGE:
%   % Basic: STL with default settings
%   cfg = tppdlw_config('InputFile', 'model.stl');
%   tppdlw_process(cfg);
%
%   % STEP with custom parameters
%   cfg = tppdlw_config(...
%       'InputFile',        'part.step', ...
%       'OutputFile',       'output/part_segments.txt', ...
%       'TargetSize_mm',    0.05, ...           % 50 um
%       'LayerHeight_mm',   0.0004, ...         % 0.4 um
%       'HatchSpacing_mm',  0.0003, ...         % 0.3 um
%       'AngleMode',        'incremental', ...  % 0, 45, 90, 135, ...
%       'AngleIncrement_deg', 45);
%   tppdlw_process(cfg);
%
%   % Load config from JSON file
%   cfg = tppdlw_config('ConfigFile', 'examples/configs/default_config.json', ...
%                        'InputFile', 'model.step');
%   tppdlw_process(cfg);
%
% See also: tppdlw_config, import_model, build_toolpath, write_segments

    % ---- Add core/ and viz/ to path ----
    thisDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(thisDir, 'core'));
    addpath(fullfile(thisDir, 'viz'));

    % ---- Validate input ----
    assert(~isempty(cfg.InputFile), ...
        'tppdlw_process:noInput', 'cfg.InputFile must be specified.');
    assert(exist(cfg.InputFile, 'file') == 2, ...
        'tppdlw_process:notFound', 'Input file not found: %s', cfg.InputFile);

    % ---- Banner ----
    fprintf('\n========================================\n');
    fprintf('  TPP-DLW Toolpath Generator\n');
    fprintf('========================================\n');
    fprintf('  Input:  %s\n', cfg.InputFile);
    fprintf('  Output: %s\n', cfg.OutputFile);
    fprintf('----------------------------------------\n');

    % ---- Step 1: Import model ----
    fprintf('\n[1/3] Importing model...\n');
    tic;
    [F, V] = import_model(cfg.InputFile);
    fprintf('  Import time: %.2f s\n', toc);

    % ---- Step 2: Build toolpath ----
    fprintf('\n[2/3] Building toolpath...\n');
    tic;
    segments_mm = build_toolpath(F, V, cfg);
    fprintf('  Toolpath time: %.2f s\n', toc);

    % ---- Step 3: Write output ----
    fprintf('\n[3/3] Writing output...\n');
    write_segments(segments_mm, cfg.OutputFile);

    % ---- Summary ----
    fprintf('\n========================================\n');
    fprintf('  Done!\n');
    fprintf('  Total segments: %d\n', size(segments_mm, 1));
    fprintf('  Output file:    %s\n', cfg.OutputFile);

    % Compute some stats
    scanMask = abs(segments_mm(:,3) - segments_mm(:,6)) < 1e-10;
    nScan = sum(scanMask);
    nTransition = sum(~scanMask);
    fprintf('  Scan segments:  %d\n', nScan);
    fprintf('  Z-transitions:  %d\n', nTransition);

    if nScan > 0
        % Estimate total scan path length
        dx = segments_mm(scanMask, 4) - segments_mm(scanMask, 1);
        dy = segments_mm(scanMask, 5) - segments_mm(scanMask, 2);
        totalLength = sum(sqrt(dx.^2 + dy.^2));
        fprintf('  Total scan length: %.6g mm (%.2f um)\n', ...
            totalLength, totalLength * 1000);
    end
    fprintf('========================================\n\n');
end
