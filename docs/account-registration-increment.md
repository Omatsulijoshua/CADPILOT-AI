# Account registration increment

This increment completes CadPilot onboarding by connecting the existing backend registration contract to the Flutter application.

## Included

- Adds `CloudApi.register` for display name, normalized email, and password.
- Reuses one strict credential-envelope parser for sign-in and registration.
- Rejects empty tokens, invalid email identities, missing display names, and malformed authentication responses.
- Maps duplicate-email conflicts to a safe user-facing message without exposing server/database details.
- Adds controller-side display-name, email, and password validation before network access.
- Persists access/refresh tokens in secure storage and the signed-in session locally after successful registration.
- Adds a create-account/sign-in mode switch to onboarding.
- Shows display name only in registration mode and updates headings, descriptions, busy labels, and actions appropriately.
- Retains guest mode as a local-first fallback.
- Disposes all onboarding text controllers with the widget lifecycle.

## Validation

Display name requires at least two non-whitespace characters. Email must contain an address separator and passwords require at least eight characters, matching the current backend DTO minimums. The server remains authoritative for complete email validation and uniqueness.

## Verification

- Flutter analysis passes with no issues.
- All 128 Flutter tests pass.
- Registration payload normalization, successful credential parsing, duplicate email handling, and malformed responses have dedicated tests.
- Android and Flutter Web builds are verified after the finalized onboarding change.