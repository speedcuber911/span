/**
 * Span async WORKER — long-polls SQS FIFO and runs the parse → post-process →
 * persist pipeline (SPAN_MASTER_PLAN.md §4/§5).
 *
 * For each ingestion.parse.requested message:
 *   1. job.status := 'parsing'
 *   2. call the LLM parse (src/llm/parse.ts, imported DEFENSIVELY) → ExtractedReport
 *   3. DETERMINISTIC post-process (worker/postprocess.ts) — the part we own
 *   4. UPSERT reports + measurements (idempotent on UNIQUE(user_id, report_id,
 *      parameter, date)); idempotent overall on artifact_id (one report/artifact)
 *   5. job.status := 'extracted' (or 'needs_review' if low-conf/outlier rows)
 *   6. write outbox 'ingestion.parse.completed' + 'measurements.committed'
 *      (the latter triggers the analysis layer to recompute) — same txn
 *   7. delete the SQS message ON SUCCESS only
 *
 * On failure we DO NOT delete the message → SQS redelivers; after the queue's
 * maxReceiveCount (=5) it lands in the DLQ. The job is marked 'failed' with an
 * error_code so the progress UX can surface it.
 */

import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand,
} from '@aws-sdk/client-sqs';
import type { Message } from '@aws-sdk/client-sqs';
import type pg from 'pg';
import { withUser, withTransaction } from '../db/index.js';
import { getConfig } from '../ingestion/config.js';
import { SCHEMA_VERSION } from '../ingestion/types.js';
import type {
  ExtractedReport,
  ParseHint,
  ParseReportFn,
  ParseRequestedMessage,
  ParseCompletedMessage,
  MeasurementsCommittedMessage,
} from '../ingestion/types.js';
import {
  loadDictionary,
  processReport,
  type ProcessedMeasurement,
} from './postprocess.js';

let _sqs: SQSClient | null = null;
function sqs(): SQSClient {
  if (_sqs) return _sqs;
  const cfg = getConfig();
  _sqs = new SQSClient({
    region: cfg.awsRegion,
    ...(cfg.sqsEndpoint ? { endpoint: cfg.sqsEndpoint } : {}),
  });
  return _sqs;
}

// ── Defensive LLM parse import ──────────────────────────────────────────────

let _parseFn: ParseReportFn | null | undefined;

/**
 * Resolve src/llm/parse.ts#parseReport at runtime. The llm agent may not have
 * landed it yet; a missing/broken module yields null and the job fails cleanly
 * (message not deleted → DLQ after retries) rather than crashing the worker.
 */
async function getParseFn(): Promise<ParseReportFn | null> {
  if (_parseFn !== undefined) return _parseFn ?? null;
  try {
    const mod: any = await import('../llm/parse.js');
    const fn = mod?.parseReport ?? mod?.default;
    _parseFn = typeof fn === 'function' ? (fn as ParseReportFn) : null;
  } catch {
    _parseFn = null;
  }
  return _parseFn ?? null;
}

/** Test seam: inject a fake parse fn. */
export function __setParseFn(fn: ParseReportFn | null): void {
  _parseFn = fn;
}

// ── Message handling ────────────────────────────────────────────────────────

class NonRetryableError extends Error {}

