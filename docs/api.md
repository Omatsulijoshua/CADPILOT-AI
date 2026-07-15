# API and milestones

Phase 1 routes: `POST /v1/auth/register`, `/login`, `/refresh`, `/logout`; `GET /v1/users/me`; CRUD `/v1/projects`; `POST /v1/projects/:id/sync`; `GET /v1/projects/:id/changes`; and `GET /health`. Phase 4 adds authenticated `POST /v1/ai/commands`, which returns a schema-constrained CAD command and token usage; the OpenAI API key remains server-only.

Milestones: Phase 1 foundation; Phase 2 sketching; Phase 3 basic 3D; Phase 4 AI commands; Phase 5 sketch-to-CAD; Phase 6 advanced modeling; Phases 6A–6E AR/depth/scan-to-CAD/inspection; Phase 7 cloud and billing; Phase 8 admin; Phase 9 hardening. Each phase is gated by the acceptance criteria in the brief.

## Project synchronization contract

`POST /v1/projects/:id/sync` accepts an authenticated, idempotent project mutation:

```json
{
  "mutationId": "a-new-UUID-for-this-attempt",
  "baseRevision": 0,
  "payload": { "id": "client-project-UUID", "name": "Bracket" }
}
```

- `baseRevision: 0` means this is the first backup. The server atomically creates a project owned by the authenticated user with the client-generated project ID.
- Later requests use the last `appliedRevision` acknowledged by the server, not the local document revision.
- A successful request returns the mutation record including a positive `appliedRevision`.
- Reusing the same mutation ID for the same owned project returns the original result.
- A stale base returns HTTP 409 with `REVISION_CONFLICT` and the current remote revision.
- Project and mutation lookups are ownership-scoped and do not disclose another user's records.

Local edits remain pending until the client validates and persists the returned applied revision.