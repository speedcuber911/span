/**
 * S3 storage helpers for the ingestion layer (ap-south-1, SSE-KMS).
 *
 *   presignPutUrl(key, contentType, sha256) → short-lived device→bucket PUT,
 *       bound to SSE-KMS headers + the per-object KMS key (presigned-URL
 *       leakage mitigation, §4 Risks).
 *   headObject(key) → verify the object exists + read size/etag before enqueue.
 *   getObjectStream(key) → worker reads raw bytes for the parse pipeline.
 *
 * Bytes never transit the app server on upload: the client PUTs straight to S3
 * with the presigned URL. The server only presigns and later HEADs/GETs.
 */

import {
  S3Client,
  PutObjectCommand,
  HeadObjectCommand,
  GetObjectCommand,
} from '@aws-sdk/client-s3';
import type { HeadObjectCommandOutput } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getConfig } from './config.js';

let _client: S3Client | null = null;

/** Lazily build (and memoize) the region-pinned S3 client. */
export function s3(): S3Client {
  if (_client) return _client;
  const cfg = getConfig();
  _client = new S3Client({
    region: cfg.awsRegion,
    ...(cfg.s3Endpoint ? { endpoint: cfg.s3Endpoint, forcePathStyle: true } : {}),
  });
  return _client;
}

export interface PresignResult {
  url: string;
  /** Headers the client MUST send on the PUT for the signature to validate. */
  headers: Record<string, string>;
  expiresAt: string;
}

/**
 * Convert a lowercase-hex SHA-256 (64 chars) to the base64 form S3 expects in
 * the x-amz-checksum-sha256 header. Returns undefined if the hex is malformed.
 */
function hexSha256ToBase64(hex: string): string | undefined {
  if (!/^[0-9a-f]{64}$/i.test(hex)) return undefined;
  const bytes = Buffer.from(hex, 'hex');
  return bytes.toString('base64');
}

/**
 * Presign an S3 PUT with SSE-KMS bound into the signature. The returned headers
 * are mandatory on the client PUT — they bind the upload to our KMS key and
 * (when the client hash is well-formed) to the declared content hash.
 */
export async function presignPutUrl(
  key: string,
  contentType: string,
  sha256?: string,
): Promise<PresignResult> {
  const cfg = getConfig();
  const checksumB64 = sha256 ? hexSha256ToBase64(sha256) : undefined;

  const command = new PutObjectCommand({
    Bucket: cfg.s3Bucket,
    Key: key,
    ContentType: contentType,
    ServerSideEncryption: 'aws:kms',
    ...(cfg.kmsKeyId ? { SSEKMSKeyId: cfg.kmsKeyId } : {}),
    ...(checksumB64 ? { ChecksumSHA256: checksumB64 } : {}),
  });

  // Sign the SSE-KMS headers so a leaked URL cannot be replayed with different
  // encryption. signableHeaders forces the client to echo them verbatim.
  const signable = new Set<string>([
    'content-type',
    'x-amz-server-side-encryption',
  ]);
  if (cfg.kmsKeyId) signable.add('x-amz-server-side-encryption-aws-kms-key-id');
  if (checksumB64) signable.add('x-amz-checksum-sha256');

  const url = await getSignedUrl(s3(), command, {
    expiresIn: cfg.presignTtlSeconds,
    signableHeaders: signable,
  });

  const headers: Record<string, string> = {
    'Content-Type': contentType,
    'x-amz-server-side-encryption': 'aws:kms',
  };
  if (cfg.kmsKeyId) {
    headers['x-amz-server-side-encryption-aws-kms-key-id'] = cfg.kmsKeyId;
  }
  if (checksumB64) headers['x-amz-checksum-sha256'] = checksumB64;

  return {
    url,
    headers,
    expiresAt: new Date(Date.now() + cfg.presignTtlSeconds * 1000).toISOString(),
  };
}

export interface HeadResult {
  exists: boolean;
  contentLength?: number;
  etag?: string;
  contentType?: string;
}

/** HEAD the object: used by /complete to verify the upload actually landed. */
export async function headObject(key: string): Promise<HeadResult> {
  const cfg = getConfig();
  try {
    const out: HeadObjectCommandOutput = await s3().send(
      new HeadObjectCommand({ Bucket: cfg.s3Bucket, Key: key }),
    );
    return {
      exists: true,
      contentLength: out.ContentLength,
      etag: out.ETag,
      contentType: out.ContentType,
    };
  } catch (err: unknown) {
    const name = (err as { name?: string; $metadata?: { httpStatusCode?: number } }) ?? {};
    if (name.name === 'NotFound' || name.$metadata?.httpStatusCode === 404) {
      return { exists: false };
    }
    throw err;
  }
}

/**
 * Fetch the raw object Body (a Node readable stream) for the worker's parse
 * pipeline. Most parse paths pass the s3Key straight to the LLM layer, but this
 * is here for self-hosted OCR / hashing fallbacks.
 */
export async function getObjectStream(
  key: string,
): Promise<NodeJS.ReadableStream> {
  const cfg = getConfig();
  const out = await s3().send(
    new GetObjectCommand({ Bucket: cfg.s3Bucket, Key: key }),
  );
  if (!out.Body) {
    throw new Error(`S3 GetObject returned empty body for key=${key}`);
  }
  return out.Body as NodeJS.ReadableStream;
}

/** Build the canonical S3 key for a raw artifact: u/{user}/raw/{artifact}.{ext} */
export function rawKey(userId: string, artifactId: string, ext: string): string {
  const clean = ext.replace(/^\.+/, '').toLowerCase() || 'bin';
  return `u/${userId}/raw/${artifactId}.${clean}`;
}
