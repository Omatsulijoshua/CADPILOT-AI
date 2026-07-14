# Security baseline

Secrets and provider keys are backend-only. Passwords use Argon2id. Access tokens are short-lived; refresh tokens are hashed, rotated, and revocable. DTO validation rejects unknown fields and every project operation checks membership. Sync mutations are idempotent and bounded. Logs exclude credentials, tokens, raw prompts, and scan contents. Spatial projects default private and must support local-only and geometry-only modes before scanning ships.
