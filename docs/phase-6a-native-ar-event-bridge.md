# Phase 6A: Native AR event bridge

This increment adds the validated event envelope and coordinator between native ARKit/ARCore callbacks and CadPilot's AR session state machine.

## Included

- Required session ID, non-negative sequence number, and known event name on every native event.
- Optional plane ID, anchor ID, and diagnostic message forwarding.
- Session-scoped coordination that ignores callbacks from expired sessions.
- Strictly increasing event sequence enforcement for the active session.
- State mutation only after both envelope validation and session transition validation succeed.
- Last accepted sequence tracking for diagnostics.

## Ordering rule

Callbacks for a different session ID are ignored without changing state or sequence. Duplicate or decreasing sequence numbers for the active session are rejected. Malformed and unknown events never reach the state reducer.

## Verification

- Flutter static analysis passes.
- All 88 Flutter tests pass.
- Active-session flow, stale-session rejection, sequence protection, malformed envelopes, and unknown events are covered by tests.
- Android debug APK builds successfully.
