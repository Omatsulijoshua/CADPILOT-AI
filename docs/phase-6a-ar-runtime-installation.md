# Phase 6A: AR runtime installation recovery

This increment gives supported Android devices a truthful recovery path when Google Play Services for AR is missing or outdated.

## Included

- Adds a typed Dart result for installed, install requested, user declined, and unavailable outcomes.
- Adds a fail-closed `requestArRuntimeInstall` method-channel operation.
- Uses the official ARCore `requestInstall` API from the Android activity.
- Shows **Install or update AR runtime** only when AR hardware is supported and runtime readiness is false.
- Refreshes capability detection after the result dialog closes.
- Keeps manual placement available after declined or unavailable installation.
- Does not mark the CadPilot native renderer as available.

## Safety boundary

Runtime installation is not renderer implementation. Placement preflight still requires the native CadPilot renderer, AR runtime, plane detection, and camera permission. Web, missing plugins, native errors, and unknown responses fail closed.

## Verification

- `flutter analyze --no-pub` passed with no issues.
- All 115 Flutter tests passed.
- Android debug APK compiled successfully.
- Flutter Web release build succeeded.
- Dedicated tests cover result mapping, method routing, platform failures, and missing native hosts.