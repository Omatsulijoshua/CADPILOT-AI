# Phase 6A: Spatial capability detection

This increment establishes the safe foundation for CadPilot's AR placement and spatial scanning workflows.

## Included

- A native capability channel for Android and iOS.
- Truthful labels that distinguish LiDAR depth scanning, camera-based AR tracking, and manual measurement fallback.
- Detection for camera access, motion tracking, plane detection, scene depth, and mesh reconstruction where the operating system exposes them.
- An `AR / Scan` entry point in the project workspace.
- Camera privacy declarations for Android and iOS.
- A safe manual fallback when a native plugin or supported sensor is unavailable.

Android only reports camera AR when a camera, gyroscope, and installed ARCore runtime are present. It does not claim LiDAR or depth support from ARCore availability alone.

iOS reports LiDAR only when ARKit exposes both scene-depth semantics and scene-reconstruction support. Devices that support world tracking but not those depth capabilities are labeled as camera AR.

## Scope boundary

This increment detects and communicates device readiness. Live camera rendering, plane anchors, object placement, spatial capture, and scan-to-CAD reconstruction remain follow-up work. The current action buttons therefore identify the planned workflow without pretending that capture has started.

## Verification

- Flutter static analysis passes.
- 69 Flutter tests pass, including mocked native capability and missing-plugin fallback coverage.
- Android debug APK builds successfully.
- The iOS native implementation is included but requires macOS and Xcode for device compilation and validation.
