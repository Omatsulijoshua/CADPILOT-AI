# User-facing text encoding cleanup

This increment repairs visible mojibake in the tablet application and prevents the same class of corruption from returning unnoticed.

## Repaired labels

- Sign-in progress.
- Project revision and sync status.
- Autosave progress.
- Design-notes placeholder.

The replacements use encoding-safe punctuation while preserving the original meaning.

## Regression protection

A source-level test scans all user-facing Dart source files for common UTF-8/Windows-1252 corruption markers. The test fails if those markers reappear.

## Verification

- Flutter static analysis passes.
- All 89 Flutter tests pass.
- Android debug APK builds successfully.
- The repaired strings were confirmed directly in the formatted source.
