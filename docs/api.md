# API and milestones

Phase 1 routes: `POST /v1/auth/register`, `/login`, `/refresh`, `/logout`; `GET /v1/users/me`; CRUD `/v1/projects`; `POST /v1/projects/:id/sync`; `GET /v1/projects/:id/changes`; and `GET /health`. Phase 4 adds authenticated `POST /v1/ai/commands`, which returns a schema-constrained CAD command and token usage; the OpenAI API key remains server-only.

Milestones: Phase 1 foundation; Phase 2 sketching; Phase 3 basic 3D; Phase 4 AI commands; Phase 5 sketch-to-CAD; Phase 6 advanced modeling; Phases 6A–6E AR/depth/scan-to-CAD/inspection; Phase 7 cloud and billing; Phase 8 admin; Phase 9 hardening. Each phase is gated by the acceptance criteria in the brief.
