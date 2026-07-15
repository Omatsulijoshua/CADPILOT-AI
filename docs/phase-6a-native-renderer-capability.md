# Phase 6A: Native renderer capability separation

This increment separates device-level AR support from availability of a CadPilot-hosted native AR renderer.

## Included

- `SpatialCapabilities.nativeArRendererAvailable` is decoded independently from camera, motion tracking, plane detection, ARCore, and ARKit support.
- Android and iOS currently report the renderer as unavailable, matching their explicit fail-closed operation routes.
- AR placement preflight requires device AR, plane detection, camera permission, and a CadPilot renderer.
- The spatial workspace shows a separate **CadPilot AR renderer** capability chip.
- Devices with AR-capable hardware but no CadPilot renderer fall back to manual placement and never label the record `camera_ar`.
- Older or incomplete capability payloads default renderer availability to false.

## Verification

- Device-only AR fallback has dedicated regression coverage.
- `flutter analyze --no-pub` passed with no issues.
- All 110 Flutter tests passed.
- Android debug APK built successfully.
- Flutter Web release build succeeded.

The iOS source reports the same capability but cannot be compiled in this Windows environment.
