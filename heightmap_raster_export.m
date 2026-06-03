%% heightmap_raster_export.m
% Height-map STL/CSV -> raster toolpath TXT.
%
% Use this for pixel-exact height-map data. Unlike contour slicing, this path
% does not intersect scanlines with STL boundaries, so it avoids odd-crossing
% warnings and false boundary fragments.

% ========================= USER PARAMETERS =========================
HeightMapPath = fullfile('examples','models','final_lut_height_map_6um_pixel_exact_base0p5um.stl');
OutTxt        = fullfile('output','Final_YH_05um.txt');

% Source height-map parameters. For the generated STL, PixelPitch is read from
% the STL header ("pitch=6um"). For CSV input, set PixelPitch to the pixel size
% in the CSV units, for example 6 when each pixel is 6 um.
PixelPitch    = [];
AddBaseHeight = 0;       % use >0 for CSV if the CSV height does not include a base

% Output scale and raster resolution (mm)
TargetMaxXY   = 1.005;   % final max XY span in mm
XYPitch       = 0.0004;  % output hatch pitch in mm
DZ            = 0.0005;  % output layer height in mm

% Toolpath behavior
WoodpileMode  = true;    % odd layers X-directed, even layers Y-directed
Serpentine    = true;    % alternate direction on adjacent scanlines
CoordMode     = 'edges'; % matches existing base rows: x = 0 ... 1.005
StageZConvention = true; % write positive build height as negative stage Z
Tolerance_mm  = 1e-12;

% TXT formatting
OutputSignificantDigits = 6;
Verbose = true;
% ===================================================================

ExitCode = 1; ErrMsg = ''; Segments_mm = zeros(0, 6);
try
    tJob = tic;
    rootDir = fileparts(mfilename('fullpath'));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'core'));
    addpath(fullfile(rootDir, 'viz'));

    assert(exist(HeightMapPath, 'file') == 2, 'Height map source not found: %s', HeightMapPath);
    assert(XYPitch > 0, 'XYPitch must be > 0.');
    assert(DZ > 0, 'DZ must be > 0.');

    if Verbose
        fprintf('\n[%s] Reading height-map source: %s\n', datestr(now, 'HH:MM:SS'), HeightMapPath);
    end

    hm = read_heightmap_source(HeightMapPath, ...
        'PixelPitch', PixelPitch, ...
        'AddBaseHeight', AddBaseHeight, ...
        'Units', 'um');

    if Verbose
        fprintf('[%s] Height map: %d x %d cells, pitch=[%.10g %.10g] %s\n', ...
            datestr(now, 'HH:MM:SS'), size(hm.Height, 2), size(hm.Height, 1), ...
            hm.SourcePitch(1), hm.SourcePitch(2), hm.Units);
        if ~isempty(hm.BaseHeight)
            fprintf('[%s] STL header base height: %.10g %s\n', ...
                datestr(now, 'HH:MM:SS'), hm.BaseHeight, hm.Units);
        end
    end

    [Segments_mm, info] = heightmap_to_segments(hm.Height, ...
        'SourcePitch', hm.SourcePitch, ...
        'TargetMaxXY', TargetMaxXY, ...
        'HatchPitch_mm', XYPitch, ...
        'LayerHeight_mm', DZ, ...
        'StageZConvention', StageZConvention, ...
        'WoodpileMode', WoodpileMode, ...
        'Serpentine', Serpentine, ...
        'CoordMode', CoordMode, ...
        'Tolerance_mm', Tolerance_mm);

    write_segments(Segments_mm, OutTxt, OutputSignificantDigits);

    if Verbose
        fprintf('[%s] Height-map raster export complete.\n', datestr(now, 'HH:MM:SS'));
        fprintf(' Source cells: %d x %d\n', info.SourceSize(2), info.SourceSize(1));
        fprintf(' Output grid:  %d x %d\n', info.OutputGridSize(2), info.OutputGridSize(1));
        fprintf(' Output span:  %.10g x %.10g mm\n', info.SpanXY_mm(1), info.SpanXY_mm(2));
        fprintf(' Layers:       %d\n', info.LayerCount);
        fprintf(' Write rows:   %d scan rows + %d Z-hop rows\n', ...
            info.LayerRows, max(0, info.LayerCount - 1));
        fprintf(' Output:       %s\n', OutTxt);
        fprintf(' Elapsed:      %.2f s\n\n', toc(tJob));
    end

    ExitCode = 0;
catch ME
    ErrMsg = ME.message;
    warning('heightmap_raster_export:error', '%s', ErrMsg);
    ExitCode = 1;
end
