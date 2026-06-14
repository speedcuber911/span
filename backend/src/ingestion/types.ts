/**
 * Project Span — Ingestion + Worker shared types.
 *
 * This module owns the wire contracts that cross component boundaries:
 *   - the HTTP request/response shapes for the ingestion API,
 *   - the SQS FIFO queue message shapes (ingestion.parse.requested /
 *     ingestion.parse.completed) — see SPAN_MASTER_PLAN.md §4,
 *   - the `ExtractedReport` interface returned by the LLM parse layer
 *     (`src/llm/parse.ts`) — the contract with `src/llm`. This file is the
 *     single source of truth both sides agree on (§5 LLM tool-schema contract).
 *
 * NB: at launch every PHI row is region='in', storage_geo='ap-south-1',
 * inference_geo='asia-south1' (DPDP, India-only). The fields are modeled
 * generically so a future EU box is additive, not a rewrite.
 */

// ── Residency primitives ────────────────────────────────────────────────────

/** Live region at launch is 'in'; 'eu' reserved for a future additive box. */
export type Region = 'in' | 'eu';

/** Vertex inference geo pin. India → 'asia-south1'. */
export type InferenceGeo = 'asia-south1' | 'europe-west3';

/** Where an artifact came from (matches ingestion_artifacts.source CHECK). */
export type IngestionSource = 'folder' | 'photo' | 'gmail';

/** ingestion_jobs.status FSM — mirrors the migration CHECK constraint exactly. */
export type JobStatus =
  | 'intent_created'
  | 'uploading'
  | 'uploaded'
  | 'enqueued'
  | 'parsing'
  | 'needs_review'
  | 'extracted'
  | 'committed'
  | 'failed'
  | 'duplicate'
  | 'quarantined';

/** Outbox topics this component publishes. */
export type OutboxTopic =
  | 'ingestion.parse.requested'
  | 'ingestion.parse.completed'
  | 'measurements.committed';

/** Bump when any queue payload shape below changes (consumers branch on it). */
export const SCHEMA_VERSION = 1 as const;
export type SchemaVersion = typeof SCHEMA_VERSION;

// ── HTTP: POST /v1/ingestion/intents ────────────────────────────────────────

/** One file the client wants to upload, in a batch intent request. */
export interface IngestionIntentFile {
  filename: string;
  mime_type: string;
  byte_size: number;
  /** Lowercase hex SHA-256 of the file bytes (64 chars) — drives exact dedup. */
  content_sha256: string;
  source: IngestionSource;
}

/** Body of POST /v1/ingestion/intents — a batch of files. */
export interface IngestionIntentRequest {
  files: IngestionIntentFile[];
  /** Optional client idempotency key per logical batch action (24h replay). */
  idempotency_key?: string;
}

/** Per-file dedup outcome. */
export type IntentVerdict = 'new' | 'duplicate';

/** Presigned S3 PUT instruction for a 'new' artifact. */
export interface PresignedUpload {
  url: string;
  method: 'PUT';
  /** Headers the client MUST echo on the PUT (SSE-KMS binding, content type). */
  headers: Record<string, string>;
  expires_at: string; // ISO8601
}

/** One result row in the intents response, 1:1 with the request files[]. */
export interface IngestionIntentResult {
  artifact_id: string;
  job_id: string;
  verdict: IntentVerdict;
  content_sha256: string;
  /** Present only when verdict === 'new'. Duplicates resolve to existing rows. */
  upload?: PresignedUpload;
}

export interface IngestionIntentResponse {
  results: IngestionIntentResult[];
}

// ── HTTP: GET /v1/ingestion/jobs ────────────────────────────────────────────

export interface IngestionJobView {
  job_id: string;
  artifact_id: string;
  status: JobStatus;
  progress_pct: number | null;
  error_code: string | null;
  source: IngestionSource | null;
  original_filename: string | null;
  created_at: string;
  updated_at: string;
}

// ── Queue: ingestion.parse.requested ────────────────────────────────────────

/** Storage locator carried on every parse message. */
export interface StorageRef {
  bucket: string;
  key: string;
  kms_key_id: string;
}

