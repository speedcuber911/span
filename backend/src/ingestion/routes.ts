/**
 * Ingestion HTTP routes — Fastify plugin the API process registers.
 *
 *   POST /v1/ingestion/intents          batch presign + dedup + job creation
 *   POST /v1/ingestion/:jobId/complete   verify upload → enqueue (txn outbox)
 *   GET  /v1/ingestion/jobs              list caller's jobs (progress UX)
 *   GET  /v1/ingestion/jobs/:id          one job
 *
 * Every PHI read/write is RLS-scoped via withUser(userId, …). The caller's
 * user_id is resolved from the authenticated request (the API agent owns auth;
 * we read req.user defensively and fall back to an injected resolver).
 *
 * The /complete handler writes the job status change AND the
 * 'ingestion.parse.requested' outbox row in ONE transaction — the transactional
 * outbox (§4): nothing is enqueued unless the status flip commits.
 */

import { z } from 'zod';
import type { FastifyInstance, FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import type pg from 'pg';
import { withUser } from '../db/index.js';
import { presignPutUrl, headObject, rawKey } from './storage.js';
import { getConfig } from './config.js';
import { SCHEMA_VERSION } from './types.js';
import type {
  IngestionIntentResponse,
  IngestionIntentResult,
  IngestionJobView,
  ParseRequestedMessage,
} from './types.js';

// ── Plugin options (lets the API inject auth + consent without us owning them) ─

export interface IngestionPluginOptions {
  /** Resolve the authenticated user_id from a request. Defaults to req.user. */
  getUserId?: (req: FastifyRequest) => string | undefined;
  /**
   * Consent gate. MUST return true before any byte is stored (consent-before-
   * storage, §4). If omitted we call hasIngestionConsent() which checks the
   * consents table; the compliance agent may inject a richer checker.
   */
  hasConsent?: (userId: string) => Promise<boolean>;
}

// ── Zod bodies ──────────────────────────────────────────────────────────────

const fileSchema = z.object({
  filename: z.string().min(1).max(512),
  mime_type: z.string().min(1).max(255),
  byte_size: z.number().int().nonnegative(),
  content_sha256: z.string().length(64).regex(/^[0-9a-fA-F]{64}$/),
  source: z.enum(['folder', 'photo', 'gmail']),
});

const intentBodySchema = z.object({
  files: z.array(fileSchema).min(1).max(100),
  idempotency_key: z.string().min(1).max(255).optional(),
});

const jobsQuerySchema = z.object({
  status: z
    .enum([
      'intent_created',
      'uploading',
      'uploaded',
      'enqueued',
      'parsing',
      'needs_review',
      'extracted',
      'committed',
      'failed',
      'duplicate',
      'quarantined',
    ])
    .optional(),
});

// ── Helpers ───────────────────────────────────────────────────────────────--

const MAX_BYTES = 50 * 1024 * 1024; // 50 MB upload cap (poison/size guard, §4)
const ALLOWED_MIME = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
  'image/tiff',
]);

function extFor(filename: string, mime: string): string {
  const m = filename.match(/\.([A-Za-z0-9]{1,8})$/);
  if (m && m[1]) return m[1].toLowerCase();
  const byMime: Record<string, string> = {
    'application/pdf': 'pdf',
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/tiff': 'tif',
  };
  return byMime[mime] ?? 'bin';
}

/** Default consent check against the consents table (overridable via opts). */
async function hasIngestionConsent(userId: string): Promise<boolean> {
  return withUser(userId, async (client: pg.PoolClient) => {
    const { rows } = await client.query(
      `SELECT 1
         FROM consents
        WHERE user_id = $1
          AND scope = 'ingestion'
          AND granted = true
          AND withdrawn_at IS NULL
        LIMIT 1`,
      [userId],
    );
    return rows.length > 0;
  });
}

function resolveUserId(
  req: FastifyRequest,
  opts: IngestionPluginOptions,
): string | undefined {
  if (opts.getUserId) return opts.getUserId(req);
  return req.user?.user_id ?? req.user?.sub;
}

