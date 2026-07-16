# CadPilot Admin

Phase 8 super-admin dashboard. It signs in through the CadPilot API and reads
only the server-enforced admin overview, user metadata, project metadata, and
recent AI/sync audit metadata.
It does not expose password hashes, manifests, raw spatial data, or write
operations. The access token stays only in browser memory. A 401 response
clears the local dashboard state and requires a new sign-in; a refresh action
reloads all three read-only data sets together.

The audit feed intentionally excludes prompts, sync payloads, project manifests,
raw spatial data, and credentials.

## Run

```powershell
cd admin
npm install
$env:NEXT_PUBLIC_CADPILOT_API_URL='http://localhost:3000/v1'
npm run dev
```

Set `CADPILOT_SUPER_ADMIN_EMAILS` on the Nest API to a comma-separated list of
authorized email addresses. The API rejects every other account, even if it
loads this web UI.

For a separately hosted dashboard, add its exact origin to
`CORS_ALLOWED_ORIGINS` on the API and set `NEXT_PUBLIC_CADPILOT_API_URL` to the
API's `/v1` URL at build time.
