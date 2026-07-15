# Phase 6A: Android ARCore availability detection

This increment replaces the Android package-presence heuristic with Google's official ARCore availability API.

## Included

- Pins the optional Android dependency `com.google.ar:core:1.54.0`.
- Uses `ArCoreApk.getInstance().checkAvailability(activity).isSupported` for device support.
- Declares `com.google.ar.core` as `optional` in the Android application manifest.
- Keeps camera and gyroscope requirements in the capability decision.
- Does not make ARCore mandatory, preserving CadPilot manual CAD workflows on unsupported devices.
- CadPilot native renderer availability remains a separate false capability until the renderer host is implemented.

## Why

Having the Google Play Services for AR package installed does not by itself prove that the current device supports ARCore. The availability API accounts for Google's device compatibility result.

## Verification

- Android debug APK compiled successfully with ARCore 1.54.0.
- `flutter analyze --no-pub` passed with no issues.
- All 110 Flutter tests passed.

The pinned version was selected from Google's official Maven metadata on 2026-07-15.