// ── Plugin ────────────────────────────────────────────────────────────────--

export const ingestionRoutes: FastifyPluginAsync<IngestionPluginOptions> = async (
  app: FastifyInstance,
  opts: IngestionPluginOptions,
) => {
  const consentCheck = opts.hasConsent ?? hasIngestionConsent;
  const cfg = getConfig();

  // POST /v1/ingestion/intents — batch presign + dedup ----------------------
  app.post('/v1/ingestion/intents', async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = resolveUserId(req, opts);
    if (!userId) return reply.code(401).send({ error: 'unauthenticated' });

    const parsed = intentBodySchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'invalid_body', issues: parsed.error.issues });
    }
    const body = parsed.data;

    // Consent gate BEFORE any artifact row / presign (consent-before-storage).
    const ok = await consentCheck(userId);
    if (!ok) {
      return reply
        .code(409)
        .send({ error: 'consent_required', scope: 'ingestion' });
    }

    // Validate per-file caps up front (reject the whole batch on a bad file).
    for (const f of body.files) {
      if (f.byte_size > MAX_BYTES) {
        return reply.code(413).send({ error: 'file_too_large', filename: f.filename });
      }
      if (!ALLOWED_MIME.has(f.mime_type)) {
        return reply
          .code(415)
          .send({ error: 'unsupported_media_type', filename: f.filename, mime_type: f.mime_type });
      }
    }

    const idemBase = body.idempotency_key ?? `intent:${Date.now()}`;

    const results: IngestionIntentResult[] = await withUser(
      userId,
      async (client: pg.PoolClient) => {
        const out: IngestionIntentResult[] = [];
        for (let i = 0; i < body.files.length; i++) {
          const f = body.files[i]!;
          const sha = f.content_sha256.toLowerCase();

          // Dedup on UNIQUE(user_id, content_sha256). If the artifact already
          // exists, resolve to it (verdict 'duplicate') and reuse its job.
          const existing = await client.query<{ id: string }>(
            `SELECT id FROM ingestion_artifacts
              WHERE user_id = $1 AND content_sha256 = $2 LIMIT 1`,
            [userId, sha],
          );

          if (existing.rows.length > 0) {
            const artifactId = existing.rows[0]!.id;
            const job = await client.query<{ id: string }>(
              `SELECT id FROM ingestion_jobs WHERE artifact_id = $1 LIMIT 1`,
              [artifactId],
            );
            out.push({
              artifact_id: artifactId,
              job_id: job.rows[0]?.id ?? '',
              verdict: 'duplicate',
              content_sha256: sha,
            });
            continue;
          }

          // New artifact. Insert artifact (storage_key filled now from its id),
          // then the 1:1 job in status 'intent_created'.
          const ext = extFor(f.filename, f.mime_type);
          const ins = await client.query<{ id: string }>(
            `INSERT INTO ingestion_artifacts
               (user_id, region, source, original_filename, mime_type,
                byte_size, content_sha256, storage_bucket, kms_key_id)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
             RETURNING id`,
            [
              userId,
              cfg.region,
              f.source,
              f.filename,
              f.mime_type,
              f.byte_size,
              sha,
              cfg.s3Bucket,
              cfg.kmsKeyId || null,
            ],
          );
          const artifactId = ins.rows[0]!.id;
          const key = rawKey(userId, artifactId, ext);

          await client.query(
            `UPDATE ingestion_artifacts SET storage_key = $1 WHERE id = $2`,
            [key, artifactId],
          );

          const idemKey = `${idemBase}:${sha}`;
          const job = await client.query<{ id: string }>(
            `INSERT INTO ingestion_jobs
               (artifact_id, user_id, region, status, idempotency_key, progress_pct)
             VALUES ($1,$2,$3,'intent_created',$4,0)
             RETURNING id`,
            [artifactId, userId, cfg.region, idemKey],
          );
          const jobId = job.rows[0]!.id;

          const presign = await presignPutUrl(key, f.mime_type, sha);
          out.push({
            artifact_id: artifactId,
            job_id: jobId,
            verdict: 'new',
            content_sha256: sha,
            upload: {
              url: presign.url,
              method: 'PUT',
              headers: presign.headers,
              expires_at: presign.expiresAt,
            },
          });
        }
        return out;
      },
    );

    const resp: IngestionIntentResponse = { results };
    return reply.code(200).send(resp);
  });

  // POST /v1/ingestion/:jobId/complete — verify upload → enqueue (txn outbox)-
  app.post('/v1/ingestion/:jobId/complete', async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = resolveUserId(req, opts);
    if (!userId) return reply.code(401).send({ error: 'unauthenticated' });

    const params = req.params as { jobId?: string };
    const jobId = params.jobId;
    if (!jobId) return reply.code(400).send({ error: 'missing_job_id' });

    // Load the job + artifact (RLS-scoped) so we know the S3 key to HEAD.
    const loaded = await withUser(userId, async (client: pg.PoolClient) => {
      const { rows } = await client.query<{
        job_id: string;
        status: string;
        artifact_id: string;
        storage_key: string | null;
        storage_bucket: string | null;
        kms_key_id: string | null;
        mime_type: string | null;
        source: string;
        byte_size: string | null;
        content_sha256: string;
        page_count: number | null;
        sender_domain: string | null;
        original_filename: string | null;
      }>(
        `SELECT j.id AS job_id, j.status, a.id AS artifact_id,
                a.storage_key, a.storage_bucket, a.kms_key_id, a.mime_type,
                a.source, a.byte_size, a.content_sha256, a.page_count,
                a.sender_domain, a.original_filename
           FROM ingestion_jobs j
           JOIN ingestion_artifacts a ON a.id = j.artifact_id
          WHERE j.id = $1 AND j.user_id = $2`,
        [jobId, userId],
      );
      return rows[0] ?? null;
    });

    if (!loaded) return reply.code(404).send({ error: 'job_not_found' });
    if (!loaded.storage_key) {
      return reply.code(409).send({ error: 'artifact_not_presigned' });
    }

    // Idempotent: if already enqueued/past, return current status (no re-enqueue).
    const TERMINAL_OR_PAST = new Set([
      'enqueued', 'parsing', 'needs_review', 'extracted', 'committed', 'quarantined',
    ]);
    if (TERMINAL_OR_PAST.has(loaded.status)) {
      return reply.code(200).send({ status: loaded.status, idempotent: true });
    }

    // Verify the object actually landed in S3 + size sanity.
    const head = await headObject(loaded.storage_key);
    if (!head.exists) {
      return reply.code(409).send({ error: 'upload_not_found' });
    }
    if (head.contentLength !== undefined && head.contentLength === 0) {
      await withUser(userId, async (client: pg.PoolClient) => {
        await client.query(
          `UPDATE ingestion_jobs
              SET status='failed', error_code='empty_upload', updated_at=now()
            WHERE id=$1`,
          [jobId],
        );
      });
      return reply.code(409).send({ error: 'empty_upload' });
    }

    // Build the parse.requested payload once (ids only — no PHI values).
    const payload: ParseRequestedMessage = {
      schema_version: SCHEMA_VERSION,
      topic: 'ingestion.parse.requested',
      job_id: loaded.job_id,
      artifact_id: loaded.artifact_id,
      user_id: userId,
      region: cfg.region,
      inference_geo: cfg.inferenceGeo,
      storage: {
        bucket: loaded.storage_bucket ?? cfg.s3Bucket,
        key: loaded.storage_key,
        kms_key_id: loaded.kms_key_id ?? cfg.kmsKeyId,
      },
      source: loaded.source as ParseRequestedMessage['source'],
      mime_type: loaded.mime_type,
      page_count: loaded.page_count,
      content_sha256: loaded.content_sha256,
      hint: {
        sender_domain: loaded.sender_domain ?? undefined,
        original_filename: loaded.original_filename ?? undefined,
      },
    };

    // TRANSACTIONAL OUTBOX: flip status → 'enqueued' AND insert the outbox row
    // in ONE transaction. withUser already wraps in BEGIN/COMMIT.
    await withUser(userId, async (client: pg.PoolClient) => {
      // Re-check status inside the txn to avoid a double-enqueue race.
      const { rows } = await client.query<{ status: string }>(
        `SELECT status FROM ingestion_jobs WHERE id=$1 FOR UPDATE`,
        [jobId],
      );
      const cur = rows[0]?.status;
      if (cur && TERMINAL_OR_PAST.has(cur)) return; // someone beat us; no-op

      await client.query(
        `UPDATE ingestion_jobs
            SET status='enqueued', progress_pct=10, updated_at=now()
          WHERE id=$1`,
        [jobId],
      );
      await client.query(
        `UPDATE ingestion_artifacts SET av_scan='clean' WHERE id=$1`,
        [loaded.artifact_id],
      );
      await client.query(
        `INSERT INTO outbox (job_id, topic, payload, published)
         VALUES ($1, 'ingestion.parse.requested', $2::jsonb, false)`,
        [jobId, JSON.stringify(payload)],
      );
    });

    return reply.code(200).send({ status: 'enqueued' });
  });

  // GET /v1/ingestion/jobs — list caller's jobs (progress UX) ----------------
  app.get('/v1/ingestion/jobs', async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = resolveUserId(req, opts);
    if (!userId) return reply.code(401).send({ error: 'unauthenticated' });

    const parsed = jobsQuerySchema.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send({ error: 'invalid_query', issues: parsed.error.issues });
    }
    const { status } = parsed.data;

    const jobs = await withUser(userId, async (client: pg.PoolClient) => {
      const { rows } = await client.query<IngestionJobViewRow>(
        `SELECT j.id AS job_id, j.artifact_id, j.status, j.progress_pct,
                j.error_code, a.source, a.original_filename,
                j.created_at, j.updated_at
           FROM ingestion_jobs j
           JOIN ingestion_artifacts a ON a.id = j.artifact_id
          WHERE j.user_id = $1
            ${status ? 'AND j.status = $2' : ''}
          ORDER BY j.updated_at DESC
          LIMIT 200`,
        status ? [userId, status] : [userId],
      );
      return rows.map(toJobView);
    });

    return reply.code(200).send({ jobs });
  });

  // GET /v1/ingestion/jobs/:id ----------------------------------------------
  app.get('/v1/ingestion/jobs/:id', async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = resolveUserId(req, opts);
    if (!userId) return reply.code(401).send({ error: 'unauthenticated' });

    const params = req.params as { id?: string };
    const id = params.id;
    if (!id) return reply.code(400).send({ error: 'missing_id' });

    const job = await withUser(userId, async (client: pg.PoolClient) => {
      const { rows } = await client.query<IngestionJobViewRow>(
        `SELECT j.id AS job_id, j.artifact_id, j.status, j.progress_pct,
                j.error_code, a.source, a.original_filename,
                j.created_at, j.updated_at
           FROM ingestion_jobs j
           JOIN ingestion_artifacts a ON a.id = j.artifact_id
          WHERE j.id = $1 AND j.user_id = $2`,
        [id, userId],
      );
      return rows[0] ? toJobView(rows[0]) : null;
    });

    if (!job) return reply.code(404).send({ error: 'job_not_found' });
    return reply.code(200).send({ job });
  });
};

// ── Row → view mapping ───────────────────────────────────────────────────---

interface IngestionJobViewRow {
  job_id: string;
  artifact_id: string;
  status: string;
  progress_pct: number | null;
  error_code: string | null;
  source: string | null;
  original_filename: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

function toJobView(r: IngestionJobViewRow): IngestionJobView {
  return {
    job_id: r.job_id,
    artifact_id: r.artifact_id,
    status: r.status as IngestionJobView['status'],
    progress_pct: r.progress_pct,
    error_code: r.error_code,
    source: (r.source as IngestionJobView['source']) ?? null,
    original_filename: r.original_filename,
    created_at: typeof r.created_at === 'string' ? r.created_at : r.created_at.toISOString(),
    updated_at: typeof r.updated_at === 'string' ? r.updated_at : r.updated_at.toISOString(),
  };
}

export default ingestionRoutes;
