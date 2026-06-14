/**
 * parseReport — the contract the ingestion worker calls.
 *
 *   parseReport(s3Key, hint) -> ExtractedReport
 *
 * Pipeline (SPAN_MASTER_PLAN §5):
 *   1. fetch bytes from S3 (ap-south-1)
 *   2. Document AI OCR (asia-south1) -> text + tables grounding
 *   3. Gemini emit_lab_report with SELF-CONSISTENCY N=3 — run 3 passes, agree
 *      per-field, disagreement lowers that row's confidence.
 *
 * The LLM TRANSCRIBES ONLY: no unit conversion, no canonicalization, no
 * invented ranges, no diagnosis. That determinism lives downstream.
 *
 * MOCK MODE: set SPAN_LLM_MODE=mock to return a small canned ExtractedReport
 * with no GCP/AWS creds — so the worker + tests run today.
 */

import { getConfig } from './config.js';
import { ParseError, type ExtractedReport, type ExtractedRow, type ParseHint } from './types.js';
import { ocrDocument } from './documentai.js';
import { emitLabReport, type GeminiGrounding } from './gemini.js';

const SELF_CONSISTENCY_N = 3;

// ── byte fetching ─────────────────────────────────────────────────────────────
export type ByteFetcher = (s3Key: string) => Promise<Uint8Array>;

// minimal structural types for @aws-sdk/client-s3 (lazy import)
interface S3GetCommandCtor {
  new (input: { Bucket: string; Key: string }): unknown;
}
interface S3Body {
  transformToByteArray?(): Promise<Uint8Array>;
}
interface S3GetOutput {
  Body?: S3Body;
}
interface S3ClientLike {
  send(cmd: unknown): Promise<S3GetOutput>;
}
interface S3ClientCtor {
  new (opts: { region: string }): S3ClientLike;
}

let s3Promise: Promise<{ client: S3ClientLike; Get: S3GetCommandCtor; bucket: string }> | undefined;

async function defaultFetchBytes(s3Key: string): Promise<Uint8Array> {
  if (!s3Promise) {
    s3Promise = (async () => {
      const cfg = await getConfig();
      if (!cfg.S3_BUCKET) {
        throw new ParseError('config', 'S3_BUCKET is not configured.');
      }
      let mod: { S3Client: S3ClientCtor; GetObjectCommand: S3GetCommandCtor };
      try {
        const spec = '@aws-sdk/client-s3';
        mod = (await import(spec)) as unknown as {
          S3Client: S3ClientCtor;
          GetObjectCommand: S3GetCommandCtor;
        };
      } catch (err) {
        throw new ParseError('config', '@aws-sdk/client-s3 is not installed.', err);
      }
      return {
        client: new mod.S3Client({ region: cfg.S3_REGION }),
        Get: mod.GetObjectCommand,
        bucket: cfg.S3_BUCKET,
      };
    })();
  }
  const { client, Get, bucket } = await s3Promise;
  let out: S3GetOutput;
  try {
    out = await client.send(new Get({ Bucket: bucket, Key: s3Key }));
  } catch (err) {
    throw new ParseError('fetch', `S3 GetObject failed for key ${s3Key}.`, err);
  }
  const body = out.Body;
  if (!body?.transformToByteArray) {
    throw new ParseError('fetch', `S3 object ${s3Key} had no readable body.`);
  }
  return body.transformToByteArray();
}

// ── retry helper ──────────────────────────────────────────────────────────────
async function withRetry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      // ConfigError / config-coded errors are not retryable.
      if (err instanceof ParseError && err.code === 'config') throw err;
      if (i < attempts - 1) {
        await new Promise((r) => setTimeout(r, 100 * 2 ** i));
      }
    }
  }
  throw lastErr instanceof Error
    ? lastErr
    : new ParseError('unknown', 'retry exhausted', lastErr);
}

// ── self-consistency merge ────────────────────────────────────────────────────
function rowKey(r: ExtractedRow): string {
  // Group by the raw parameter name (lowercased, trimmed) — the only stable
  // anchor before canonicalization.
  return r.parameter_raw.trim().toLowerCase();
}

