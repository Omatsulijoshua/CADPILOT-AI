# Phase 6A: AR screenshot capture contract

This increment defines the validated Flutter-to-native boundary for capturing an AR placement screenshot without claiming that an unsupported native renderer completed a capture.

## Included

- Screenshot requests require a non-empty active session ID and an anchored AR session.
- The native request carries the active session and anchor identities.
- Native results require a file path, positive pixel dimensions, a valid UTC capture time, and matching session and anchor IDs.
- Malformed or cross-session results are rejected before they can be persisted or shown as success.
- Missing and unsupported native implementations fail closed with no screenshot result.

## Scope boundary

The Android and iOS runners do not yet host a live AR camera renderer, so no user-facing capture button is exposed by this increment. Native ARCore and ARKit render capture will implement `captureArScreenshot` against this contract in a later increment.

## Verification

- `flutter analyze --no-pub` passes with no issues.
- All 98 Flutter tests pass.
- Android debug APK builds successfully.
- Request gating, payload shape, result validation, identity matching, and missing-platform behavior are covered by tests.

The iOS native target is not compiled in this Windows verification environment.
