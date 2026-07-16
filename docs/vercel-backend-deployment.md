# Vercel backend deployment

The Nest API has a Vercel serverless adapter in `server/api/index.ts`. It keeps
the Nest application warm between invocations when Vercel reuses a function
instance, while retaining the same `/v1` routes, validation, security headers,
and CORS policy as the container deployment.

## Required Vercel environment variables

Set these in the **cadpilot-api** Vercel project before treating the API as
ready:

- `DATABASE_URL`: production PostgreSQL connection string.
- `JWT_ACCESS_SECRET`: unique 32+ character secret.
- `JWT_REFRESH_SECRET`: different unique 32+ character secret.
- `CORS_ALLOWED_ORIGINS`: comma-separated HTTPS CadPilot web and admin origins.
- `OPENAI_API_KEY`: optional; required only for server-generated AI commands.
- `CADPILOT_SUPER_ADMIN_EMAILS`: optional; required to activate the read-only
  admin APIs.

The server fails closed in production when its JWT secrets or CORS allowlist
are absent. Configure a managed PostgreSQL provider first; Vercel does not
provide PostgreSQL automatically for this repository.

## Deploy

```powershell
cd server
vercel --prod --scope joshua-omatsuli-projects
```

After environment setup, verify `GET /v1/health` and `/v1/health/ready`. The
second route requires the database to be reachable.