function parseMessage(body: string | undefined): ParseRequestedMessage | null {
  if (!body) return null;
  try {
    const m = JSON.parse(body) as ParseRequestedMessage;
    if (m && m.topic === 'ingestion.parse.requested' && m.artifact_id && m.user_id) {
      return m;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Process one parse.requested message end-to-end. Throws on a retryable failure
 * (caller leaves the message on the queue); returns normally on success or on a
 * permanent/idempotent skip (caller deletes the message).
 */
export async function handleParseRequested(msg: ParseRequestedMessage): Promise<void> {
  const { user_id: userId, artifact_id: artifactId, job_id: jobId } = msg;

  // Idempotency: if a report already exists for this artifact, we've committed
  // before — short-circuit and let the message be deleted.
  const already = await withUser(userId, async (client: pg.PoolClient) => {
    const { rows } = await client.query<{ id: string }>(
      `SELECT id FROM reports WHERE user_id=$1 AND artifact_id=$2 LIMIT 1`,
      [userId, artifactId],
    );
    return rows[0]?.id ?? null;
  });
  if (already) {
    await markJob(userId, jobId, 'extracted', null, 100);
    return;
  }

  // 1) status → parsing
  await markJob(userId, jobId, 'parsing', null, 40);

  // 2) LLM parse (defensive).
  const parseFn = await getParseFn();
  if (!parseFn) {
    await markJob(userId, jobId, 'failed', 'llm_parse_unavailable', null);
    // Retryable: the llm module may land later; do NOT delete the message.
    throw new Error('llm parse fn unavailable');
  }

  let extracted: ExtractedReport;
  try {
    const hint: ParseHint = msg.hint ?? {};
    extracted = await parseFn(msg.storage.key, hint);
  } catch (err) {
    await markJob(userId, jobId, 'failed', 'llm_parse_error', null);
    throw err instanceof Error ? err : new Error('llm parse threw');
  }

  if (!extracted || !Array.isArray(extracted.rows)) {
    await markJob(userId, jobId, 'failed', 'llm_bad_output', null);
    // Bad output is unlikely to fix itself, but redelivery is harmless; let it DLQ.
    throw new NonRetryableError('llm returned no rows');
  }

  // 3) deterministic post-process (ours).
  const dict = await withTransaction((client: pg.PoolClient) => loadDictionary(client));
  const processed = processReport(extracted, dict);

  // 4–6) persist + outbox, all in ONE RLS transaction.
  const { reportId, committed } = await persist(userId, msg, processed.lab, processed.report_date, processed.measurements, processed.needsReview);

  // 5/6 status + completion event handled inside persist(); nothing else to do.
  void reportId;
  void committed;
}

async function persist(
  userId: string,
  msg: ParseRequestedMessage,
  lab: string | null,
  reportDate: string | null,
  measurements: ProcessedMeasurement[],
  needsReview: boolean,
): Promise<{ reportId: string; committed: number }> {
  const cfg = getConfig();

  return withUser(userId, async (client: pg.PoolClient) => {
    // UPSERT report (idempotent on artifact_id — one report per artifact).
    const repRes = await client.query<{ id: string }>(
      `INSERT INTO reports (user_id, region, artifact_id, lab, report_date, s3_key)
       VALUES ($1,$2,$3,$4,$5,$6)
       RETURNING id`,
      [userId, cfg.region, msg.artifact_id, lab, reportDate, msg.storage.key],
    );
    const reportId = repRes.rows[0]!.id;

    // Effective date for the measurement key. Fall back to today if unprinted.
    const effDate = reportDate ?? new Date().toISOString().slice(0, 10);

    const committedIds: string[] = [];
    for (const m of measurements) {
      const ins = await client.query<{ id: string }>(
        `INSERT INTO measurements
           (user_id, region, report_id, date, parameter, parameter_raw, category,
            canonical_param_id, loinc_code, value, value_text, value_operator,
            unit, unit_raw, ref_low, ref_high, ref_text, ref_qualifier, flag, lab,
            sources, field_confidence, extraction_status)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23)
         ON CONFLICT (user_id, report_id, parameter, date)
         DO UPDATE SET
            value           = EXCLUDED.value,
            value_text      = EXCLUDED.value_text,
            value_operator  = EXCLUDED.value_operator,
            unit            = EXCLUDED.unit,
            unit_raw        = EXCLUDED.unit_raw,
            ref_low         = EXCLUDED.ref_low,
            ref_high        = EXCLUDED.ref_high,
            ref_text        = EXCLUDED.ref_text,
            ref_qualifier   = EXCLUDED.ref_qualifier,
            flag            = EXCLUDED.flag,
            field_confidence= EXCLUDED.field_confidence
         RETURNING id`,
        [
          userId,
          cfg.region,
          reportId,
          effDate,
          m.parameter,
          m.parameter_raw,
          m.category,
          m.canonical_param_id,
          m.loinc_code,
          m.value,
          m.value_text,
          m.value_operator,
          m.unit,
          m.unit_raw,
          m.ref_low,
          m.ref_high,
          m.ref_text,
          m.ref_qualifier ? JSON.stringify(m.ref_qualifier) : null,
          m.flag,
          lab,
          ['span_parser'],
          m.field_confidence ? JSON.stringify(m.field_confidence) : null,
          needsReview ? 'auto_accepted' : 'auto_accepted',
        ],
      );
      const id = ins.rows[0]?.id;
      if (id) committedIds.push(id);

      // Queue a review task for any flagged row (low conf / outlier / unmapped).
      if (m.review_reasons.length > 0 && m.review_reasons.some((r) => r !== 'mid_conf')) {
        const reason = pickReviewReason(m.review_reasons);
        await client.query(
          `INSERT INTO review_tasks
             (user_id, ingestion_job_id, measurement_draft, reason, assigned_to)
           VALUES ($1,$2,$3::jsonb,$4,'user')`,
          [userId, msg.job_id, JSON.stringify(m), reason],
        );
      }
    }

    // 5) job status — needs_review if any non-trivial review reason, else extracted.
    const finalStatus = needsReview ? 'needs_review' : 'extracted';
    await client.query(
      `UPDATE ingestion_jobs
          SET status=$2, progress_pct=100, error_code=NULL, updated_at=now()
        WHERE id=$1`,
      [msg.job_id, finalStatus],
    );

    // 6) completion outbox event (drives app progress UX).
    const completed: ParseCompletedMessage = {
      schema_version: SCHEMA_VERSION,
      topic: 'ingestion.parse.completed',
      job_id: msg.job_id,
      artifact_id: msg.artifact_id,
      user_id: userId,
      region: cfg.region,
      report_id: reportId,
      outcome: needsReview ? 'needs_review' : 'extracted',
      measurements_committed: committedIds.length,
      review_count: measurements.filter(
        (m) => m.review_reasons.some((r) => r !== 'mid_conf'),
      ).length,
    };
    await client.query(
      `INSERT INTO outbox (job_id, topic, payload, published)
       VALUES ($1,'ingestion.parse.completed',$2::jsonb,false)`,
      [msg.job_id, JSON.stringify(completed)],
    );

    // measurements.committed → analysis layer recomputes trends/scores (§7).
    const committedEvt: MeasurementsCommittedMessage = {
      schema_version: SCHEMA_VERSION,
      topic: 'measurements.committed',
      user_id: userId,
      region: cfg.region,
      report_id: reportId,
      artifact_id: msg.artifact_id,
      measurement_ids: committedIds,
    };
    await client.query(
      `INSERT INTO outbox (job_id, topic, payload, published)
       VALUES ($1,'measurements.committed',$2::jsonb,false)`,
      [msg.job_id, JSON.stringify(committedEvt)],
    );

    return { reportId, committed: committedIds.length };
  });
}

function pickReviewReason(
  reasons: string[],
): 'low_conf' | 'outlier' | 'unmapped_param' | 'unit_ambiguous' {
  if (reasons.includes('outlier')) return 'outlier';
  if (reasons.includes('unmapped_param')) return 'unmapped_param';
  if (reasons.includes('unit_ambiguous')) return 'unit_ambiguous';
  return 'low_conf';
}

async function markJob(
  userId: string,
  jobId: string,
  status: string,
  errorCode: string | null,
  progress: number | null,
): Promise<void> {
  await withUser(userId, async (client: pg.PoolClient) => {
    await client.query(
      `UPDATE ingestion_jobs
          SET status=$2,
              error_code=$3,
              attempt = attempt + CASE WHEN $2='failed' THEN 1 ELSE 0 END,
              progress_pct=COALESCE($4, progress_pct),
              updated_at=now()
        WHERE id=$1`,
      [jobId, status, errorCode, progress],
    );
  });
}

// ── Poll loop ───────────────────────────────────────────────────────────────

let _running = false;

export async function runWorker(): Promise<void> {
  const cfg = getConfig();
  _running = true;
  // eslint-disable-next-line no-console
  console.log('[worker] starting', {
    queue: cfg.sqsQueueUrl ? 'configured' : 'MISSING (idle)',
    region: cfg.awsRegion,
  });

  while (_running) {
    if (!cfg.sqsQueueUrl) {
      await sleep(cfg.outboxPollMs);
      continue;
    }
    try {
      const res = await sqs().send(
        new ReceiveMessageCommand({
          QueueUrl: cfg.sqsQueueUrl,
          MaxNumberOfMessages: 5,
          WaitTimeSeconds: cfg.sqsWaitSeconds,
          VisibilityTimeout: cfg.sqsVisibilityTimeout,
          MessageAttributeNames: ['All'],
        }),
      );
      const messages: Message[] = res.Messages ?? [];
      for (const m of messages) {
        await processOne(m, cfg.sqsQueueUrl);
      }
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[worker] receive loop error', err);
      await sleep(5000);
    }
  }
}

async function processOne(m: Message, queueUrl: string): Promise<void> {
  const parsed = parseMessage(m.Body);
  if (!parsed) {
    // Unrecognized message — delete so it doesn't poison the queue forever.
    // (A genuinely malformed body cannot be retried into validity.)
    if (m.ReceiptHandle) await deleteMessage(queueUrl, m.ReceiptHandle);
    return;
  }
  try {
    await handleParseRequested(parsed);
    if (m.ReceiptHandle) await deleteMessage(queueUrl, m.ReceiptHandle);
  } catch (err) {
    // DLQ-on-repeat: do NOT delete → SQS redelivers; maxReceiveCount=5 → DLQ.
    // eslint-disable-next-line no-console
    console.error('[worker] parse job failed (will retry/DLQ)', {
      artifact_id: parsed.artifact_id,
      err: err instanceof Error ? err.message : String(err),
    });
  }
}

async function deleteMessage(queueUrl: string, receiptHandle: string): Promise<void> {
  await sqs().send(
    new DeleteMessageCommand({ QueueUrl: queueUrl, ReceiptHandle: receiptHandle }),
  );
}

export function stopWorker(): void {
  _running = false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((res) => setTimeout(res, ms));
}

// Entrypoint when run directly (npm run start:worker).
const isMain =
  typeof process !== 'undefined' &&
  process.argv[1] !== undefined &&
  import.meta.url === `file://${process.argv[1]}`;

if (isMain) {
  runWorker().catch((err) => {
    // eslint-disable-next-line no-console
    console.error('[worker] fatal', err);
    process.exit(1);
  });
}
