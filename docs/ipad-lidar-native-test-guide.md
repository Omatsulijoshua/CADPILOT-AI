# iPad LiDAR native test guide

CadPilot LiDAR capture requires the native iPad app. The Vercel web app can run
CAD, AI planning, and manual spatial records, but iPad Safari does not expose
ARKit scene-depth / LiDAR point-cloud frames to Flutter web.

## Supported path

Use this path when testing LiDAR:

1. Open the Flutter project on a Mac with Xcode installed:

   ```bash
   cd tablet_app
   open ios/Runner.xcworkspace
   ```

2. In Xcode, select the `Runner` target and set:
   - your Apple development team;
   - a unique bundle identifier if needed;
   - automatic signing for local device testing.

3. Connect the LiDAR-capable iPad by USB or use Xcode wireless debugging.
4. Run the app on the physical iPad. Do not use Safari for LiDAR testing.
5. Open a CadPilot project.
6. Tap `AR / Scan`.
7. Tap `Enable camera + recheck LiDAR`.
8. Grant camera permission.
9. Confirm the readiness card reports:
   - `LiDAR hardware detected` or `iPad LiDAR scan capture is ready`;
   - diagnostic includes `platform=ios` / `ios_arkit`;
   - `cameraPermission=granted`;
   - `capture=lidar`.
10. Tap `Capture advisory depth scan`.

CadPilot captures bounded ARKit depth frames, processes them through the
validated point-cloud pipeline, and saves advisory scan dimensions. These are
not certified manufacturing measurements.

## What the diagnostic means

The spatial panel shows a native diagnostic string when available.

| Diagnostic clue | Meaning | Next action |
| --- | --- | --- |
| `web_or_missing_native_spatial_plugin` | You are on web or a build without the native channel. | Install/run the native iPad app. |
| `cameraPermission=not_determined` | Camera permission has not been requested yet. | Tap `Enable camera + recheck LiDAR`. |
| `cameraPermission=permanently_denied` | iPadOS blocked camera access for CadPilot. | Enable camera in iPad Settings, then reopen the app. |
| `lidar=false` | ARKit is not reporting LiDAR-style scene depth + mesh support. | Confirm the iPad model has LiDAR and the app is a native iOS build. |
| `capture=not_ready` | Hardware may exist, but capture is gated. | Grant camera permission and recheck. |
| `capture=lidar` | CadPilot can request ARKit depth frames. | Tap `Capture advisory depth scan`. |

## If capture still fails

Send these details back into the Codex task:

- iPad model and iPadOS version.
- Whether you installed through Xcode or TestFlight.
- Screenshot of the `AR / Scan` readiness card.
- The full `Diagnostic:` line.
- The exact message after tapping `Capture advisory depth scan`.

Common causes:

- opening the Vercel web app instead of the native app;
- camera permission denied in iPad Settings;
- iPad model without LiDAR;
- ARKit did not deliver a scene-depth frame within the current two-second
  capture window;
- the app was built without the iOS native host code.

## Release/TestFlight path

For TestFlight distribution:

1. In Xcode, archive the `Runner` scheme for a real iOS device.
2. Upload the archive to App Store Connect.
3. Add internal testers in TestFlight.
4. Install the TestFlight build on the LiDAR iPad.
5. Repeat the native test steps above.

The GitHub `Flutter CI` workflow compiles an unsigned iOS debug app on macOS.
That catches Swift/Flutter integration errors, but physical-device LiDAR
validation still requires a real iPad.
