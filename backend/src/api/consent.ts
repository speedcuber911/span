/**
 * Project Span — Consent management + consent gate.
 *
 *   POST   /v1/consents          {scope, granted, policy_version}  — record consent
 *   DELETE /v1/consents/:scope                                     — withdraw (withdrawn_at)
 *   GET    /v1/consents                                            — list current state
 *   GET    /v1/policy/current                                     — readable policy_versions
 *
 *   requireConsent(scope) — a preHandler other routes mount to gate on an active
 *   consent; returns 409 CONSENT_REQUIRED if none.
 *
 * Consents are versioned against policy_versions and withdrawable (SPAN_MASTER_PLAN
 * §9 / schema §3).  Grant + withdraw are audited (no PHI in the audit meta).
 */

import { createHash } from 'node:crypto';
import type { FastifyInstance, FastifyRequest, preHandlerHookHandler } from 'fastify';
import { z } from 'zod';

import { query } from '../db/index.js';
import { RESIDENCY } from '../config.js';
import {
  ApiError,
  audit,
  authPreHandler,
  clientIp,
  conflict,
  runAsUser,
} from './middleware.js';

// Consent scopes — must match the CHECK constraint in 0001_init.sql.
const SCOPES = [
  'ingestion',
  'gmail_readonly',
  'processing',
  'storage',
  'voice',
  'research_deidentified',
] as const;
type Scope = (typeof SCOPES)[number];

const scopeSchema = z.enum(SCOPES);

const grantBody = z.object({
  scope: scopeSchema,
  granted: z.boolean(),
  policy_version: z.string().min(1),
  // 'tap' | 'voice_confirmed' | 'api' — matches the method CHECK constraint.
  method: z.enum(['tap', 'voice_confirmed', 'api']).default('tap'),
  // Optional human-readable purpose; defaults to the scope.
  purpose: z.string().min(1).optional(),
});

function hashIp(ip: string | undefined): string | null {
  if (!ip) return null;
  return createHash('sha256').update(`span-ip|${ip}`).digest('hex');
}

// ---------------------------------------------------------------------------
// requireConsent(scope) — preHandler factory.  Mount on routes that need an
// active (granted, not-withdrawn) consent for `scope`.
// ---------------------------------------------------------------------------
export function requireConsent(scope: Scope): preHandlerHookHandler {
  return async (req: FastifyRequest) => {
    const active = await runAsUser(req, async (client) => {
      const { rows } = await client.query<{ id: string }>(
        `SELECT id FROM consents
          WHERE user_id = current_setting('app.current_user_id', true)::uuid
            AND scope = $1 AND granted = true AND withdrawn_at IS NULL
          ORDER BY granted_at DESC
          LIMIT 1`,
        [scope],
      );
      return rows[0];
    });
    if (!active) {
      throw conflict('CONSENT_REQUIRED', `Active consent required for scope '${scope}'`);
    }
  };
}

// ---------------------------------------------------------------------------
// Routes.
// ---------------------------------------------------------------------------
// eslint-disable-next-line @typescript-eslint/require-await
export default async function consentRoutes(app: FastifyInstance): Promise<void> {
  // All consent routes require an authenticated user.
  app.addHook('preHandler', authPreHandler);

  // GET /v1/policy/current — current policy versions by kind (non-PHI, but
  // auth-gated for simplicity; the client needs the version string before granting).
  app.get('/policy/current', async () => {
    const { rows } = await query<{
      version: string;
      kind: string;
      effective_at: Date;
      copy_hash: string;
    }>(
      `SELECT DISTINCT ON (kind) version, kind, effective_at, copy_hash
         FROM policy_versions
        WHERE effective_at <= now()
        ORDER BY kind, effective_at DESC`,
    );
    return { policies: rows };
  });

  // GET /v1/consents — current consent state for the caller.
  app.get('/consents', async (req) => {
    const rows = await runAsUser(req, async (client) => {
      const res = await client.query(
        `SELECT DISTINCT ON (scope)
                scope, granted, policy_version, granted_at, withdrawn_at
           FROM consents
          WHERE user_id = current_setting('app.current_user_id', true)::uuid
          ORDER BY scope, granted_at DESC`,
      );
      return res.rows;
    });
    return { consents: rows };
  });

  // POST /v1/consents — record a grant (or an explicit denial).
  app.post('/consents', async (req, reply) => {
    const parsed = grantBody.safeParse(req.body);
    if (!parsed.success) {
      throw new ApiError(400, 'INVALID_REQUEST', 'Malformed consent payload');
    }
    const { scope, granted, policy_version, method, purpose } = parsed.data;

    // Validate the referenced policy version exists (FK would 500 otherwise).
    const { rows: pv } = await query<{ version: string }>(
      `SELECT version FROM policy_versions WHERE version = $1`,
      [policy_version],
    );
    if (!pv[0]) {
      throw new ApiError(400, 'UNKNOWN_POLICY_VERSION', `Unknown policy_version '${policy_version}'`);
    }

    const ua = req.headers['user-agent'];
    const evidence = {
      ua: typeof ua === 'string' ? ua : null,
      ip_hash: hashIp(clientIp(req)),
    };

    const consentId = await runAsUser(req, async (client) => {
      const { rows } = await client.query<{ id: string }>(
        `INSERT INTO consents
           (user_id, region, scope, purpose, policy_version, granted, method, ip_at_grant, evidence_blob)
         VALUES (current_setting('app.current_user_id', true)::uuid,
                 $1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING id`,
        [
          RESIDENCY.region,
          scope,
          purpose ?? scope,
          policy_version,
          granted,
          method,
          clientIp(req) ?? null,
          JSON.stringify(evidence),
        ],
      );
      return rows[0]?.id;
    });

    await audit(granted ? 'consent.granted' : 'consent.denied', 'consents', consentId ?? null, {
      req,
      detail: { scope, policy_version, method },
    });

    return reply.code(201).send({ id: consentId, scope, granted });
  });

  // DELETE /v1/consents/:scope — withdraw the active consent for a scope.
  app.delete('/consents/:scope', async (req, reply) => {
    const params = z.object({ scope: scopeSchema }).safeParse(req.params);
    if (!params.success) {
      throw new ApiError(400, 'INVALID_SCOPE', 'Unknown consent scope');
    }
    const { scope } = params.data;

    const withdrawnId = await runAsUser(req, async (client) => {
      const { rows } = await client.query<{ id: string }>(
        `UPDATE consents
            SET withdrawn_at = now()
          WHERE user_id = current_setting('app.current_user_id', true)::uuid
            AND scope = $1 AND granted = true AND withdrawn_at IS NULL
          RETURNING id`,
        [scope],
      );
      return rows[0]?.id;
    });

    if (!withdrawnId) {
      throw new ApiError(404, 'NO_ACTIVE_CONSENT', `No active consent to withdraw for '${scope}'`);
    }

    await audit('consent.withdrawn', 'consents', withdrawnId, {
      req,
      detail: { scope },
    });

    // TODO(compliance): withdrawing 'voice' should trigger scoped deletion of
    // transcripts (§9 "Withdrawal … may trigger scoped deletion").  Hand off to
    // the deletion pipeline once scoped-erasure jobs exist.

    return reply.code(200).send({ scope, withdrawn: true });
  });
}
