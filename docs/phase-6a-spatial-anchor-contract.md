# Phase 6A: Spatial anchor contract

This increment adds the persistent application contract that native ARKit and ARCore anchors will populate.

## Included

- Optional native anchor identity on every spatial placement.
- Anchor platform, last-update time, and tracking state.
- Tracking, limited, paused, and stopped lifecycle states.
- Attach, update, and detach operations that preserve the placement's 1:1 transform.
- Explicit `Unanchored placement plan` labeling when no native anchor exists.
- Anchor platform and tracking state displayed for anchored records.
- Safe duplication that always detaches the source anchor and unlocks the copy, preventing two plans from claiming one native anchor.
- Backward-compatible loading for all existing unanchored placements.

## Scope boundary

This is the persisted anchor contract and truthful UI state. Native plane ray-casting and anchor creation are not claimed complete in this increment. ARKit and ARCore implementations must populate this contract only after a real plane anchor is created.

## Verification

- Flutter static analysis passes.
- All 76 Flutter tests pass.
- Anchor serialization, tracking updates, and safe detach behavior are covered by tests.
- Android debug APK builds successfully.
