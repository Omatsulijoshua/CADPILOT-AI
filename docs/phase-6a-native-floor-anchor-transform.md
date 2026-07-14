# Phase 6A: Native floor-anchor transform

This increment defines the precision handoff from CadPilot placement records to the transform format consumed by ARKit and ARCore.

## Included

- Conversion of CAD dimensions and offsets from millimetres to metres.
- Conversion from CadPilot's Z-up coordinate convention to the Y-up convention used by native AR sessions.
- A 4x4 column-major transform matrix compatible with native rendering APIs.
- Rotation conversion from degrees to a floor-plane yaw matrix.
- Independent metre-based width, height, and depth values for 1:1 model rendering.
- Immutable transform arrays.
- Strict rejection when a non-floor placement is passed to the floor-anchor adapter.

## Coordinate mapping

For floor placement, CadPilot X maps to native X, CadPilot Z maps to native Y, and forward CadPilot Y maps to negative native Z. Translation and model dimensions are divided by 1,000 exactly. No user scale factor is applied.

## Scope boundary

This adapter intentionally supports floor anchors only. Wall, ceiling, and arbitrary-plane transforms require a native plane basis and will be implemented as separate adapters rather than approximated with incorrect orientation math.

## Verification

- Flutter static analysis passes.
- All 80 Flutter tests pass.
- Metre conversion, axis mapping, 90-degree yaw, homogeneous matrix output, and plane rejection are covered by tests.
- Android debug APK builds successfully.
