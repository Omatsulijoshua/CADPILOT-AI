# Phase 1 verification

From `tablet_app`: `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, then run on an iPad and an Android tablet at 800dp or wider.

From `server`: `npm ci`, `npx prisma validate`, `npm run lint`, `npm test`, `npm run build`.

Acceptance: sign in or use guest mode; create a project; edit its note; wait for “Saved locally”; terminate and relaunch; reopen the same project and verify the note. At a narrow width, verify the tablet-required message.

Limitations: OAuth/email delivery, live cloud transport, secure production token storage, and sync conflict resolution require deployment work and are not claimed complete. CAD, stylus, LiDAR, and AR belong to later gated phases. Signed physical-device builds require the owner's Apple and Google credentials.
