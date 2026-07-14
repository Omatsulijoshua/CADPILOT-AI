# Phase 6A: Camera permission readiness

This increment adds explicit native camera-permission readiness for future AR placement and scan capture.

## Included

- Android permission status and runtime request handling.
- iOS AVFoundation authorization status and request handling.
- Distinct granted, not-requested, denied, permanently-denied, restricted, and unavailable states.
- A user-initiated `Check camera access` action in the spatial workspace.
- A safe result dialog that keeps manual placement available when access is not granted.
- Protection against overlapping Android permission requests.
- Missing-plugin and platform-error behavior that fails closed.

## Privacy behavior

CadPilot does not activate the camera when opening the spatial workspace. The native permission prompt is requested only after the user chooses the camera-access action. Granting permission does not start capture; a future explicit AR or scan workflow must do that.

## Verification

- Flutter static analysis passes.
- All 74 Flutter tests pass.
- Android debug APK builds successfully, including the Kotlin permission callback.
- The iOS implementation requires macOS/Xcode for native compilation and device validation.
