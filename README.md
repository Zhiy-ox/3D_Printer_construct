# TPP-DLW Toolpath Generator

MATLAB tools for converting STL geometry into tab-separated toolpath segments
for a LabVIEW-controlled two-photon polymerization / direct laser writing setup.

The generated text format is:

```text
X1    Y1    Z1    X2    Y2    Z2
```

Each row represents either a laser-on write segment or a layer-to-layer Z move.
Coordinates are in millimeters.

For a printable new-user guide, see [README.PDF](README.PDF).

## What Is Included

- `stl_slice_export_mm_woodpile_true_resample.m`: fastest standalone STL to TXT
  converter for large height-map style STL files.
- `tppdlw_process.m`: modular conversion pipeline for general STL/STEP-style
  workflows.
- `core/`: import, slicing, hatching, path ordering, and segment writing helpers.
- `viz/`: 2D/3D preview and layer-comparison tools.
- `gui/`: MATLAB GUI entry point.
- `examples/` and `tests/`: basic usage and output-format checks.
- `tools/build_readme_pdf.py`: rebuilds the PDF user guide.

Generated STL/TXT exports are intentionally ignored by Git. Put large outputs in
`output/` unless you deliberately want to version them.

## Requirements

- MATLAB.
- Python with `reportlab` only if you want to rebuild `README.PDF`.
- A valid, watertight STL gives the most reliable slicing result.

No external MATLAB dependency is required for the main STL-to-TXT workflow.

## Quick Start

Open this folder in MATLAB and run:

```matlab
run('stl_slice_export_mm_woodpile_true_resample.m')
```

Edit the user parameters near the top of that file before production runs:

- `STLPath`: input STL file.
- `OutTxt`: destination tab-separated TXT file.
- `TargetMaxXY`: target XY footprint in millimeters.
- `XYPitch`: spacing between adjacent raster scanlines.
- `DZ`: layer thickness / vertical slicing step.
- `SquareGrid`: force equal X/Y grid counts for woodpile-style output.
- `WoodpileMode`: alternate horizontal and vertical writing by layer.
- `OptimizePath`: enable greedy nearest-neighbor segment ordering.
- `OptimizeMaxSegments`: skip expensive greedy ordering above this layer size.
- `TraceContour`: keep `false` for height-map raster exports. Turning it on
  writes boundary/outline rows before hatch rows.
- `OutputSignificantDigits`: compact numeric precision for the TXT file.

For preview runs, use a larger `XYPitch` and `DZ` so conversion finishes quickly.
Restore final pitch/layer values only after the previewed layers look correct.

## Preview Before Printing

After generating a TXT file, inspect representative layers before using it on
the printer:

```matlab
addpath(genpath(pwd))
segments = load('output/Final.txt');
preview_toolpath(segments, 'Layer', 1, 'Mode', '2d')
preview_3d(segments, 'EveryN', 2)
```

Check for:

- long write lines crossing empty space,
- unexpected zero-length rows,
- out-of-bounds coordinates,
- unusually high segment counts on a single layer,
- console warnings about skipped odd scanlines or open contours.

If the first rows are short fragments along `X = 0` or another boundary, contour
tracing is probably enabled. Disable `TraceContour` / `ContourFirst` for the
height-map workflow so the TXT starts with hatch-fill rows such as full-width
base scanlines.

The current converter skips unresolved odd scanlines instead of force-pairing
them. This avoids false long write lines when an STL is open or non-manifold.

## Tests

From MATLAB:

```matlab
addpath(genpath(pwd))
run('tests/test_output_format.m')
run('tests/test_hatch_square.m')
run('tests/test_full_pipeline.m')
```

## Rebuild The PDF Guide

From the project root:

```bash
python3 tools/build_readme_pdf.py
```

This regenerates `README.PDF`.

## Publishing Notes

Keep source code, examples, tests, and documentation in Git. Keep large generated
printer outputs, STL files, MATLAB cache files, and local scratch files out of
Git unless they are intentionally small public examples.
