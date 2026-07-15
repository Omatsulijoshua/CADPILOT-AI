# Phase 6A: Coordinated AR session controller

This increment combines CadPilot's native lifecycle command boundary with the validated native event bridge under one session-scoped controller.

## Included

- Native callback listening is registered before the start command is issued.
- Successful native acknowledgement marks the session controller active.
- Repeated start calls are idempotent while the same session is active.
- Failed or unsupported native startup immediately removes the callback handler.
- Stop targets the active session and always clears active state and callback listening, even when native stop acknowledgement fails.
- Inactive stop and repeated disposal are safe no-ops.

## Safety rule

The controller never reports an active session unless the native host returns an explicit successful start acknowledgement. Listener lifetime cannot outlive controller lifetime.

## Verification

- `flutter analyze --no-pub` passed with no issues.
- All 108 Flutter tests passed.
- Android debug APK built successfully.
- Flutter Web release build succeeded.
- Startup ordering, idempotence, rollback, targeted stop, and disposal are covered by tests.

Native ARCore and ARKit camera-session hosts remain separate platform increments. The iOS target is not compiled in this Windows environment.
