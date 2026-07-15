# Phase 6A: AR session command boundary

This increment connects CadPilot's validated placement readiness model to explicit native AR session start and stop requests.

## Included

- `startArSession` requests require a non-empty session ID and successful AR placement preflight.
- Start payloads request horizontal plane detection and fixed 1:1 scale.
- `stopArSession` requests target one explicit session ID.
- Web, missing native hosts, platform errors, null responses, and false native acknowledgements fail closed.
- Blocked preflight never invokes native code.

## Scope boundary

This is the Flutter-to-native lifecycle command contract. Android ARCore and iOS ARKit camera-session hosts remain separate native increments. No user-facing control claims that an unsupported native session started.

## Verification

- `flutter analyze --no-pub` passed with no issues.
- All 104 Flutter tests passed.
- Android debug APK built successfully.
- Flutter Web release build succeeded.
- Start gating, payload shape, targeted stop, invalid IDs, and missing-host behavior are covered by tests.

The iOS native target is not compiled in this Windows environment.
