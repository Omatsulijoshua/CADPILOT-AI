# Cloud project restore increment

This increment adds explicit conflict recovery by downloading and restoring the latest authenticated cloud project.

## Included

- Adds ownership-scoped `GET /v1/projects/:id` for active projects.
- Returns not found for missing, inactive, or foreign projects without disclosing ownership.
- Adds client download with authorization, HTTP error handling, envelope validation, positive remote revision validation, and project-ID matching.
- Marks a downloaded document synced only after the entire response validates.
- Adds **Restore cloud copy** when local edits exist after a previous backup.
- Requires explicit confirmation that unsynced local edits will be replaced.
- Cancels pending note autosave before applying the downloaded document.
- Refreshes the active note editor and local project repository after restore.
- Keeps malformed, missing, and mismatched cloud data from replacing local work.

## Safety boundary

Restore is intentionally one-sided conflict resolution: the user may choose the latest server copy and discard current unsynced local edits. Automatic field-level or CAD-operation merging remains future work. CadPilot never performs this destructive replacement without confirmation.

## Verification

- Flutter analysis passes with no issues.
- All 123 Flutter tests pass.
- All 9 NestJS tests pass.
- NestJS production compilation succeeds.
- Android and Flutter Web release builds are verified after final client changes.