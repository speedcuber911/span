/**
 * Transactional-outbox relay → SQS FIFO.
 *
 * Polls the `outbox` table for unpublished rows, sends each to the SQS FIFO
 * queue, and marks it published — all under SELECT … FOR UPDATE SKIP LOCKED so
 * multiple relay instances never double-send a row.
 *
 *   MessageGroupId         = user_id   (per-user FIFO ordering + debounce, §4/§7)
 *   MessageDeduplicationId = artifact_id (queue-level dedup; idempotent worker)
 *
 * The relay is the ONLY thing that talks to SQS on the produce side — the API
 * handlers only ever write outbox rows in their own transaction. This decouples
 * the request path from SQS availability (durability: rows survive a queue
 * outage and drain when it returns).
 */

import {
  SQSClient,
  SendMessageCommand,
} from '@aws-sdk/client-sqs';
import type pg from 'pg';
import { withTransaction } from '../db/index.js';
import { getConfig } from './config.js';

let _sqs: SQSClient | null = null;

export function sqs(): SQSClient {
  if (_sqs) return _sqs;
  const cfg = getConfig();
  _sqs = new SQSClient({
    region: cfg.awsRegion,
    ...(cfg.sqsEndpoint ? { endpoint: cfg.sqsEndpoint } : {}),
  });
  return _sqs;
}

interface OutboxRow {
  id: string;
  job_id: string;
  topic: string;
  payload: unknown; // jsonb — already an object via pg
}

/** Pull a dedup id out of a payload (artifact_id preferred, else job/outbox id). */
function dedupId(payload: unknown, row: OutboxRow): string {
  const p = (payload ?? {}) as Record<string, unknown>;
  const artifact = typeof p.artifact_id === 'string' ? p.artifact_id : undefined;
  // Suffix with topic so parse.requested and parse.completed for the same
  // artifact are distinct messages (else FIFO would dedup the second).
  const base = artifact ?? row.job_id ?? row.id;
  return `${base}:${row.topic}`.slice(0, 128);
}

function groupId(payload: unknown, row: OutboxRow): string {
  const p = (payload ?? {}) as Record<string, unknown>;
  const user = typeof p.user_id === 'string' ? p.user_id : undefined;
  return user ?? row.job_id; // per-user ordering; fall back to per-job
}

/**
 * Process one batch of unpublished outbox rows. Returns the number sent.
 * Each row is locked (SKIP LOCKED), sent to SQS, and marked published in the
 * SAME transaction — so a crash after send-but-before-commit re-locks the row
 * and resends; SQS FIFO dedup (MessageDeduplicationId) makes that safe.
 */
export async function relayOnce(batchSize = 25): Promise<number> {
  const cfg = getConfig();
  if (!cfg.sqsQueueUrl) {
    // No queue configured (e.g. local dev) — nothing to do, don't spin hot.
    return 0;
  }

  return withTransaction(async (client: pg.PoolClient) => {
    const { rows } = await client.query<OutboxRow>(
      `SELECT id, job_id, topic, payload
         FROM outbox
        WHERE NOT published
        ORDER BY created_at
        FOR UPDATE SKIP LOCKED
        LIMIT $1`,
      [batchSize],
    );
    if (rows.length === 0) return 0;

    let sent = 0;
    for (const row of rows) {
      const body =
        typeof row.payload === 'string' ? row.payload : JSON.stringify(row.payload);
      await sqs().send(
        new SendMessageCommand({
          QueueUrl: cfg.sqsQueueUrl,
          MessageBody: body,
          MessageGroupId: groupId(row.payload, row),
          MessageDeduplicationId: dedupId(row.payload, row),
          MessageAttributes: {
            topic: { DataType: 'String', StringValue: row.topic },
          },
        }),
      );
      await client.query(
        `UPDATE outbox SET published = true, published_at = now() WHERE id = $1`,
        [row.id],
      );
      sent++;
    }
    return sent;
  });
}

let _running = false;

/**
 * Long-running relay loop. Polls every cfg.outboxPollMs; backs off on error.
 * Stop with stopOutboxRelay().
 */
export async function runOutboxRelay(): Promise<void> {
  const cfg = getConfig();
  _running = true;
  // eslint-disable-next-line no-console
  console.log('[outbox-relay] starting', {
    queue: cfg.sqsQueueUrl ? 'configured' : 'MISSING (idle)',
    pollMs: cfg.outboxPollMs,
  });

  while (_running) {
    try {
      const sent = await relayOnce();
      // If we drained a full-ish batch, loop immediately to keep up; else sleep.
      if (sent === 0) {
        await sleep(cfg.outboxPollMs);
      }
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[outbox-relay] error', err);
      await sleep(Math.max(cfg.outboxPollMs, 5000));
    }
  }
}

export function stopOutboxRelay(): void {
  _running = false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((res) => setTimeout(res, ms));
}
