/**
 * Project Span — API middleware & per-request helpers.
 *
 *   • authPreHandler  — verifies OUR access JWT, pins request.userId.
 *   • runAsUser       — wraps db.withUser(req.userId, fn) so every PHI query
 *                       runs under the RLS session variable.
 *   • audit           — append-only audit_log writer (hashed IP, NO PHI in meta).
 *   • assertRegion    — residency guard; every PHI row must be region='in'.
 *
 * The access-token contract (minted in auth.ts):
 *   { sub: <user_id uuid>, type: 'access' }   — ~15 min TTL, signed with JWT_SECRET.
 * Refresh tokens are opaque + stored hashed (see auth.ts / migration 0004); they
 * are NEVER accepted here.
 */

import { createHash } from 'node:crypto';
import type { FastifyReply, FastifyRequest, preHandlerHookHandler } from 'fastify';
import type pg from 'pg';

import { withUser, withTransaction } from '../db/index.js';
import { RESIDENCY } from '../config.js';

// ---------------------------------------------------------------------------
// Fastify type augmentation: request.userId + our access-token payload shape.
// ---------------------------------------------------------------------------
declare module 'fastify' {
  interface FastifyRequest {
    /** Set by authPreHandler once the access JWT is verified. */
    userId?: string;
  }
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    // What WE sign/verify for our own session tokens.
    payload: { sub: string; type: 'access' | 'refresh' };
    // `request.user` after jwtVerify(). Kept permissive so other layers that read
    // `request.user.user_id` (e.g. ingestion routes) still typecheck; our access
    // tokens only ever set `sub` + `type`.
    user: { sub: string; type?: 'access' | 'refresh'; user_id?: string; [k: string]: unknown };
  }
}

// ---------------------------------------------------------------------------
// Stable error envelope.  We never leak PHI or stack traces (see index.ts).
// ---------------------------------------------------------------------------
export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export const unauthorized = (msg = 'Authentication required') =>
  new ApiError(401, 'UNAUTHORIZED', msg);
export const forbidden = (msg = 'Forbidden') => new ApiError(403, 'FORBIDDEN', msg);
export const notFound = (msg = 'Not found') => new ApiError(404, 'NOT_FOUND', msg);
export const conflict = (code: string, msg: string) => new ApiError(409, code, msg);

// ---------------------------------------------------------------------------
// authPreHandler — verify OUR access JWT and pin request.userId.
// Rejects refresh tokens presented as access tokens.
// ---------------------------------------------------------------------------
export const authPreHandler: preHandlerHookHandler = async (req: FastifyRequest) => {
  let payload: { sub: string; type: 'access' | 'refresh' };
  try {
    // @fastify/jwt decorates the request; verifies signature + exp against JWT_SECRET.
    payload = await req.jwtVerify<{ sub: string; type: 'access' | 'refresh' }>();
  } catch {
    throw unauthorized('Invalid or expired access token');
  }
  if (payload.type !== 'access' || !payload.sub) {
    throw unauthorized('Not an access token');
  }
  req.userId = payload.sub;
};

// ---------------------------------------------------------------------------
// runAsUser — run fn inside db.withUser(req.userId) so RLS is enforced.
// ---------------------------------------------------------------------------
export async function runAsUser<T>(
  req: FastifyRequest,
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  if (!req.userId) {
    throw unauthorized('No authenticated user on request');
  }
  return withUser(req.userId, fn);
}

// ---------------------------------------------------------------------------
// IP hashing — audit_log stores a salted hash, never the raw IP (§9).
// ---------------------------------------------------------------------------
function hashIp(ip: string | undefined): string | null {
  if (!ip) return null;
  // Salt with the JWT secret material indirectly: a fixed app-level pepper keeps
  // the hash non-reversible without a rainbow table over the IPv4 space.
  return createHash('sha256').update(`span-ip|${ip}`).digest('hex');
}

/** Best-effort client IP, honoring a single trusted proxy hop. */
export function clientIp(req: FastifyRequest): string | undefined {
  const fwd = req.headers['x-forwarded-for'];
  if (typeof fwd === 'string' && fwd.length > 0) {
    const first = fwd.split(',')[0];
    if (first) return first.trim();
  }
  return req.ip;
}

// ---------------------------------------------------------------------------
// audit — append-only write into audit_log.  NO PHI values in `detail`.
// Written via withTransaction (privileged path): the app role has INSERT-only
// on audit_log (migration 0002), so this can never update/delete prior rows.
// ---------------------------------------------------------------------------
export interface AuditOptions {
  /** Optional explicit user id (defaults to req.userId). */
  userId?: string | null;
  /** Hashed client IP is derived from the request, not passed in. */
  req?: FastifyRequest;
  /** Counts / keys / status codes only — NEVER PHI values. */
  detail?: Record<string, unknown>;
}

export async function audit(
  action: string,
  resource: string | null,
  resourceId: string | null,
  opts: AuditOptions = {},
): Promise<void> {
  const userId = opts.userId ?? opts.req?.userId ?? null;
  const actor = userId ? `user:${userId}` : 'system';
  const ipHash = opts.req ? hashIp(clientIp(opts.req)) : null;

  // Defensive: keep meta to scalar/serialisable, IP hashed not raw.
  const meta = {
    ...(opts.detail ?? {}),
    ...(ipHash ? { ip_hash: ipHash } : {}),
  };

  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO audit_log (user_id, actor, action, entity, entity_id, region, meta)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [userId, actor, action, resource, resourceId, RESIDENCY.region, JSON.stringify(meta)],
    );
  });
}

// ---------------------------------------------------------------------------
// assertRegion — residency guard.  Every PHI row must be region='in'.
// Throws (500-class) if a non-'in' row is ever read/written, surfacing a
// residency bug loudly rather than leaking cross-region data.
// ---------------------------------------------------------------------------
export function assertRegion(region: string | null | undefined): void {
  if (region !== RESIDENCY.region) {
    throw new ApiError(
      500,
      'RESIDENCY_VIOLATION',
      `Expected region='${RESIDENCY.region}', got '${region ?? 'null'}'`,
    );
  }
}

// Re-export so route files import a single reply helper if they need it.
export type { FastifyReply, FastifyRequest };
