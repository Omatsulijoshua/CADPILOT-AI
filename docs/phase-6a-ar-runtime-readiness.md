# Phase 6A: AR runtime readiness

This increment separates device AR compatibility from installation/readiness of the platform AR runtime.

## Included

- Adds `SpatialCapabilities.arRuntimeInstalled` with a fail-closed default.
- Android reports true only for ARCore `SUPPORTED_INSTALLED`; supported-but-missing and outdated runtime states remain false.
- iOS reports runtime readiness alongside ARKit world-tracking support because ARKit is part of the operating system.
- Placement preflight now requires device support, plane detection, an installed runtime, the CadPilot renderer, and camera permission.
- The spatial capability panel shows a separate **AR runtime** status chip.
- Missing or outdated runtime produces a specific blocker and manual-placement fallback.

## Verification

- Dedicated supported-device/missing-runtime regression coverage passes.
- `flutter analyze --no-pub` passed with no issues.
- All 111 Flutter tests passed.
- Android debug APK compiled successfully.
- Flutter Web release build succeeded.

The renderer remains reported separately and unavailable until the native camera/render host is implemented.
