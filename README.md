# 3D Printer Construct

MATLAB tools for converting STL geometry into tab-separated LabVIEW-compatible
toolpath rows:

```text
X1    Y1    Z1    X2    Y2    Z2
```

## Fast STL to TXT Workflow

Use the optimized standalone converter:

```matlab
run('stl_slice_export_mm_woodpile_true_resample.m')
```

Edit the user parameters at the top of that file:

- `STLPath`: input STL file.
- `OutTxt`: output text file.
- `TargetMaxXY`: final XY footprint in mm.
- `XYPitch`: in-plane raster pitch in mm.
- `DZ`: slice thickness in mm.
- `OptimizeMaxSegments`: cap for O(N^2) greedy path ordering.

For quick previews, increase `XYPitch` and `DZ`. Restore the final values only
for production exports.

## Performance Notes

The optimized converter is the recommended path for large STL height maps. It
uses:

- vectorized binary STL loading,
- triangle Z-range prefiltering per slice,
- scanline bucketing for raster fill,
- preallocated output buffers,
- capped greedy nearest-neighbor ordering.

The project also includes the modular `tppdlw_process` pipeline and GUI for
general STL/STEP workflows.

