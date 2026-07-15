# Phase 6A: Persistent AR screenshots

This increment persists validated AR screenshot metadata with the CadPilot project so captured placement evidence survives project save, reload, and synchronization.

## Included

- JSON serialization for screenshot path, pixel dimensions, UTC capture time, session ID, and anchor ID.
- A project-level `arScreenshots` collection.
- Project copy operations retain screenshots unless an updated collection is supplied.
- Older project files without screenshot metadata load with an empty collection.
- Capture metadata remains linked to the native session and anchor identities validated by the screenshot boundary.

## Verification

- `flutter analyze --no-pub` passes with no issues.
- All 100 Flutter tests pass.
- Android debug APK builds successfully.
- Project round-trip and legacy project compatibility are covered by regression tests.

The native camera renderer remains a separate platform increment; this change does not present unsupported capture as successful. The iOS target is not compiled in this Windows environment.
