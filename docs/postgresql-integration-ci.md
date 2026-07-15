# PostgreSQL integration CI

CadPilot runs one real PostgreSQL-backed API integration test in GitHub Actions as the `PostgreSQL integration API` job in `.github/workflows/backend-ci.yml`. It complements the fast unit and HTTP compatibility suites without allowing a test to contact development or production infrastructure.

## Isolation model

```mermaid
flowchart LR
    Runner["Clean Ubuntu runner"] --> Service["PostgreSQL 16 disposable service"]
    Service --> Schema["prisma db push"]
    Schema --> Api["Ephemeral NestJS HTTP app"]
    Api --> Flow["Register → create → sync → replay → list"]
    Flow --> Cleanup["Delete cadpilot.test records"]
    Cleanup --> End["Runner and database destroyed"]
```

The workflow supplies only local, test-only values:

- database: `cadpilot_test` in a PostgreSQL service container;
- user/password: `cadpilot_test`;
- JWT secrets: fixed CI-only values with no production use;
- test accounts: randomly named addresses ending in `@cadpilot.test`.

The job is read-only with respect to GitHub and has no Vercel, OpenAI, cloud database, signing, or production secret access. GitHub destroys the service container at job completion.

## Schema lifecycle

CadPilot has no committed Prisma migrations at this checkpoint. The isolated job therefore runs `prisma db push --accept-data-loss` only against its newly created disposable database. This is safe for the test service and must never be copied to a deployed database. Production deployment should introduce reviewed Prisma migrations before it is opened to real traffic.

Prisma Client generation is explicit before schema push, which keeps the job deterministic even when package-manager lifecycle behavior changes.

## Exercised API flow

The integration test starts a real Nest HTTP application, connects the actual `PrismaService`, and verifies that one user can:

1. register and receive an access token;
2. create a project;
3. sync a project mutation at revision 1;
4. replay the same mutation idempotently without a second revision increase;
5. list the persisted project at revision 2 with its synced name.

The test cleans only records owned by test-domain accounts. Its suite is skipped during ordinary `npm test` runs; GitHub enables it with `RUN_POSTGRES_INTEGRATION=true` and calls `npm run test:postgres`.

## Local use

A local PostgreSQL instance is optional. To run this test manually, create an empty disposable database and set these environment variables before running the command:

```powershell
$env:DATABASE_URL='postgresql://cadpilot_test:cadpilot_test@localhost:5432/cadpilot_test?schema=public'
$env:JWT_ACCESS_SECRET='local-test-access-secret'
$env:JWT_REFRESH_SECRET='local-test-refresh-secret'
$env:RUN_POSTGRES_INTEGRATION='true'
npx prisma generate
npx prisma db push --accept-data-loss
npm run test:postgres
```

Never point this command at a database containing user data: `--accept-data-loss` exists solely for disposable test schemas.

## Limitations and next work

This first integration flow verifies persistence, transactions, JWT guarding, revision update, and mutation idempotency. It does not yet cover concurrency races, refresh-token rotation against PostgreSQL, project ownership isolation between two persisted users, backup restore, operational migrations, replicas, backups, or performance/load behavior.

The service-container pattern is based on [GitHub’s PostgreSQL Actions guidance](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers). Prisma documents that [`db push`](https://www.prisma.io/docs/cli/db/push) applies a schema without migration history, which is why its use here is explicitly restricted to the disposable test database.
