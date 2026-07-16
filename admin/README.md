# CadPilot Admin

Phase 8 super-admin dashboard. It signs in through the CadPilot API and reads
only the server-enforced admin overview, user metadata, and project metadata.
It does not expose password hashes, manifests, raw spatial data, or write
operations.

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
