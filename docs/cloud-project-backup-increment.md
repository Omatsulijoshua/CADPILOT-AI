# Cloud project backup increment

This increment connects CadPilot's local-first project documents to the authenticated cloud sync endpoint without conflating local document revisions with remote synchronization revisions.

## Included

- Adds persisted `lastSyncedRevision` metadata while retaining independent local revision history.
- Adds a non-mutating `markSynced` transition that never creates a fake local edit.
- Derives a deterministic UUID v5 from the project, local revision, and remote base so retries are idempotent while later edits receive a different mutation ID.
- Sends remote base revision zero for a project's first cloud backup.
- Atomically creates the first remote project with the same client-generated UUID.
- Enforces project ownership before returning idempotent mutation results.
- Rejects stale remote bases with a revision conflict.
- Validates the server's applied revision before showing a project as synced.
- Adds a signed-in **Back up now** action with pending, busy, success, and error states.
- Keeps guest and missing-token workflows local without falsely reporting cloud success.

## Revision model

`CadProject.revision` tracks local document edits. `lastSyncedRevision` tracks the last cloud revision acknowledged by the server. Editing a synced project increments only the local revision, marks it pending, and retains the remote base for the next compare-and-swap sync.

## Security and idempotency

Mutation IDs are globally unique, but the server still verifies that an existing mutation belongs to both the requested project and authenticated owner. Cross-owner mutation lookups return not found rather than leaking sync metadata.

## Verification

- Flutter analysis passes with no issues.
- All 120 Flutter tests pass.
- All 7 NestJS tests pass.
- NestJS production compilation succeeds.
- Android debug APK compiled successfully.
- Flutter Web release build succeeded.