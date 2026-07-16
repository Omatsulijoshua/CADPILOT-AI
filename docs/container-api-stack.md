# Container API stack

CadPilot's root Compose file starts PostgreSQL and Redis by default. The API
container is an opt-in `api` profile so local CAD work does not require a
running backend.

## Prepare secrets

Copy `.env.example` to `.env` and replace both JWT placeholders with different
random values of at least 32 characters. Set `OPENAI_API_KEY` only if you want
server-generated AI plans. Do not commit `.env`.

For web access, set `CORS_ALLOWED_ORIGINS=https://cadpilot.vercel.app`. Add
`CADPILOT_SUPER_ADMIN_EMAILS` only for authorized operators of the separate
admin console.

## Start the stack

```powershell
docker compose --profile api up --build
```

The API waits for healthy PostgreSQL and Redis containers. It binds to
`http://localhost:3000` by default, and the client API prefix is `/v1`.

Apply the Prisma schema deliberately after the first startup:

```powershell
docker compose --profile api exec api npx prisma db push --skip-generate
```

`db push` is appropriate only for this current migration-free development
schema. A production deployment must use reviewed, versioned Prisma migrations
instead of automatic schema changes.

## Safety boundary

The container entrypoint refuses to start without `DATABASE_URL`,
`JWT_ACCESS_SECRET`, and `JWT_REFRESH_SECRET`. It does not print secrets,
automatically expose PostgreSQL or Redis beyond the configured local ports, or
run destructive database commands.

## Verification status

GitHub Actions builds the API image, validates the Compose profile, and runs
the entrypoint configuration guard for every container-related change. Full
local startup still requires a working Docker Desktop/WSL installation, which
is currently unavailable on this machine. Run the commands above after Docker
is repaired, then check `http://localhost:3000/health` and authenticate through
the tablet or admin application.
