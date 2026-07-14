# Phase 6A: True-scale placement locking

This increment establishes the persistent transform-lock contract required before live AR anchors are connected.

## Included

- Every spatial placement is explicitly stored and displayed at 1:1 scale.
- Scale is not user-adjustable, preventing accidental model resizing in placement workflows.
- Persistent lock/unlock state for each placement.
- Locked placements cannot be edited or deleted until explicitly unlocked.
- Duplication remains available so users can create a separate planning variant without modifying a locked record.
- Existing projects remain compatible; older placements default to unlocked and true scale.

## Scope boundary

This is the application-level true-scale and transform-lock contract. A live AR renderer must consume the same millimetre-based dimensions and fixed scale when native plane anchors are added. This increment does not claim that a real-world anchor already exists.

## Verification

- Flutter static analysis passes.
- All 75 Flutter tests pass.
- Lock persistence, immutable unlock, identity preservation, and fixed scale are covered by tests.
- Android debug APK builds successfully.
