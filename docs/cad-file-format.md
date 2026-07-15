# CadPilot project formats

## Current portable transfer format: `.cadpilot.json`

The app currently exports an interoperable, readable JSON file for user-driven
project transfer. It is intentionally separate from local persistence and cloud
sync: importing creates an independent local copy with a new identifier and no
remote revision.

```json
{
  "schemaVersion": 1,
  "format": "cadpilot-project",
  "exportedAt": "2026-07-15T02:00:00.000Z",
  "project": { "...": "CadProject JSON" },
  "integrity": {
    "algorithm": "sha256",
    "digest": "hex digest of the encoded project object"
  }
}
```

The parser enforces a 2 MiB UTF-8 limit, a JSON object, a supported schema
version, the `cadpilot-project` format identifier, required project/timestamp
fields, and—when present—a matching SHA-256 digest. The digest detects
corruption or accidental modification; it is not a cryptographic signature.
Legacy root-level `CadProject` JSON and earlier versioned manifests without an
`integrity` field remain importable.

## Migration target: `.cadpilot` archive

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
