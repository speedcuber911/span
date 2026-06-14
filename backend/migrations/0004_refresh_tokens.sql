-- =============================================================================
-- Project Span — Migration 0004: Refresh-token store (rotating, theft-detecting)
--
-- Owned by the API/auth layer (src/api/auth.ts).  Backs the session model in
-- SPAN_MASTER_PLAN §9 "Auth (Sign in with Apple)":
--   • Our own access token (~15 min, @fastify/jwt) is stateless — NOT stored here.
--   • The refresh token is an opaque random secret; only its SHA-256 hash is
--     stored.  Rotation issues a new row in the same `family_id` and revokes the
--     presented one.  Presenting an already-rotated (revoked) token is treated as
--     theft → the whole family is revoked.
--
-- Run as the migration role (superuser / owner).  This table is RLS-exempt: it is
-- looked up by token_hash BEFORE we know the user (refresh is pre-authentication),
-- so the API queries it via the privileged `query()`/`withTransaction()` path, not
-- `withUser()`.  It still carries user_id + region for cascade-delete and audit.
-- =============================================================================

CREATE TABLE refresh_tokens (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region      text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    -- SHA-256 (hex) of the opaque refresh secret.  The raw secret is returned to
    -- the client exactly once and never persisted.
    token_hash  char(64)    NOT NULL UNIQUE,
    -- All tokens minted from one login share a family_id.  Reuse of a rotated
    -- token revokes the entire family (RFC-style refresh-token rotation).
    family_id   uuid        NOT NULL,
    expires_at  timestamptz NOT NULL,
    -- Set when the token is rotated (normal) or force-revoked (theft / logout).
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Fast lookup on presentation (the hot path for /v1/auth/refresh):
CREATE INDEX idx_refresh_tokens_hash   ON refresh_tokens (token_hash);
-- Family revocation + per-user listing / cascade cleanup:
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
CREATE INDEX idx_refresh_tokens_user   ON refresh_tokens (user_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- Grants — the app role manages refresh tokens directly (pre-auth, RLS-exempt).
-- INSERT (mint), SELECT (lookup), UPDATE (set revoked_at).  No DELETE from the
-- app role: expired/revoked rows are reaped by an ops/cron job or cascade.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON refresh_tokens TO span_app;
