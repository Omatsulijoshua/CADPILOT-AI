# Phase 1 architecture

CadPilot uses a local-first Flutter client, a replaceable native C++ CAD engine boundary, and a NestJS service backed by PostgreSQL/Prisma and Redis. The tablet remains useful offline; cloud sync exchanges versioned manifests and operations rather than mutable engine memory.

## Decisions

- **Tablet UI:** Flutter, feature folders, Riverpod state, landscape-first navigation, and a minimum 720dp workspace gate.
- **Local data:** repository interfaces with a versioned JSON envelope in Phase 1. Writes are serialized and autosaved. The same interface will move to atomic `.cadpilot` ZIP archives.
- **Geometry:** OpenCascade is the initial B-rep kernel for parametric features and STEP interoperability. It is isolated behind a C++20 engine interface.
- **Rendering:** a renderer abstraction with Metal/Vulkan/OpenGL platform adapters exposes a GPU texture to Flutter. A Flutter overlay handles low-latency 2D stylus feedback.
- **Bridge:** Dart FFI calls a narrow C ABI with opaque session handles and versioned command/result DTOs. Geometry stays native; UI receives stable IDs and metadata. Long work executes off the UI isolate.
- **Backend:** modular NestJS, Prisma/PostgreSQL durability, Redis jobs/rate limits, S3-compatible version assets, REST plus later WebSockets.
- **Sync:** idempotent device mutations contain a UUID, base revision, timestamp, and content hash. An outbox queues changes offline.

## Major risks

| Risk | Mitigation |
|---|---|
| OpenCascade mobile size/builds | Pin releases, build each ABI in CI, strip symbols, ship a minimal feature set. |
| Cross-platform GPU integration | Keep platform adapters and test real iPad/Android hardware early. |
| Topological naming | Persist feature IDs and geometric matching, never transient kernel indices. |
| Offline conflicts/large files | Immutable revisions, hashes, chunked assets, resumable outbox, explicit conflict UI. |
| Stylus latency | Coalesced/predicted events, lightweight overlay, physical-device frame budgets. |
| Spatial accuracy/privacy | Capability gates, calibration metadata, local/geometry-only scans, advisory labels. |
| Credential theft | Short access tokens, rotated hashed refresh tokens, platform secure storage. |

LiDAR and AR remain Phases 6A–6E after stable CAD. Their data ownership is anticipated but no unfinished spatial UI is presented as complete.
