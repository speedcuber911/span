/**
 * Project Span — shared environment configuration.
 *
 * Single zod-validated, frozen source of truth for every env var the API +
 * compliance layer needs.  Fail-fast: in production a missing required var
 * aborts boot rather than 500-ing at request time.
 *
 * Residency note (SPAN_MASTER_PLAN §1.2 / §9): the whole product is India-only.
 * Defaults pin storage to ap-south-1 and inference to asia-south1; nothing here
 * may default to a global/cross-region endpoint.
 */

import { z } from 'zod';

// ---------------------------------------------------------------------------
// Schema.  Required-ness is conditional on NODE_ENV: in development/test we
// allow soft defaults so a contributor can boot without a full AWS/Apple setup;
// in production every PHI-touching var is mandatory.
// ---------------------------------------------------------------------------

const NodeEnv = z.enum(['development', 'test', 'production']);

const rawSchema = z.object({
  NODE_ENV: NodeEnv.default('development'),

  // Network
  PORT: z.coerce.number().int().positive().max(65_535).default(8080),

  // Database — consumed by src/db (which reads PG* vars directly); we accept a
  // single DATABASE_URL too so deploys can use either form.
  DATABASE_URL: z.string().url().optional(),

  // AWS / residency (India-only).  These MUST stay in-region.
  AWS_REGION: z.string().min(1).default('ap-south-1'),
  S3_BUCKET: z.string().min(1).optional(),
  SQS_QUEUE_URL: z.string().url().optional(),
  KMS_KEY_ID: z.string().min(1).optional(),

  // Sign in with Apple — `aud` we verify the Apple identity_token against.
  APPLE_CLIENT_ID: z.string().min(1).optional(),

  // Secret used to sign OUR access JWTs (NOT Apple's).  Must be strong in prod.
  JWT_SECRET: z.string().min(1).optional(),
});

type RawEnv = z.infer<typeof rawSchema>;

/**
 * Vars that are optional in dev/test but REQUIRED in production.  Listed once so
 * the fail-fast check and the docs stay in sync.
 */
const REQUIRED_IN_PROD = [
  'DATABASE_URL',
  'S3_BUCKET',
  'SQS_QUEUE_URL',
  'KMS_KEY_ID',
  'APPLE_CLIENT_ID',
  'JWT_SECRET',
] as const satisfies readonly (keyof RawEnv)[];

function loadConfig(env: NodeJS.ProcessEnv): Readonly<RawEnv & { isProduction: boolean }> {
  const parsed = rawSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  - ${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('\n');
    throw new Error(`[config] invalid environment:\n${issues}`);
  }

  const value = parsed.data;
  const isProduction = value.NODE_ENV === 'production';

  if (isProduction) {
    const missing = REQUIRED_IN_PROD.filter((k) => value[k] === undefined || value[k] === '');
    if (missing.length > 0) {
      throw new Error(
        `[config] missing required production env vars: ${missing.join(', ')}. ` +
          'Refusing to boot — PHI endpoints would be insecure or non-functional.',
      );
    }
    // Reject a weak / placeholder JWT secret in prod.
    if ((value.JWT_SECRET ?? '').length < 32) {
      throw new Error('[config] JWT_SECRET must be at least 32 chars in production.');
    }
    // Residency guard: India-only deployment must not be pointed at another region.
    if (value.AWS_REGION !== 'ap-south-1') {
      throw new Error(
        `[config] AWS_REGION must be 'ap-south-1' (India-only residency); got '${value.AWS_REGION}'.`,
      );
    }
  }

  return Object.freeze({ ...value, isProduction });
}

/** Frozen, validated config.  Import this everywhere — never read process.env directly. */
export const config = loadConfig(process.env);

export type Config = typeof config;

// A non-secret development fallback for the JWT secret so local boot works.
// In production loadConfig() guarantees JWT_SECRET is present and strong.
export const jwtSecret: string =
  config.JWT_SECRET ?? 'dev-only-insecure-jwt-secret-change-me-1234567890';

// Stable residency constants — every PHI row is pinned to these (§9).
export const RESIDENCY = Object.freeze({
  region: 'in' as const,
  storageGeo: 'ap-south-1' as const,
  inferenceGeo: 'asia-south1' as const,
});
