function write_segments(segments_mm, output_path, significant_digits)
% WRITE_SEGMENTS  Write scan segments to tab-separated .txt file.
%
%   write_segments(segments_mm, output_path)
%   write_segments(segments_mm, output_path, significant_digits)
%
% INPUTS:
%   segments_mm - Nx6 matrix [x1 y1 z1 x2 y2 z2] in mm
%   output_path - Path to output .txt file
%   significant_digits - Optional compact significant digits, default 6
%
% OUTPUT FORMAT:
%   Tab-separated, 6 columns per line, no header.
%   x1\ty1\tz1\tx2\ty2\tz2
%
%   Matches the format of Pyramid_T5-SINGLE.txt for LabVIEW import.
%
% See also: build_toolpath, tppdlw_process

    if nargin < 3 || isempty(significant_digits)
        significant_digits = 6;
    end
    significant_digits = round(significant_digits);
    assert(significant_digits >= 4 && significant_digits <= 15, ...
        'write_segments:precision', 'significant_digits must be between 4 and 15.');

    if isempty(segments_mm)
        warning('write_segments:empty', 'No segments to write.');
        return;
    end

    % Ensure output directory exists
    outDir = fileparts(output_path);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    % Open file
    fid = fopen(output_path, 'w');
    if fid < 0
        error('write_segments:fileError', 'Cannot open output file: %s', output_path);
    end
    cleanupObj = onCleanup(@() fclose(fid));

    % Use significant digits so integers and clean grid coordinates stay compact.
    valueFmt = sprintf('%%.%dg', significant_digits);
    fmt = [valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\t' valueFmt '\n'];
    fprintf(fid, fmt, segments_mm.');

    fprintf('  Written %d segments to: %s\n', size(segments_mm, 1), output_path);
end
