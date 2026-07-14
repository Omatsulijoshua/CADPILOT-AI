# AI command safety

The canonical schema is `shared/schemas/ai-cad-command.schema.json`. Commands are parsed, schema-validated, checked against current model IDs and constraints, previewed, explicitly confirmed when required, and committed as one undoable history transaction. The model cannot run code or access files. Spatial operations use the same transaction and confidence/assumption policy when their phases ship.
