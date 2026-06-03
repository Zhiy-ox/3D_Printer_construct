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

- `heightmap_raster_export.m`: recommended converter for pixel-exact height-map
  STL/CSV files. It rasterizes directly from heights and does not use contour
  intersection pairing.
- `stl_slice_export_mm_woodpile_true_resample.m`: contour-slicing STL exporter
  for cases where a true height map is not available.
- `tppdlw_process.m`: modular conversion pipeline for general STL/STEP-style
  workflows.
- `core/`: import, slicing, hatching, path ordering, and segment writing helpers.
- `viz/`: 2D/3D preview and layer-comparison tools.
- `gui/`: MATLAB GUI entry point with `Height-map raster` and `Contour slicing`
  workflow modes.
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
run('heightmap_raster_export.m')
```

Edit the user parameters near the top of that file before production runs:

- `HeightMapPath`: input height-map STL or CSV file.
- `OutTxt`: destination tab-separated TXT file.
- `TargetMaxXY`: target XY footprint in millimeters.
- `XYPitch`: spacing between adjacent raster scanlines.
- `DZ`: layer thickness / vertical slicing step.
- `WoodpileMode`: alternate horizontal and vertical writing by layer.
- `PixelPitch`: source pixel pitch for CSV; STL files can read this from the
  generated STL header when available.
- `BaseHeight`: support base height in source units. Use `0` when the STL
  already includes a base; use `0.5` for a CSV that needs a 0.5 um base.
- `CoordMode`: use `edges` to match full-width base rows like `0 ... 1.005`.
- `OutputSignificantDigits`: compact numeric precision for the TXT file.

For preview runs, use a larger `XYPitch` and `DZ` so conversion finishes quickly.
Restore final pitch/layer values only after the previewed layers look correct.

### Size, Pixel Pitch, And Base Height

For height-map raster export there are three different pitches/sizes:

- `PixelPitch` is the original source pixel spacing, in the same units as the
  height map. For your original CSV, this is `6` because each pixel is 6 um.
- `TargetMaxXY` controls the final printed XY footprint in millimeters. If this
  is set, it is the parameter that controls the maximum XY size.
- `XYPitch` is the printer raster scanline spacing in millimeters. It controls
  writing resolution and TXT size, not the source model footprint.

When `TargetMaxXY` is set, the final source-pixel pitch is derived from the
target size and grid dimensions. For a square `335 x 335` height map with
`TargetMaxXY = 1.005`, one source pixel becomes `1.005 / 335 = 0.003 mm`
wide in the final print. The raster scanline spacing can still be finer, for
example `XYPitch = 0.0004 mm`.

`BaseHeight` is added inside `heightmap_to_segments` before generating raster
scanlines. It is expressed in source units, so with a micron-valued CSV,
`BaseHeight = 0.5` means a 0.5 um support base. If the input STL was already
generated with a base, leave `BaseHeight = 0` to avoid adding it twice.

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
- unexpected contour-slicing warnings. The height-map raster exporter should not
  report odd contour-crossing warnings.

If the first rows are short fragments along `X = 0` or another boundary, you are
probably using a contour-slicing workflow. Use `heightmap_raster_export.m` for
pixel-exact height-map data so the TXT starts with hatch-fill rows such as
full-width base scanlines.

The current converter skips unresolved odd scanlines instead of force-pairing
them. This avoids false long write lines when an STL is open or non-manifold.

## Tests

From MATLAB:

```matlab
addpath(genpath(pwd))
run('tests/test_output_format.m')
run('tests/test_heightmap_raster.m')
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
