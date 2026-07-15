# Phase 6A: Asynchronous ARCore availability

This increment prevents transient ARCore compatibility checks from being reported as permanent lack of device support.

## Included

- Android `getCapabilities` now uses `ArCoreApk.checkAvailabilityAsync`.
- Camera and gyroscope hardware checks are combined with the completed asynchronous compatibility result.
- The Flutter method-channel result is returned on Android's UI thread.
- Capability decoding continues to await the native method result, so the spatial panel receives one resolved snapshot.
- Native renderer availability remains separate and false until the CadPilot renderer is implemented.

## Verification

- The Android APK compiled successfully against the exact ARCore 1.54.0 callback signature.
- `flutter analyze --no-pub` passed with no issues.
- All 110 Flutter tests passed.

This removes the `UNKNOWN_CHECKING` false-negative window inherent in the synchronous availability probe.
