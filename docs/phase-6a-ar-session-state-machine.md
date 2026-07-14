# Phase 6A: AR session state machine

This increment defines the deterministic lifecycle that native ARKit and ARCore session callbacks must follow.

## Included

- Idle, initializing, plane-searching, plane-ready, placing, anchored, interrupted, failed, and stopped phases.
- Explicit startup, session-ready, plane-found, plane-lost, placement, anchor-created, interruption, resume, failure, and stop events.
- Plane identity retained through placement.
- Native anchor identity required before entering the anchored phase.
- Recovery from plane loss and tracking interruption.
- Retry from failed and stopped sessions.
- Terminal failure and stop states.
- Immediate rejection of invalid event ordering or missing native identifiers.

## Integration rule

Platform callbacks must be reduced through this state machine before changing the visible AR workflow or persisting an anchor. A method-channel response alone is not sufficient to declare a placement anchored.

## Verification

- Flutter static analysis passes.
- All 85 Flutter tests pass.
- Normal placement, plane loss, interruption, resume, failure, retry, stop, invalid ordering, and missing identifiers are covered by tests.
- Android debug APK builds successfully.
