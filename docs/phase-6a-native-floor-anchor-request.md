# Phase 6A: Native floor-anchor request boundary

This increment defines the validated method-channel contract that native ARKit and ARCore floor ray-casting implementations will receive.

## Included

- A native request payload containing placement identity, floor-plane type, fixed 1:1 scale, 16-value column-major transform, and metre-based model dimensions.
- A service method that sends `createFloorAnchor` only after successful AR preflight.
- Native response decoding into the persisted spatial-anchor contract.
- Fail-closed handling for platform errors, missing native implementations, and web builds.
- Rejection of manual-source placements, non-floor placements, already-anchored records, and failed preflight before any native call.

## Safety rules

The method channel is not exposed as a user action until the platform implementation can create a real plane anchor. A null result means no anchor was created and must never be persisted as success. Retrying requires a fresh native ray cast.

## Verification

- Flutter static analysis passes.
- All 82 Flutter tests pass.
- Payload shape, 1:1 scale, native anchor decoding, and zero-call blocked behavior are covered by tests.
- Android debug APK builds successfully.
