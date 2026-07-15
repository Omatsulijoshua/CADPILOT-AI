# Cloud project browser increment

This increment replaces the inert dashboard Cloud destination with an authenticated browser for remote CadPilot projects.

## Included

- Converts the dashboard to stateful local/cloud navigation.
- Removes the non-functional Favorites destination rather than presenting a placeholder.
- Adds validated lightweight cloud project summaries with ID, name, remote revision, and update time.
- Adds loading, empty, retry, error, refresh, and download-in-progress states.
- Requires a signed-in session and secure access token before listing projects.
- Downloads and validates a selected manifest before adding it to local storage.
- Opens a successfully imported project directly in the editor.
- Replaces an existing local copy only when it has no pending local edits.
- Directs projects with pending edits to the explicit Restore cloud copy workflow instead of silently overwriting them.
- Keeps malformed list responses from rendering untrusted project metadata.

## Safety boundary

Cloud browsing is read-only until the user selects **Download & open**. Import never overwrites a pending local document. Conflict resolution remains explicit inside the local project workspace.

## Verification

- Flutter analysis passes with no issues.
- All 125 Flutter tests pass.
- Cloud list authentication, decoding, date normalization, and malformed-response behavior have dedicated tests.
- Android and Flutter Web builds are verified after the finalized UI change.