# Phase 6A: Spatial placement lifecycle

This increment completes the local lifecycle for persistent spatial placement plans.

## Included

- Edit saved placement names, planes, dimensions, offsets, and rotation.
- Preserve record identity and creation time while editing.
- Duplicate a placement into a new independently identified record.
- Delete a placement only after explicit confirmation.
- Update the open spatial workspace immediately after each operation.
- Persist the complete updated placement collection through the project store.

These operations remain valid for both manual measurement records and camera-AR-ready plans. They do not claim that a live native anchor exists.

## Verification

- Flutter static analysis passes.
- All 72 Flutter tests pass.
- Immutable placement updates are covered by tests.
- Android debug APK builds successfully.
