/**
 * Ingestion/worker configuration accessor.
 *
 * The API agent owns the canonical `src/config.ts`. We do NOT hard-import it
 * (it may not exist yet, and NodeNext would fail the build). Instead we read
 * the same environment variables defensively here, and — if a richer config
 * object turns up at runtime — prefer its values via `loadSharedConfig()`.
 *
 * Region is pinned to ap-south-1 / asia-south1 (India-only at launch).
 */

import type { InferenceGeo, Region } from './types.js';

export interface IngestionConfig {
  region: Region;
  awsRegion: string; // ap-south-1
  inferenceGeo: InferenceGeo; // asia-south1
  s3Bucket: string;
  kmsKeyId: string;
  sqsQueueUrl: string;
  /** Optional localstack/MinIO endpoint override for local dev/tests. */
  s3Endpoint?: string;
  sqsEndpoint?: string;
  /** Presigned PUT TTL in seconds (default 300 = 5 min). */
  presignTtlSeconds: number;
  /** Worker long-poll wait (SQS WaitTimeSeconds). */
  sqsWaitSeconds: number;
  /** Worker visibility timeout while a parse job is in flight. */
  sqsVisibilityTimeout: number;
  /** Outbox relay poll interval (ms). */
  outboxPollMs: number;
}

const num = (v: string | undefined, dflt: number): number => {
  const n = v === undefined ? NaN : Number(v);
  return Number.isFinite(n) ? n : dflt;
};

/**
 * Build config from process.env with India-pinned defaults. Pure + synchronous
 * so route/worker modules can call it at import time without a promise.
 */
export function getConfig(): IngestionConfig {
  return {
    region: (process.env.SPAN_REGION as Region) ?? 'in',
    awsRegion: process.env.AWS_REGION ?? 'ap-south-1',
    inferenceGeo: (process.env.SPAN_INFERENCE_GEO as InferenceGeo) ?? 'asia-south1',
    s3Bucket: process.env.S3_BUCKET ?? 'span-phi-992203938018-ap-south-1',
    kmsKeyId: process.env.KMS_KEY_ID ?? '',
    sqsQueueUrl: process.env.SQS_QUEUE_URL ?? '',
    s3Endpoint: process.env.S3_ENDPOINT,
    sqsEndpoint: process.env.SQS_ENDPOINT,
    presignTtlSeconds: num(process.env.PRESIGN_TTL_SECONDS, 300),
    sqsWaitSeconds: num(process.env.SQS_WAIT_SECONDS, 20),
    sqsVisibilityTimeout: num(process.env.SQS_VISIBILITY_TIMEOUT, 300),
    outboxPollMs: num(process.env.OUTBOX_POLL_MS, 2000),
  };
}

/**
 * If the API agent's `../config.js` exists at runtime and exports a `config`
 * object, merge any overlapping fields over our env-derived defaults. Failures
 * (module missing, shape mismatch) silently fall back — by design.
 */
export async function loadSharedConfig(): Promise<IngestionConfig> {
  const base = getConfig();
  try {
    // Dynamic, optional — compiled as a runtime import so a missing module is
    // a caught rejection, not a compile error.
    const mod: any = await import(
      /* @vite-ignore */ '../config.js'
    ).catch(() => null);
    const shared = mod?.config ?? mod?.default ?? null;
    if (shared && typeof shared === 'object') {
      return {
        ...base,
        awsRegion: shared.awsRegion ?? shared.region ?? base.awsRegion,
        s3Bucket: shared.s3Bucket ?? shared.bucket ?? base.s3Bucket,
        kmsKeyId: shared.kmsKeyId ?? shared.kms_key_id ?? base.kmsKeyId,
        sqsQueueUrl: shared.sqsQueueUrl ?? shared.queueUrl ?? base.sqsQueueUrl,
        inferenceGeo: shared.inferenceGeo ?? base.inferenceGeo,
      };
    }
  } catch {
    /* fall through to env-derived base */
  }
  return base;
}
