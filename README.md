# CadPilot

<p align="center"><img src="tablet_app/web/icons/Icon-512.png" alt="CadPilot logo" width="160"></p>
<p align="center"><strong>Tablet-first CAD, intelligent design assistance, spatial scanning, and augmented reality.</strong></p>
<p align="center"><a href="https://cadpilot.vercel.app"><strong>Live App</strong></a> | <a href="docs/architecture.md">Architecture</a> | <a href="docs/api.md">API</a> | <a href="docs/cad-file-format.md">File Format</a> | <a href="docs/security.md">Security</a></p>

---

## Project status

CadPilot is an actively developed local-first CAD platform built with Flutter, Dart, C++, NestJS, Prisma, and PostgreSQL. This repository contains a working cross-platform app, deterministic CAD foundations, local persistence, intelligent-command infrastructure, cloud-service foundations, and native AR runtime-readiness integration.

> **Important:** ARCore availability detection and spatial-session state are implemented. Full native AR rendering, LiDAR reconstruction, and real-time collaboration remain in development. The OpenAI Responses API integration is implemented as a hardened foundation; production evaluation, quotas, and billing controls remain. This README separates implemented foundations from planned capabilities.

## Contents

- [Overview](#overview)
- [Principles](#principles)
- [Feature status](#feature-status)
- [Architecture](#architecture)
- [CAD pipeline](#cad-pipeline)
- [Intelligent commands](#intelligent-commands)
- [Spatial scanning and AR](#spatial-scanning-and-ar)
- [Persistence and sync](#persistence-and-sync)
- [Repository map](#repository-map)
- [Technology stack](#technology-stack)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Running the project](#running-the-project)
- [Testing](#testing)
- [Backend and data model](#backend-and-data-model)
- [Security and privacy](#security-and-privacy)
- [Deployment](#deployment)
- [Roadmap](#roadmap)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)
- [Contributing](#contributing)

## Overview

CadPilot brings structured 2D and 3D design workflows to tablets without reducing CAD to a drawing toy. Users can manage projects, construct sketches, apply dimensions and constraints, build ordered parametric features, persist work locally, and prepare models for spatial placement.

The product connects four workflows:

1. **Design** — precise sketches and parametric features.
2. **Understand** — history, dimensions, constraints, materials, and properties.
3. **Assist** — natural language converted into structured, reviewable operations.
4. **Place** — digital models connected to physical space on supported devices.

Open the browser build at **[cadpilot.vercel.app](https://cadpilot.vercel.app)**. The web app supports general workflows; LiDAR, ARCore, ARKit, and native sensors require compatible mobile hardware.

## Principles

- **Tablet first:** touch targets, gestures, responsive layouts, and progressive disclosure.
- **Local first:** device persistence provides continuity; cloud sync is layered on top.
- **Deterministic geometry:** identical documents and operations should rebuild identically.
- **Review before mutation:** intelligent plans are validated and previewed before application.
- **Capability-aware spatial tools:** hardware, permission, runtime, and session states are separate.
- **Versioned documents:** the documented format supports deliberate migration and recovery.
- **Honest delivery:** visible UI does not imply every native subsystem is production complete.

## Feature status

| Area | Status | Current behavior |
|---|---|---|
| Flutter shell | Implemented | Responsive navigation, projects, editor, settings, branded web shell |
| Authentication | Implemented foundation | Account registration, sign-in, RSA-OAEP/AES-GCM secure token storage, refresh-token rotation, revocable logout, guest mode, and offline-tolerant session restoration with a visible reconnect-and-verify state |
| Project management | Implemented | Create, open, persist, back up, browse cloud projects, restore, and manage projects |
| Durable autosave | Implemented | Lifecycle-aware local persistence |
| Sketching | Implemented | Entities, selection, dimensions, constraints, tools, viewport |
| Parametric history | Implemented | Ordered features, rebuild behavior, and history UI |
| CAD kernel boundary | Foundation | Stable Dart/native ABI under `cad_core/` |
| Intelligent commands | Foundation | Plan, validation, preview, deterministic application |
| Cloud API | Foundation | Authenticated backup and restore, remote revisions, conflicts, plans, spatial sessions, and audits |
| Database | Foundation | Prisma schema and PostgreSQL migrations |
| Spatial controller | Implemented | Capability, permission, readiness, lifecycle, recovery |
| ARCore availability | Implemented | Official asynchronous Android detection |
| Native AR renderer | In progress | Planes, anchors, occlusion, rendering, placement UX remain |
| LiDAR reconstruction | Planned | Processing, meshing, cleanup, export remain |
| Collaboration | Planned | Presence and robust multi-user conflicts remain |
| Production AI | Implemented foundation | OpenAI Responses API, strict command schema, bounded timeout, safe failures, review-before-apply, and token metering; production evals, quotas, and billing remain |

## Architecture

```mermaid
flowchart TB
    USER["User"] --> UI["Flutter tablet / web UI"]
    UI --> APP["Application services"]
    APP --> DOC["Versioned CAD document"]
    APP --> LOCAL["Local project repository"]
    APP --> AI["Intelligent command planner"]
    APP --> SPATIAL["Spatial session controller"]
    DOC --> CORE["Deterministic CAD core / C++ ABI"]
    LOCAL --> DISK[("Device storage")]
    AI --> VALIDATE["Schema and operation validator"]
    SPATIAL --> CHANNEL["Flutter method channel"]
    CHANNEL --> NATIVE["Android / iOS runtime"]
    APP -. "when online" .-> API["NestJS REST API"]
    API --> PRISMA["Prisma ORM"]
    PRISMA --> DB[("PostgreSQL")]
    API --> STORE["Object-storage boundary"]
    API --> PROVIDER["AI-provider boundary"]
```

| Boundary | Owns | Does not own |
|---|---|---|
| Flutter UI | Input, layout, accessibility, visualization | Geometry rules |
| Application layer | Use cases, commands, save/sync orchestration | Native camera calls |
| CAD core | Entities, constraints, features, rebuild invariants | UI/network state |
| Local repository | Persistence and offline continuity | Remote authorization |
| Backend | Identity, remote projects, versions, sync, audit | Render loop |
| Native runtime | Device, permission, tracking/session lifecycle | Project logic |

See [docs/architecture.md](docs/architecture.md) for the deeper design.

## CAD pipeline

```mermaid
flowchart LR
    INPUT["Touch, pointer, keyboard, or AI proposal"] --> COMMAND["Typed editor command"]
    COMMAND --> CHECK{"Valid?"}
    CHECK -- "No" --> ERROR["Actionable error"]
    CHECK -- "Yes" --> HISTORY["History update"]
    HISTORY --> MODEL["Document mutation"]
    MODEL --> SOLVER["Constraint and feature rebuild"]
    SOLVER --> GEO["Derived geometry"]
    GEO --> VIEW["2D / 3D viewport"]
    MODEL --> SAVE["Durable autosave"]
```

- Sketch entities represent points, lines, arcs, circles, and profiles.
- Constraints encode geometric relationships rather than screen coordinates.
- Dimensions communicate and drive design intent.
- Features form an ordered history for deterministic rebuilds.
- Commands validate mutations and support future undo/redo and collaboration.
- Format versions make migration deliberate and recoverable.

The native boundary stays narrow: Flutter exchanges stable serialized operations and results instead of native implementation details.

## Intelligent commands

Natural language cannot directly mutate geometry. It becomes a reviewable proposal.

```mermaid
sequenceDiagram
    actor User
    participant UI as CadPilot UI
    participant Planner as Planner
    participant Validator as Validator
    participant Core as CAD core
    participant Store as Version store
    User->>UI: "Extrude this profile by 40 mm"
    UI->>Planner: Request + selection + context
    Planner-->>UI: Structured operation plan
    UI->>Validator: Validate schema, units, references, limits
    Validator-->>UI: Preview or errors
    UI-->>User: Display proposal
    User->>UI: Confirm
    UI->>Core: Apply validated operations
    Core-->>UI: Rebuilt document
    UI->>Store: Save metadata and version
```

This improves safety, reproducibility, testing, and provider independence. The planning boundary exists today; fully configured production AI is future work.

## Spatial scanning and AR

```mermaid
flowchart TD
    START["Open spatial workspace"] --> PROBE["Probe platform/device"]
    PROBE --> SUPPORT{"Hardware supported?"}
    SUPPORT -- "No" --> FALLBACK["Explain limitation; retain CAD tools"]
    SUPPORT -- "Yes" --> PERM{"Permission granted?"}
    PERM -- "No" --> REQUEST["Request permission"]
    REQUEST --> PERM
    PERM -- "Yes" --> RUNTIME["Check native runtime"]
    RUNTIME --> READY{"Runtime ready?"}
    READY -- "No" --> HELP["Install/update guidance"]
    READY -- "Yes" --> SESSION["Start tracked session"]
```

```mermaid
stateDiagram-v2
    [*] --> Unknown
    Unknown --> Probing
    Probing --> Unsupported
    Probing --> PermissionRequired
    Probing --> RuntimeUnavailable
    Probing --> Ready
    PermissionRequired --> Probing: permission result
    RuntimeUnavailable --> Probing: retry
    Ready --> Starting
    Starting --> Running
    Starting --> Error
    Running --> Paused
    Paused --> Running
    Running --> Stopping
    Stopping --> Ready
    Error --> Probing: recover
```

Android uses official ARCore detection and resolves transient asynchronous states without blocking Flutter. Web and unsupported targets return a graceful unsupported state. Native rendering and LiDAR reconstruction are not claimed as complete.

## Persistence and sync

```mermaid
flowchart LR
    EDIT["Editor mutation"] --> MEMORY["In-memory document"]
    MEMORY --> SAVE["Durable local autosave"]
    SAVE --> LOCAL[("Local project store")]
    LOCAL --> QUEUE["Pending sync"]
    QUEUE --> ONLINE{"Online and authenticated?"}
    ONLINE -- "No" --> RETAIN["Retain; retry later"]
    ONLINE -- "Yes" --> API["Version / sync API"]
    API --> REMOTE[("Cloud persistence")]
    API --> RESULT{"Accepted or conflict?"}
    RESULT -- "Accepted" --> CLEAN["Mark synchronized"]
    RESULT -- "Conflict" --> RESOLVE["Preserve versions; resolve explicitly"]
```

Conflicts must never silently discard project data. See [docs/cad-file-format.md](docs/cad-file-format.md).

## Repository map

```text
CADPILOT-AI/
|-- tablet_app/          Flutter client
|   |-- lib/             Domain, editor, persistence, spatial code
|   |-- test/            Unit and widget tests
|   |-- android/         Android host and ARCore bridge
|   |-- ios/             iOS host
|   `-- web/             Manifest, favicon, icons, bootstrap
|-- server/              NestJS and Prisma
|   |-- src/             API modules
|   |-- prisma/          Schema and migrations
|   `-- test/            Server tests
|-- cad_core/            Native CAD core / ABI
|-- docs/                Architecture, contracts, verification
|-- docker-compose.yml   Development services
`-- vercel.json          Web deployment
```

## Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| Client | Flutter / Dart | Cross-platform UI and logic |
| Geometry | Dart + C++ ABI | Documents and CAD operations |
| Android spatial | Kotlin + ARCore | Availability and native runtime |
| iOS target | Apple native host + ARKit | Future Apple spatial integration |
| Backend | NestJS / TypeScript | REST API and cloud use cases |
| ORM/database | Prisma / PostgreSQL | Typed persistence and migrations |
| Local services | Docker Compose | Reproducible infrastructure |
| Hosting | Vercel | Flutter web and SPA routing |

## Getting started

Prerequisites: Flutter, Git, Node.js/npm, Docker Desktop, Android Studio for Android, and Xcode on macOS for iOS.

```powershell
flutter doctor -v
git clone https://github.com/Omatsulijoshua/CADPILOT-AI.git
cd CADPILOT-AI
cd tablet_app
flutter pub get
cd ..\server
npm install
```

Start PostgreSQL and prepare Prisma:

```powershell
cd ..
docker compose up -d
cd server
npx prisma generate
npx prisma migrate dev
```

## Configuration

Typical development `server/.env`:

```dotenv
DATABASE_URL="postgresql://cadpilot:cadpilot@localhost:5432/cadpilot?schema=public"
JWT_ACCESS_SECRET="replace-with-a-long-random-access-secret"
JWT_REFRESH_SECRET="replace-with-a-different-long-random-refresh-secret"
PORT=3000
OPENAI_API_KEY=""
OPENAI_CAD_MODEL="gpt-5.6-luna"
OPENAI_TIMEOUT_MS=30000
```

Match credentials to [docker-compose.yml](docker-compose.yml). Never commit secrets.

Client endpoint:

```powershell
flutter run --dart-define=CADPILOT_API_URL=http://localhost:3000
```

Use `http://10.0.2.2:3000` from the standard Android emulator. Never put server secrets in Flutter definitions; client bundles are inspectable.

## Running the project

Backend (**17 passing tests**, NestJS 11/Express 5, and zero production audit findings at this checkpoint):

```powershell
cd server
npm run start:dev
```

Web:

```powershell
cd tablet_app
flutter run -d chrome
```

Android:

```powershell
cd tablet_app
flutter devices
flutter run -d <device-id>
```

Use compatible physical hardware for ARCore. On macOS/iOS, run `open ios/Runner.xcworkspace`, configure signing and permissions, then use `flutter run`. LiDAR requires supported Apple hardware.

## Testing

At the latest verified point, the Flutter suite contains **139 passing tests**. Run it locally because the count evolves.

```powershell
cd tablet_app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk
```

Backend (**17 passing tests**, NestJS 11/Express 5, and zero production audit findings at this checkpoint):

```powershell
cd server
npm run lint
npm test
npm run build
npx prisma validate
npm audit --omit=dev
```

```mermaid
flowchart LR
    CHANGE["Change"] --> FORMAT["Format/analyze"]
    FORMAT --> UNIT["Unit tests"]
    UNIT --> WIDGET["Widget tests"]
    WIDGET --> WEB["Web build"]
    WIDGET --> ANDROID["Android build"]
    UNIT --> LINT["Server TypeScript lint"]
    LINT --> SERVER["Server tests/build"]
    UNIT --> ABI["CAD ABI checks"]
    ANDROID --> DEVICE["Physical-device test"]
```

AR changes should cover unsupported platforms, denied permission, missing runtime, transient availability, lifecycle transitions, and recovery.

## Backend and data model

The server covers authentication, users, projects, versions, sync, AI plans, spatial sessions, and audits. Exact routes and schemas are in [docs/api.md](docs/api.md).

```mermaid
erDiagram
    USER ||--o{ PROJECT : owns
    USER ||--o{ AUTH_SESSION : authenticates
    PROJECT ||--o{ PROJECT_VERSION : contains
    PROJECT ||--o{ SYNC_EVENT : synchronizes
    PROJECT ||--o{ AI_PLAN : requests
    PROJECT ||--o{ SPATIAL_SESSION : captures
    USER ||--o{ AUDIT_EVENT : produces
    PROJECT_VERSION ||--o{ AUDIT_EVENT : references
    USER {
      string id
      string email
      datetime createdAt
    }
    PROJECT {
      string id
      string ownerId
      string name
    }
    PROJECT_VERSION {
      string id
      int sequence
      string documentRef
    }
```

This is conceptual. [server/prisma/schema.prisma](server/prisma/schema.prisma) is authoritative.

## Security and privacy

- Treat client input and AI operations as untrusted.
- Authorize every project/resource operation.
- Keep secrets server-side.
- Request camera/spatial permissions only when required.
- Keep frames and scans local unless upload is intentional.
- Exclude tokens and private documents from logs.
- Rotate refresh tokens on signed-in startup and revoke the active refresh token on logout.
- Clear sessions after confirmed invalid credentials while preserving local continuity during transient outages.
- Preserve recovery during file migration.
- Validate AI schemas, units, references, and limits.
- Audit actions without copying private content.

Read [docs/security.md](docs/security.md) before changing auth, storage, sync, AI, or spatial code.

## Deployment

The public app is **[cadpilot.vercel.app](https://cadpilot.vercel.app)**. [the web deployment guide](docs/cadpilot-branding-and-web-deployment.md) configures build output and SPA routing.

```mermaid
flowchart LR
    PUSH["Push to GitHub"] --> VERCEL["Vercel build"]
    VERCEL --> GET["Resolve packages"]
    GET --> BUILD["flutter build web --release"]
    BUILD --> STATIC["tablet_app/build/web"]
    STATIC --> CDN["Vercel CDN"]
    CDN --> LIVE["cadpilot.vercel.app"]
```

Browser title, manifest, favicon, and icons use **CadPilot** under [tablet_app/web](tablet_app/web). The backend separately needs Node.js, managed PostgreSQL, secrets, migrations, HTTPS, CORS, backups, health checks, and monitoring.

## Roadmap

```mermaid
timeline
    title CadPilot delivery direction
    Foundation : Flutter shell, projects, autosave
               : NestJS and Prisma foundation
    CAD : Sketches, constraints, dimensions
        : Parametric history and CAD ABI
    Intelligence : Structured plans and validation
                 : Preview and provider integration
    Spatial : Capability, permission, ARCore readiness
            : Planes, anchors, rendering, LiDAR
    Maturity : Conflict resolution and collaboration
             : Observability and hardening
```

Near-term priorities are native AR sessions, rendering CAD at tracked anchors, device verification, sync conflicts, and continued deterministic geometry.

## Known limitations

- Web cannot provide complete native LiDAR/AR.
- AR readiness exists, but production placement/rendering is incomplete.
- LiDAR capture-to-mesh reconstruction is not production-ready.
- The CAD core is not yet a mature manufacturing kernel.
- Intelligent commands are not a fully configured production AI service.
- Robust multi-device conflicts and collaboration remain ongoing.
- Backend production infrastructure is environment-specific.
- iOS spatial parity needs Apple-device completion and testing.

## Troubleshooting

### Docker says WSL is not installed

Run PowerShell as Administrator:

```powershell
wsl --install
```

Restart Windows, initialize the Linux distribution, restart Docker, and ensure virtualization/WSL 2 are enabled.

```powershell
wsl --status
wsl --list --verbose
docker version
docker compose version
```

### Flutter cannot find a device

```powershell
flutter doctor -v
flutter devices
```

Enable USB debugging, accept authorization, and install Android SDK licenses.

### Android cannot reach the API

Use `10.0.2.2` instead of `localhost` in the emulator. Physical devices need a reachable LAN address or deliberate tunnel.

### AR is unavailable

Confirm compatible hardware, updated Google Play Services for AR on Android, camera permission, a native build, and that no other app owns the camera.

### Prisma cannot connect

```powershell
docker compose ps
cd server
npx prisma validate
npx prisma migrate status
```

Check `DATABASE_URL`, container health, ports, and migrations.

## Documentation

| Document | Purpose |
|---|---|
| [Architecture](docs/architecture.md) | Boundaries and technical design |
| [API contract](docs/api.md) | Routes, schemas, errors, sync semantics |
| [File format](docs/cad-file-format.md) | Versioned document representation |
| [Security](docs/security.md) | Threats, permissions, secrets, trust boundaries |
| [Session refresh and revocation](docs/session-refresh-and-revocation-increment.md) | Client token rotation, offline recovery, invalidation, and logout behavior |
| [Offline cloud verification](docs/offline-cloud-session-verification-increment.md) | Visible offline state, retry flow, and stale-token cloud guards |
| [Secure storage v10 migration](docs/secure-storage-v10-migration.md) | Cipher modernization, automatic token migration, Web/Wasm compatibility |
| [OpenAI provider hardening](docs/openai-provider-hardening-increment.md) | Responses API timeout, validation, privacy, metering, and safe failures |
| [Backend TypeScript lint gate](docs/backend-typescript-lint-gate.md) | ESLint activation, verification workflow, and dependency-audit baseline |
| [NestJS 11 security migration](docs/nestjs-11-security-migration.md) | Express 5 compatibility, Node 20 floor, HTTP regression tests, zero-audit verification |
| [Phase notes](docs/) | Decisions and verification evidence |
| [Flutter notes](tablet_app/README.md) | Client-specific guidance |

## Contributing

1. Create a focused branch.
2. Read relevant architecture/security docs.
3. Keep geometry deterministic and native code behind interfaces.
4. Add proportionate tests.
5. Run analysis, tests, and affected builds.
6. Update docs for changed behavior or contracts.
7. Open a PR describing outcome and verification.

Use concise imperative commits. Issue reports should include platform, OS, Flutter version, device model for spatial issues, reproduction steps, expected/actual behavior, and sanitized logs. Never attach credentials or private designs.

---

<p align="center"><strong>CadPilot</strong><br>Design precisely. Understand spatially. Build confidently.</p>
