# Phase 4 AI command increment

This increment establishes the safety boundary for AI-authored CAD commands and adds authenticated natural-language generation through the server-side OpenAI Responses API. The tablet accepts a structured command, validates it against the current sketch and model, shows a non-mutating preview, and requires an explicit Apply action before replacing the model document.

## Supported operations

- Extrude an existing rectangular profile with a positive depth.
- Cut an existing circular profile after a valid base extrusion exists.
- Rename an existing model-tree operation.
- Delete an existing model-tree operation.

All other operation types are rejected before mutation. Profile references, operation references, dimensions, required fields, and duplicate operation IDs are checked locally.

## Verify

1. Open a project with a rectangular sketch profile.
2. Sign in, choose AI command in the project toolbar, enter a natural-language request, and choose Generate.
3. Preview the generated structured extrude command and confirm the model has not changed.
4. Apply it and confirm the workspace switches to 3D and the operation appears in the model tree.
5. Reopen the project and confirm the model operation remains available.
6. Enter an unsupported type such as shell, or a missing profile ID, and confirm Preview rejects it.
7. Preview a valid command and choose Cancel; confirm the model remains unchanged.

## Server configuration

Set `OPENAI_API_KEY` only on the server. `OPENAI_CAD_MODEL` defaults to `gpt-5.6-luna` and is configurable. Apply the Prisma schema with `npm exec prisma db push` in development or the deployment migration workflow before enabling the endpoint. Requests use structured output and `store: false`; the server records provider, model, response ID, and token counts.

## Persistence and audit

Applied and explicitly cancelled previews are stored as project-level AI command records with command ID, summary, status, and UTC timestamp. Applied records also persist the pre-command model snapshot; the latest applied command exposes an Undo action in the history sidebar and remains undoable after reopening. Project deserialization now restores both the 3D model document and AI audit history.

## Honest limitations

Natural-language generation is available only to signed-in users on a server configured with an OpenAI API key; guests retain the local structured editor. Broader modeling operations, streaming chat, response signatures, quotas, and multi-level AI redo remain for later increments. AI undo is stack-safe and persisted, but currently restores only the latest still-applied AI command.