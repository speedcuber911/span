# src/api — HTTP Routes

Fastify route handlers for the `/v1` API surface.

Responsibilities:
- Auth middleware (Sign in with Apple / JWT validation)
- Consent gate (blocks requests if active consent record is missing)
- Postgres RLS session variable injection (`SET app.current_user_id`)
- Region residency assertion (`region = 'in'` for every PHI read/write)
- Routes: users, artifacts (presign), measurements, scores, voice sessions, export/delete
