/**
 * Project Span — Sign in with Apple + our own session tokens.
 *
 * Flow (SPAN_MASTER_PLAN §9 "Auth"):
 *   POST /v1/auth/apple
 *     1. Verify Apple identity_token against Apple's JWKS (iss/aud/exp/nonce).
 *     2. Extract the stable `sub`.
 *     3. Upsert users (apple_sub unique, region='in', storage_geo='ap-south-1',
 *        inference_geo='asia-south1'); create an empty profiles row on first sign-in.
 *     4. Mint OUR access token (~15 min) + a rotating opaque refresh token.
 *   POST /v1/auth/refresh
 *     Rotate the refresh token; on reuse of an already-rotated token, revoke the
 *     whole family (theft detection).
 *
 * We NEVER reuse Apple's identity_token as our session — Apple's token bootstraps
 * identity exactly once.  The `authorization_code` is accepted for future Apple
 * account-revocation / SiwA-driven deletion (TODO below); not yet exchanged.
 */

import { createHash, randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { z } from 'zod';

import { query, withTransaction } from '../db/index.js';
import { config, RESIDENCY } from '../config.js';
import { ApiError, audit, unauthorized } from './middleware.js';

// ---------------------------------------------------------------------------
// Apple constants.
// ---------------------------------------------------------------------------
const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = new URL('https://appleid.apple.com/auth/keys');

// Cached remote JWKS — jose handles key rotation + caching internally.
const appleJwks = createRemoteJWKSet(APPLE_JWKS_URL);

// Token lifetimes.
const ACCESS_TTL_SECONDS = 15 * 60; // ~15 min
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

// ---------------------------------------------------------------------------
// Request schemas.
// ---------------------------------------------------------------------------
const appleBody = z.object({
  identity_token: z.string().min(1),
  authorization_code: z.string().min(1),
  // Optional nonce: if the client sent one to Apple, we require the token's
  // nonce to match (replay protection).
  nonce: z.string().min(1).optional(),
});

const refreshBody = z.object({
  refresh_token: z.string().min(1),
});

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------
function sha256Hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/** Hash a nonce the way Apple does when the client sends a hashed nonce. */
function sha256OfRaw(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}

interface SessionTokens {
  access_token: string;
  refresh_token: string;
  token_type: 'Bearer';
  expires_in: number;
}

/**
 * Issue a fresh access token + a new refresh token row in the given family.
 * Returns the opaque refresh secret (only time it exists in plaintext).
 */
async function issueSession(
  app: FastifyInstance,
  userId: string,
  familyId: string,
): Promise<SessionTokens> {
  const access_token = await app.jwt.sign(
    { sub: userId, type: 'access' as const },
    { expiresIn: ACCESS_TTL_SECONDS },
  );

  const refreshSecret = randomBytes(32).toString('base64url');
  const tokenHash = sha256Hex(refreshSecret);
  const expiresAt = new Date(Date.now() + REFRESH_TTL_MS);

  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO refresh_tokens (user_id, region, token_hash, family_id, expires_at)
       VALUES ($1, $2, $3, $4, $5)`,
      [userId, RESIDENCY.region, tokenHash, familyId, expiresAt.toISOString()],
    );
  });

  return {
    access_token,
    refresh_token: refreshSecret,
    token_type: 'Bearer',
    expires_in: ACCESS_TTL_SECONDS,
  };
}

interface AppleClaims {
  sub: string;
  email?: string;
  email_verified?: boolean | string;
  is_private_email?: boolean | string;
  nonce?: string;
  nonce_supported?: boolean;
}

// ---------------------------------------------------------------------------
// Routes.
// ---------------------------------------------------------------------------
// eslint-disable-next-line @typescript-eslint/require-await
export default async function authRoutes(app: FastifyInstance): Promise<void> {
  // -------------------------------------------------------------------------
  // POST /v1/auth/apple — verify Apple token, upsert user, mint our session.
  // -------------------------------------------------------------------------
  app.post('/auth/apple', async (req, reply) => {
    const parsed = appleBody.safeParse(req.body);
    if (!parsed.success) {
      throw new ApiError(400, 'INVALID_REQUEST', 'Malformed Sign in with Apple payload');
    }
    const { identity_token, nonce } = parsed.data;

    if (!config.APPLE_CLIENT_ID) {
      // Misconfiguration, not a client error.
      throw new ApiError(500, 'AUTH_NOT_CONFIGURED', 'Apple sign-in is not configured');
    }

    // 1. Verify the Apple identity_token (signature via JWKS, iss, aud, exp).
    let claims: AppleClaims;
    try {
      const { payload } = await jwtVerify(identity_token, appleJwks, {
        issuer: APPLE_ISSUER,
        audience: config.APPLE_CLIENT_ID,
        // jose enforces exp/nbf automatically; small clock tolerance for skew.
        clockTolerance: 30,
      });
      claims = payload as unknown as AppleClaims;
    } catch {
      throw unauthorized('Apple identity token failed verification');
    }

    // Nonce replay protection: if the client supplied a nonce, the token's nonce
    // must match either the raw value or its SHA-256 (Apple hashes the nonce).
    if (nonce) {
      const tokenNonce = claims.nonce;
      if (!tokenNonce || (tokenNonce !== nonce && tokenNonce !== sha256OfRaw(nonce))) {
        throw unauthorized('Nonce mismatch');
      }
    }

    const appleSub = claims.sub;
    if (!appleSub) {
      throw unauthorized('Apple token missing subject');
    }

    const emailPrivate =
      claims.is_private_email === true || claims.is_private_email === 'true';

    // 3. Upsert the user (region pins are immutable; only set on insert).
    //    Privileged path — this is identity creation, pre-RLS-session.
    const { rows } = await query<{ id: string; created: boolean }>(
      `INSERT INTO users (apple_sub, email_private, region, storage_geo, inference_geo)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (apple_sub) DO UPDATE SET updated_at = now()
       RETURNING id, (xmax = 0) AS created`,
      [
        appleSub,
        emailPrivate,
        RESIDENCY.region,
        RESIDENCY.storageGeo,
        RESIDENCY.inferenceGeo,
      ],
    );
    const row = rows[0];
    if (!row) {
      throw new ApiError(500, 'AUTH_UPSERT_FAILED', 'Could not establish user');
    }
    const userId = row.id;
    const isNewUser = row.created;

    // Create an empty profiles row on first sign-in (idempotent).
    if (isNewUser) {
      await query(
        `INSERT INTO profiles (user_id, region)
         VALUES ($1, $2)
         ON CONFLICT (user_id) DO NOTHING`,
        [userId, RESIDENCY.region],
      );
    }

    // 4. Mint our session (fresh family).
    const familyId = randomBytes(16).toString('hex');
    const tokens = await issueSession(app, userId, formatUuidLike(familyId));

    // TODO(auth): exchange `authorization_code` with Apple's /auth/token to obtain
    // a refresh token for detecting Apple-account revocation and powering
    // SiwA-driven deletion (§9).  Requires APPLE_TEAM_ID / key id / private key —
    // out of scope for this MVP slice.

    await audit(isNewUser ? 'auth.signup' : 'auth.signin', 'users', userId, {
      req,
      detail: { method: 'apple', new_user: isNewUser },
    });

    return reply.code(isNewUser ? 201 : 200).send({ user_id: userId, ...tokens });
  });

  // -------------------------------------------------------------------------
  // POST /v1/auth/refresh — rotate; revoke family on reuse (theft detection).
  // -------------------------------------------------------------------------
  app.post('/auth/refresh', async (req, reply) => {
    const parsed = refreshBody.safeParse(req.body);
    if (!parsed.success) {
      throw new ApiError(400, 'INVALID_REQUEST', 'Missing refresh_token');
    }
    const presentedHash = sha256Hex(parsed.data.refresh_token);

    // Atomically look up + rotate inside one transaction to avoid races.
    const result = await withTransaction(async (client) => {
      const { rows } = await client.query<{
        id: string;
        user_id: string;
        family_id: string;
        expires_at: Date;
        revoked_at: Date | null;
      }>(
        `SELECT id, user_id, family_id, expires_at, revoked_at
           FROM refresh_tokens
          WHERE token_hash = $1
          FOR UPDATE`,
        [presentedHash],
      );
      const token = rows[0];

      if (!token) {
        return { kind: 'unknown' as const };
      }

      // Theft detection: a token that has already been rotated (revoked) is being
      // replayed → revoke the entire family and refuse.
      if (token.revoked_at !== null) {
        await client.query(
          `UPDATE refresh_tokens
              SET revoked_at = now()
            WHERE family_id = $1 AND revoked_at IS NULL`,
          [token.family_id],
        );
        return { kind: 'reuse' as const, userId: token.user_id, familyId: token.family_id };
      }

      if (token.expires_at.getTime() <= Date.now()) {
        return { kind: 'expired' as const };
      }

      // Normal rotation: revoke the presented token; caller mints a successor in
      // the same family below.
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1`,
        [token.id],
      );
      return { kind: 'ok' as const, userId: token.user_id, familyId: token.family_id };
    });

    if (result.kind === 'reuse') {
      await audit('auth.refresh_reuse', 'refresh_tokens', null, {
        userId: result.userId,
        req,
        detail: { outcome: 'family_revoked' },
      });
      throw unauthorized('Refresh token reuse detected — session revoked');
    }
    if (result.kind !== 'ok') {
      // unknown / expired — do not leak which.
      throw unauthorized('Invalid or expired refresh token');
    }

    const tokens = await issueSession(app, result.userId, result.familyId);
    await audit('auth.refresh', 'refresh_tokens', null, {
      userId: result.userId,
      req,
      detail: { outcome: 'rotated' },
    });

    return reply.code(200).send({ user_id: result.userId, ...tokens });
  });
}

// refresh_tokens.family_id is uuid; we generate 16 random bytes → format as uuid.
function formatUuidLike(hex32: string): string {
  const h = hex32.padEnd(32, '0').slice(0, 32);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}
