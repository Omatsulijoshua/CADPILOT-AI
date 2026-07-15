# `.cadpilot` format

The native project is a ZIP archive written via a temporary sibling and atomic replacement.

```text
project.cadpilot
|- manifest.json
|- cad/operations.json
|- cad/sketches.json
|- cad/geometry.bin
|- materials/materials.json
|- annotations/annotations.json
|- prompts/history.json
|- references/
|- thumbnails/preview.webp
|- scans/scan_manifest.json
|- ar/placements.json
`- versions/index.json
```

The manifest stores format version, UUID, units, timestamps, app/engine versions, active revision, SHA-256 hashes, and feature flags. Operation history is authoritative; geometry is a rebuildable cache. Unknown optional fields are preserved. Spatial data is optional and can remain local-only. The current Flutter app persists versioned JSON locally; the atomic ZIP archive remains the migration target. Browser STL export is available separately for manufacturing output.