function mode<T>(vals: T[]): { value: T; agreement: number } {
  const counts = new Map<string, { value: T; n: number }>();
  for (const v of vals) {
    const k = JSON.stringify(v);
    const cur = counts.get(k);
    if (cur) cur.n += 1;
    else counts.set(k, { value: v, n: 1 });
  }
  let best: { value: T; n: number } | undefined;
  for (const c of counts.values()) {
    if (!best || c.n > best.n) best = c;
  }
  const chosen = best ?? { value: vals[0] as T, n: 1 };
  return { value: chosen.value, agreement: chosen.n / vals.length };
}

/**
 * Merge N transcriptions into one, per-field majority vote. Per-row confidence
 * is the original mean confidence scaled by the field-level agreement ratio —
 * so disagreement across passes lowers that row's confidence.
 */
export function mergeSelfConsistency(reports: ExtractedReport[]): ExtractedReport {
  if (reports.length === 0) {
    return { lab: null, report_date: null, rows: [] };
  }
  if (reports.length === 1) return reports[0] as ExtractedReport;

  const lab = mode(reports.map((r) => r.lab)).value;
  const report_date = mode(reports.map((r) => r.report_date)).value;

  // Collect each row keyed by raw parameter across all passes.
  const byKey = new Map<string, ExtractedRow[]>();
  for (const rep of reports) {
    for (const row of rep.rows) {
      const k = rowKey(row);
      const arr = byKey.get(k) ?? [];
      arr.push(row);
      byKey.set(k, arr);
    }
  }

  const merged: ExtractedRow[] = [];
  for (const variants of byKey.values()) {
    const v0 = variants[0] as ExtractedRow;
    const fieldAgreements: number[] = [];
    const pickField = <K extends keyof ExtractedRow>(key: K): ExtractedRow[K] => {
      const { value, agreement } = mode(variants.map((x) => x[key]));
      fieldAgreements.push(agreement);
      return value;
    };
    const parameter_raw = pickField('parameter_raw');
    const value_text = pickField('value_text');
    const value_numeric = pickField('value_numeric');
    const value_operator = pickField('value_operator');
    const unit_raw = pickField('unit_raw');
    const ref_text = pickField('ref_text');
    const ref_low = pickField('ref_low');
    const ref_high = pickField('ref_high');
    const flag_printed = pickField('flag_printed');

    // How many of the N passes saw this row at all (presence agreement).
    const presence = variants.length / reports.length;
    const meanConf =
      variants.reduce((s, x) => s + x.confidence, 0) / variants.length;
    const fieldAgreement =
      fieldAgreements.reduce((s, x) => s + x, 0) / fieldAgreements.length;
    const confidence = Math.max(
      0,
      Math.min(1, meanConf * fieldAgreement * presence),
    );

    merged.push({
      parameter_raw,
      value_text,
      value_numeric,
      value_operator,
      unit_raw,
      ref_text,
      ref_low,
      ref_high,
      flag_printed,
      confidence: Number(confidence.toFixed(4)),
    });
    void v0;
  }

  return { lab, report_date, rows: merged };
}

// ── mock report ───────────────────────────────────────────────────────────────
/**
 * A small canned ExtractedReport for offline/mock mode. Deliberately exercises
 * the transcribe-only invariants the worker/tests check:
 *   - a censored "<200" row (value_operator '<', no unit conversion)
 *   - a non-numeric "Negative" row
 *   - raw units left untouched (ng/mL, mg/dL)
 */
