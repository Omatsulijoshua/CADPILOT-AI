# Phase 6A: Flutter AR method-channel bridge

This increment connects CadPilot's validated native AR event coordinator to Flutter's platform callback lifecycle.

## Included

- Method-channel handler registration and disposal.
- Acceptance of only the `arSessionEvent` callback method.
- Map-only native event argument validation.
- Active-session envelope reduction through the sequence-validated coordinator.
- UI state notification only after an event is accepted.
- Native acknowledgement containing acceptance status and the last accepted sequence.
- Idempotent start and dispose behavior.
- Explicit rejection of unknown callbacks.

## Lifecycle rule

The bridge must be started when an AR workspace becomes active and disposed when it closes. Disposal removes the native callback handler so events cannot update an inactive widget or a subsequent session.

## Verification

- Flutter static analysis passes.
- All 91 Flutter tests pass.
- Registration, disposal, accepted and stale acknowledgements, state notification, unknown callbacks, and malformed arguments are covered by tests.
- Android debug APK builds successfully.
