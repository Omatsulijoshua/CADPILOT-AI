# Phase 6A: AR placement preflight

This increment prevents placement records from being mislabeled as camera AR unless the native session prerequisites are satisfied.

## Included

- A deterministic AR placement preflight result.
- Required checks for AR tracking, plane detection, and granted camera access.
- User-initiated camera permission request when an AR-capable device starts placement planning.
- Explicit blocker messages when preflight fails.
- Automatic, truthful manual-source fallback when any prerequisite is missing.
- Unsupported devices never receive a camera permission request.
- Manual planning remains available after denied, blocked, restricted, or unavailable camera access.

## Metadata rule

A placement receives the `camera_ar` source only when all preflight checks pass. Otherwise it is persisted as `manual`. Passing preflight does not claim that a native plane anchor exists; that is represented separately by the optional anchor contract.

## Verification

- Flutter static analysis passes.
- All 78 Flutter tests pass.
- Ready, blocked, and unsupported preflight paths are covered by tests.
- Android debug APK builds successfully.
