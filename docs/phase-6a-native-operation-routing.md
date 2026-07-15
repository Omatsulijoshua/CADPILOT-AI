# Phase 6A: Explicit native AR operation routing

This increment makes the Android and iOS spatial method-channel hosts recognize every current Phase 6A native operation.

## Included

- Android and iOS explicitly route `startArSession`, `stopArSession`, `createFloorAnchor`, and `captureArScreenshot`.
- Start, anchor, and screenshot requests return the structured `ar_renderer_unavailable` platform error until a real native renderer is attached.
- Stop requests return `false` when no native session is active.
- Request arguments are preserved in error details for diagnostics.
- Flutter converts the explicit native renderer error into a safe false start/stop result.
- Unknown methods remain `notImplemented` so contract mistakes are still visible.

## Truthfulness rule

Capability detection may report device AR support, but native operations never report success unless CadPilot itself hosts a live AR renderer. Installing ARCore or using an ARKit-capable device alone is not presented as an active CadPilot session.

## Verification

- Focused native-error regression tests passed.
- `flutter analyze --no-pub` passed with no issues.
- All 109 Flutter tests passed.
- Android debug APK compiled successfully with the new Kotlin routes.
- Flutter Web release build succeeded.

The Swift routes are source-reviewed but the iOS target cannot be compiled in this Windows environment.
