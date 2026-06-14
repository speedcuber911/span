/**
 * Defensive config accessor for the LLM + VOICE layers.
 *
 * The master plan says config lives in '../config.js'. That module may not
 * exist yet (it's owned by another track), so we read it OPTIONALLY via a
 * dynamic import and fall back to process.env. This keeps llm/ + voice/
 * compilable and runnable in isolation (incl. mock mode with no creds).
 *
 * HARD RULE (SPAN_MASTER_PLAN §1.1): Vertex / Document AI inference MUST stay
 * in asia-south1. VERTEX_LOCATION is pinned and the regional apiEndpoint is
 * derived from it; we never allow a global/default endpoint.
 */

export const VERTEX_LOCATION = 'asia-south1' as const;
export const VERTEX_API_ENDPOINT = 'asia-south1-aiplatform.googleapis.com' as const;
export const DOCUMENTAI_API_ENDPOINT = 'asia-south1-documentai.googleapis.com' as const;
/** S3 region for raw PHI bytes (SPAN_MASTER_PLAN §1.2). */
export const S3_REGION = 'ap-south-1' as const;

export interface SpanConfig {
  // Vertex / Document AI
  VERTEX_PROJECT?: string;
  VERTEX_LOCATION: string;
  GOOGLE_APPLICATION_CREDENTIALS?: string;
  DOCUMENTAI_PROCESSOR_ID?: string;
  DOCUMENTAI_PROCESSOR_LOCATION?: string;
  GEMINI_MODEL: string;
  // S3
  S3_REGION: string;
  S3_BUCKET?: string;
  // Sarvam (voice)
  SARVAM_API_KEY?: string;
  SARVAM_BASE_URL: string;
  // modes
  LLM_MODE: 'mock' | 'live';
  VOICE_MODE: 'mock' | 'live';
}

let cached: SpanConfig | undefined;
let externalConfig: Record<string, unknown> | undefined;
let externalLoaded = false;

/**
 * Optionally pull a shared config object from '../config.js' if that module
 * exists and exports a config-shaped object. Never throws.
 */
async function loadExternalConfig(): Promise<Record<string, unknown> | undefined> {
  if (externalLoaded) return externalConfig;
  externalLoaded = true;
  try {
    // Indirect specifier so tsc does not try to statically resolve a module
    // that may not exist yet.
    const spec = '../config.js';
    const mod = (await import(spec)) as Record<string, unknown>;
    const candidate =
      (mod.config as Record<string, unknown> | undefined) ??
      (mod.default as Record<string, unknown> | undefined) ??
      mod;
    externalConfig = candidate;
  } catch {
    externalConfig = undefined;
  }
  return externalConfig;
}

function pick(
  ext: Record<string, unknown> | undefined,
  key: string,
): string | undefined {
  const fromExt = ext?.[key];
  if (typeof fromExt === 'string' && fromExt.length > 0) return fromExt;
  const fromEnv = process.env[key];
  if (typeof fromEnv === 'string' && fromEnv.length > 0) return fromEnv;
  return undefined;
}

/**
 * Resolve config once, merging the optional shared config with process.env.
 * Safe to call repeatedly (memoized). Asynchronous because the optional
 * '../config.js' lookup is dynamic.
 */
export async function getConfig(): Promise<SpanConfig> {
  if (cached) return cached;
  const ext = await loadExternalConfig();

  const llmModeRaw = pick(ext, 'SPAN_LLM_MODE');
  const voiceModeRaw = pick(ext, 'SPAN_VOICE_MODE');

  cached = {
    VERTEX_PROJECT: pick(ext, 'VERTEX_PROJECT'),
    // Always pinned to asia-south1 — never read a different location.
    VERTEX_LOCATION,
    GOOGLE_APPLICATION_CREDENTIALS: pick(ext, 'GOOGLE_APPLICATION_CREDENTIALS'),
    DOCUMENTAI_PROCESSOR_ID: pick(ext, 'DOCUMENTAI_PROCESSOR_ID'),
    DOCUMENTAI_PROCESSOR_LOCATION:
      pick(ext, 'DOCUMENTAI_PROCESSOR_LOCATION') ?? 'asia-south1',
    GEMINI_MODEL: pick(ext, 'GEMINI_MODEL') ?? 'gemini-1.5-pro',
    S3_REGION,
    S3_BUCKET: pick(ext, 'S3_BUCKET'),
    SARVAM_API_KEY: pick(ext, 'SARVAM_API_KEY'),
    SARVAM_BASE_URL: pick(ext, 'SARVAM_BASE_URL') ?? 'https://api.sarvam.ai',
    LLM_MODE: llmModeRaw === 'mock' ? 'mock' : 'live',
    VOICE_MODE: voiceModeRaw === 'mock' ? 'mock' : 'live',
  };
  return cached;
}

/** Test/seam helper — reset memoized config (used by tests). */
export function __resetConfigCache(): void {
  cached = undefined;
  externalConfig = undefined;
  externalLoaded = false;
}