/** Hints passed to the LLM parse (never authoritative; transcribe-only). */
export interface ParseHint {
  sender_domain?: string;
  lab_guess?: string;
  original_filename?: string;
}

/**
 * ingestion.parse.requested — emitted (via outbox→SQS) when a job is enqueued.
 * MessageGroupId = user_id, MessageDeduplicationId = artifact_id.
 */
export interface ParseRequestedMessage {
  schema_version: SchemaVersion;
  topic: 'ingestion.parse.requested';
  job_id: string;
  artifact_id: string;
  user_id: string;
  region: Region;
  inference_geo: InferenceGeo;
  storage: StorageRef;
  source: IngestionSource;
  mime_type: string | null;
  page_count?: number | null;
  content_sha256: string;
  hint: ParseHint;
}

// ── Queue: ingestion.parse.completed ────────────────────────────────────────

/** Terminal outcome of a parse job (drives the app progress UX). */
export type ParseOutcome = 'extracted' | 'needs_review' | 'failed';

export interface ParseCompletedMessage {
  schema_version: SchemaVersion;
  topic: 'ingestion.parse.completed';
  job_id: string;
  artifact_id: string;
  user_id: string;
  region: Region;
  report_id: string | null;
  outcome: ParseOutcome;
  measurements_committed: number;
  review_count: number;
  error_code?: string | null;
}

/**
 * measurements.committed — tells the analysis layer to recompute trends/scores.
 * Also keyed MessageGroupId = user_id for per-user ordering + debounce (§7).
 */
export interface MeasurementsCommittedMessage {
  schema_version: SchemaVersion;
  topic: 'measurements.committed';
  user_id: string;
  region: Region;
  report_id: string;
  artifact_id: string;
  measurement_ids: string[];
}

// ── LLM contract: ExtractedReport (the src/llm/parse.ts return shape) ────────

export type ValueOperator = '=' | '<' | '>' | '<=' | '>=';

/**
 * One transcribed row from the LLM. The LLM TRANSCRIBES ONLY — it never
 * converts units, canonicalizes names, invents ranges, or picks categories
 * (SPAN_MASTER_PLAN.md §5). All determinism happens in worker/postprocess.ts.
 */
export interface ExtractedRow {
  /** Parameter name exactly as printed (e.g. "Hb A1c", "T3, Total"). */
  parameter_raw: string;
  /** Verbatim printed value, incl. 'Negative', '<200', '> 24', 'Trace'. */
  value_text: string;
  /** Parsed numeric value if cleanly numeric, else null. */
  value_numeric: number | null;
  /** Censoring operator if the printed value carried one ('<200' → '<'). */
  value_operator: ValueOperator | null;
  /** Unit string exactly as printed (e.g. "mg/dL", "ng/mL"). */
  unit_raw: string | null;
  /** Reference-range text exactly as printed (e.g. "3.5-5.0", "<200 IU/ml"). */
  ref_text: string | null;
  /** Reference low bound ONLY if cleanly printed as a number, else null. */
  ref_low: number | null;
  /** Reference high bound ONLY if cleanly printed as a number, else null. */
  ref_high: number | null;
  /** Flag exactly as printed by the lab ('H', 'L', 'High', etc.), else null. */
  flag_printed: string | null;
  /** Per-row extraction confidence in [0,1]. */
  confidence: number;
  /** Optional bbox lineage {page,x,y,w,h} from Document AI. */
  bbox?: Record<string, number> | null;
}

/** The full document the LLM parse returns. Contract with src/llm/parse.ts. */
export interface ExtractedReport {
  /** Lab name as printed/inferred (e.g. "Thyrocare"), or null. */
  lab: string | null;
  /** Report/collection date as ISO 'YYYY-MM-DD', or null if not printed. */
  report_date: string | null;
  rows: ExtractedRow[];
  /** Optional overall document-level confidence in [0,1]. */
  doc_confidence?: number;
}

/**
 * The function signature `src/llm/parse.ts` is expected to export.
 * The worker imports it defensively (dynamic import in try/catch) so this
 * package compiles before the llm agent lands the implementation.
 */
export type ParseReportFn = (
  s3Key: string,
  hint: ParseHint,
) => Promise<ExtractedReport>;
