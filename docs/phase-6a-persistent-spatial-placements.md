# Phase 6A: Persistent spatial placements

This increment turns spatial capability detection into useful project data without overstating live AR support.

## Included

- A placement planner available through the existing `AR / Scan` workspace.
- Manual entry for real-world width, height, depth, XYZ offsets, rotation, and mounting plane.
- Capture-source metadata that distinguishes camera AR planning from manual measurement.
- Placement records persisted with each CadPilot project and restored across app sessions.
- Backward-compatible loading: projects saved before this increment receive an empty placement list.
- A compact saved-placement summary in the spatial workspace.
- Validation for required names, positive dimensions, and numeric transforms.

## Spatial record

Each placement contains an identifier, name, creation timestamp, source, plane, dimensions in millimetres, XYZ offsets in millimetres, and rotation in degrees. This record is designed to accept a native plane-anchor identifier and transform in a later live AR increment.

## Truthful behavior

When camera AR is supported, the planner says that the record is ready for a future live plane anchor. When AR is unavailable, it explicitly uses manual fallback and does not claim an anchor or sensor measurement. Live camera rendering and plane anchoring are not claimed complete.

## Verification

- Flutter static analysis passes.
- All 71 Flutter tests pass.
- Project serialization and legacy-project compatibility are covered by tests.
- Android debug APK builds successfully.
