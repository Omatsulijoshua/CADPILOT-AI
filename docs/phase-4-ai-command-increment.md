# Phase 4 AI command increment

This increment establishes the local safety boundary for AI-authored CAD commands. The tablet accepts a structured command, validates it against the current sketch and model, shows a non-mutating preview, and requires an explicit Apply action before replacing the model document.

## Supported operations

- Extrude an existing rectangular profile with a positive depth.
- Cut an existing circular profile after a valid base extrusion exists.
- Rename an existing model-tree operation.
- Delete an existing model-tree operation.

All other operation types are rejected before mutation. Profile references, operation references, dimensions, required fields, and duplicate operation IDs are checked locally.

## Verify

1. Open a project with a rectangular sketch profile.
2. Choose AI command in the project toolbar.
3. Preview the generated structured extrude command and confirm the model has not changed.
4. Apply it and confirm the workspace switches to 3D and the operation appears in the model tree.
5. Reopen the project and confirm the model operation remains available.
6. Enter an unsupported type such as shell, or a missing profile ID, and confirm Preview rejects it.
7. Preview a valid command and choose Cancel; confirm the model remains unchanged.

## Persistence and audit

Applied and explicitly cancelled previews are stored as project-level AI command records with command ID, summary, status, and UTC timestamp. Project deserialization now restores both the 3D model document and AI audit history.

## Honest limitations

This increment accepts structured JSON rather than natural-language chat and does not call a remote model. Usage metering, a visible history browser, server-side schema validation, signed model responses, and broader modeling operations remain for later Phase 4 increments. The current transaction is atomic at the project document level, but it is not yet integrated into the interactive model canvas undo stack.