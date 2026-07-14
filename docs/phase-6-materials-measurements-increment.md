# Phase 6 materials and measurements increment

This increment adds persisted engineering material assignment and live solid-property measurements to the 3D model workspace.

## Materials

- Generic, with no density or mass estimate.
- PLA at 1.24 g/cm^3.
- Aluminum 6061 at 2.70 g/cm^3.
- Mild steel at 7.85 g/cm^3.

Material changes are stored in the model document, preserved by feature edits, survive reopening, and participate in model undo/redo history.

## Measurements

The 3D sidebar reports overall width, height, depth, net volume, surface area, and estimated mass. Through-cuts subtract cylindrical volume, remove their top and bottom circular areas, and add the cylindrical bore wall area. Mass is calculated from net volume and the assigned density.

## Verify

1. Create an extrusion and optional circular through-cut.
2. Switch among Generic, PLA, Aluminum 6061, and Mild steel.
3. Confirm dimensions and geometric measurements remain fixed while mass changes with density.
4. Add or suppress a through-cut and confirm volume, surface area, and mass update.
5. Undo and redo a material assignment.
6. Close and reopen the project and confirm the material and measurements are restored.

## Honest limitations

Measurements currently cover one evaluated rectangular extrusion with non-overlapping circular through-holes. Density is a nominal estimate and does not include manufacturing porosity, infill, coatings, tolerances, or anisotropy. Arbitrary B-rep mass properties will require the native OpenCascade evaluator.