export function mockExtractedReport(hint?: ParseHint): ExtractedReport {
  return {
    lab: hint?.lab_guess ?? 'Tata 1mg Labs',
    report_date: '2026-05-01',
    rows: [
      {
        parameter_raw: 'HbA1c',
        value_text: '5.4',
        value_numeric: 5.4,
        value_operator: '=',
        unit_raw: '%',
        ref_text: '4.0 - 5.6',
        ref_low: 4.0,
        ref_high: 5.6,
        flag_printed: 'Normal',
        confidence: 0.97,
      },
      {
        parameter_raw: 'Triglycerides',
        value_text: '<200',
        value_numeric: 200,
        value_operator: '<',
        unit_raw: 'mg/dL',
        ref_text: '<150',
        ref_low: null,
        ref_high: 150,
        flag_printed: null,
        confidence: 0.9,
      },
      {
        parameter_raw: 'Vitamin B-12',
        value_text: '412',
        value_numeric: 412,
        value_operator: '=',
        unit_raw: 'pg/mL',
        ref_text: '211 - 911',
        ref_low: 211,
        ref_high: 911,
        flag_printed: 'Normal',
        confidence: 0.93,
      },
      {
        parameter_raw: 'Dengue NS1 Antigen',
        value_text: 'Negative',
        value_numeric: null,
        value_operator: '=',
        unit_raw: null,
        ref_text: 'Negative',
        ref_low: null,
        ref_high: null,
        flag_printed: null,
        confidence: 0.95,
      },
    ],
  };
}

// ── grounding assembly ────────────────────────────────────────────────────────
function tablesToText(tables: Awaited<ReturnType<typeof ocrDocument>>['tables']): string {
  return tables
    .map((t, i) => {
      const renderRow = (cells: { text: string }[]) =>
        cells.map((c) => c.text).join(' | ');
      const head = t.headerRows.map(renderRow).join('\n');
      const body = t.bodyRows.map(renderRow).join('\n');
      return `# table ${i + 1}\n${head}\n${body}`.trim();
    })
    .join('\n\n');
}

function hintToText(hint?: ParseHint): string | undefined {
  if (!hint) return undefined;
  const bits: string[] = [];
  if (hint.lab_guess) bits.push(`lab_guess=${hint.lab_guess}`);
  if (hint.sender_domain) bits.push(`sender=${hint.sender_domain}`);
  if (hint.original_filename) bits.push(`file=${hint.original_filename}`);
  return bits.length ? bits.join(', ') : undefined;
}

// ── the public contract ───────────────────────────────────────────────────────
export interface ParseOptions {
  /** Override byte fetching (e.g. worker already holds the bytes in-region). */
  fetchBytes?: ByteFetcher;
  /** Override mode regardless of env (mainly for tests). */
  mode?: 'mock' | 'live';
  /** Override self-consistency N (default 3). */
  n?: number;
}

/**
 * parseReport — fetch the artifact, OCR it, and transcribe it with Gemini under
 * self-consistency N=3. Returns the worker-facing ExtractedReport.
 *
 * @param s3Key  the S3 object key for the raw artifact
 * @param hint   optional ingestion hint (lab guess / filename / sender)
 */
export async function parseReport(
  s3Key: string,
  hint?: ParseHint,
  options: ParseOptions = {},
): Promise<ExtractedReport> {
  const cfg = await getConfig();
  const mode = options.mode ?? cfg.LLM_MODE;

  if (mode === 'mock') {
    return mockExtractedReport(hint);
  }

  // 1. fetch bytes
  const fetcher = options.fetchBytes ?? defaultFetchBytes;
  const bytes = await withRetry(() => fetcher(s3Key));
  if (!bytes || bytes.length === 0) {
    throw new ParseError('fetch', `Artifact ${s3Key} was empty.`);
  }

  // 2. Document AI OCR (asia-south1)
  const ocr = await withRetry(() =>
    ocrDocument({ bytes, mimeType: hint?.mime_type }),
  );

  const grounding: GeminiGrounding = {
    ocrText: ocr.text,
    tableText: ocr.tables.length ? tablesToText(ocr.tables) : undefined,
    hintText: hintToText(hint),
  };

  // 3. Gemini emit_lab_report — self-consistency N passes.
  const n = Math.max(1, options.n ?? SELF_CONSISTENCY_N);
  const passes: ExtractedReport[] = [];
  for (let i = 0; i < n; i++) {
    const rep = await withRetry(() => emitLabReport(grounding));
    passes.push(rep);
  }

  const merged = mergeSelfConsistency(passes);
  if (merged.rows.length === 0) {
    throw new ParseError('empty', `No rows extracted from ${s3Key}.`);
  }
  return merged;
}
