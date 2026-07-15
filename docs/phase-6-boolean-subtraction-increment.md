# Phase 6 Boolean Subtraction Increment

CadPilot now supports explicit rectangular Boolean subtraction through a supported plate solid.

## Delivered

- Boolean Cut toolbar action using a second sketch rectangle.
- Persisted, suppressible, renameable, deleteable, and undoable subtraction operation.
- Full-depth rectangular opening with exact analytic volume, surface-area, and material-mass deltas.
- Boundary and circular/rectangular overlap validation.
- Rectangular opening visualization in the 3D viewport.
- Bounded-tolerance closed-manifold STL export for rectangular and mixed non-overlapping circular cuts.
- Topology guards for shells, revolved solids, and unsupported operation ordering.

## Geometry scope

This increment subtracts an axis-aligned rectangular sketch profile through the complete depth of an extruded plate. Partial-depth pockets, arbitrary Boolean tools, unions, intersections, rotated profiles, and multi-body workflows remain future topology work.

## Verification

- Flutter static analysis passes without issues.
- The full Flutter test suite passes, including persistence, suppression, properties, validation, mixed cuts, manifold topology, and STL export.
- Android debug APK build is required before release.
