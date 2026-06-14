/**
 * Deterministic post-processing of an ExtractedReport (SPAN_MASTER_PLAN.md §5,
 * STAGE 3). This is PURE CODE — NO LLM. The LLM transcribes only; everything
 * that could silently corrupt a trend (unit conversion, canonicalization,
 * range parsing, flagging, outlier rejection) happens here, testably.
 *
 * Pipeline per row:
 *   3a canonicalize parameter  (alias / regex → canonical_param_id)
 *   3b normalize unit          (unit_rules; NEVER auto-convert nonlinear_blocked)
 *   3c parse reference range   (ref_low/high + sex/age qualifier)
 *   3d category                (from the dictionary, never the LLM)
 *   3e flag                    (trust printed lab flag, else derive from bounds)
 *   3f outlier guard           (plausibility window → value=null, keep value_text)
 *   3g dedup                   (collapse identical canonical+date, union sources)
 *
 * The dictionary tables (canonical_parameters, unit_rules) are loaded once and
 * cached — see loadDictionary().
 */

import type pg from 'pg';
import type { ExtractedReport, ExtractedRow, ValueOperator } from '../ingestion/types.js';

// ── Dictionary types (subset of the canonical_parameters / unit_rules columns) ─

export type ConversionKind =
  | 'identity'
  | 'alias'
  | 'linear'
  | 'scale'
  | 'nonlinear_blocked';

export interface UnitRule {
  canonical_param_id: string;
  raw_unit_normalized: string;
  conversion_kind: ConversionKind;
  factor: number | null;
  offset: number | null;
  guard_min: number | null;
  guard_max: number | null;
  note: string | null;
}

export interface CanonicalParam {
  canonical_param_id: string;
  display_name: string;
  loinc_code: string | null;
  category: string;
  canonical_unit: string;
  plausibility_low: number | null;
  plausibility_high: number | null;
  default_ref_low: number | null;
  default_ref_high: number | null;
  aliases: string[];
  alias_regexes: string[];
}

export interface Dictionary {
  params: CanonicalParam[];
  /** canonical_param_id → (raw_unit_normalized → rule) */
  unitRules: Map<string, Map<string, UnitRule>>;
  /** normalized alias string → canonical_param_id (exact alias match) */
  aliasIndex: Map<string, string>;
  /** compiled regex alias → canonical_param_id (ordered) */
  regexIndex: Array<{ re: RegExp; id: string }>;
  catalogVersion: number;
}

// ── Output shape (a ready-to-upsert measurement draft) ──────────────────────

export type MeasurementFlag = 'High' | 'Low' | 'Normal';

export interface ProcessedMeasurement {
  parameter: string; // canonical display name (drives search)
  parameter_raw: string;
  category: string | null;
  canonical_param_id: string | null;
  loinc_code: string | null;
  value: number | null;
  value_text: string;
  value_operator: ValueOperator | null;
  unit: string | null; // normalized/canonical unit
  unit_raw: string | null;
  ref_low: number | null;
  ref_high: number | null;
  ref_text: string | null;
  ref_qualifier: Record<string, unknown> | null;
  flag: MeasurementFlag | null;
  field_confidence: Record<string, unknown> | null;
  /** Reasons this row needs human review (low conf, outlier, unmapped, …). */
  review_reasons: string[];
  /** True when the unit conversion was blocked (kept raw + flagged). */
  unit_blocked: boolean;
}

export interface PostprocessResult {
  lab: string | null;
  report_date: string | null;
  measurements: ProcessedMeasurement[];
  /** Any row with review_reasons present → job becomes needs_review. */
  needsReview: boolean;
}

export interface PostprocessOptions {
  /** Rows with confidence below this go to review (default 0.60). */
  reviewConfidence?: number;
  /** Rows at/above this are confidently auto-accepted (default 0.90). */
  autoAcceptConfidence?: number;
}

// ── Dictionary loading + cache ──────────────────────────────────────────────

let _cache: Dictionary | null = null;

function normUnit(u: string | null | undefined): string {
  return (u ?? '').trim().toLowerCase();
}

function normAlias(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Build the in-memory indices from raw rows (also used by tests w/ fixtures). */
export function buildDictionary(
  params: CanonicalParam[],
  rules: UnitRule[],
  catalogVersion = 1,
): Dictionary {
  const unitRules = new Map<string, Map<string, UnitRule>>();
  for (const r of rules) {
    let m = unitRules.get(r.canonical_param_id);
    if (!m) {
      m = new Map();
      unitRules.set(r.canonical_param_id, m);
    }
    m.set(normUnit(r.raw_unit_normalized), r);
  }

  const aliasIndex = new Map<string, string>();
  const regexIndex: Array<{ re: RegExp; id: string }> = [];
  for (const p of params) {
    aliasIndex.set(normAlias(p.display_name), p.canonical_param_id);
    for (const a of p.aliases ?? []) aliasIndex.set(normAlias(a), p.canonical_param_id);
    for (const rx of p.alias_regexes ?? []) {
      try {
        regexIndex.push({ re: new RegExp(rx, 'i'), id: p.canonical_param_id });
      } catch {
        /* skip malformed regex in the dictionary */
      }
    }
  }

  return { params, unitRules, aliasIndex, regexIndex, catalogVersion };
}

/** Load the dictionary from the DB once and cache it (non-PHI tables). */
export async function loadDictionary(
  client: Pick<pg.PoolClient, 'query'>,
  force = false,
): Promise<Dictionary> {
  if (_cache && !force) return _cache;

  const paramsRes = await client.query<CanonicalParam>(
    `SELECT canonical_param_id, display_name, loinc_code, category, canonical_unit,
            plausibility_low, plausibility_high, default_ref_low, default_ref_high,
            aliases, alias_regexes
       FROM canonical_parameters`,
  );
  const rulesRes = await client.query<UnitRule>(
    `SELECT canonical_param_id, raw_unit_normalized, conversion_kind,
            factor, "offset", guard_min, guard_max, note
       FROM unit_rules`,
  );

  _cache = buildDictionary(paramsRes.rows, rulesRes.rows, 1);
  return _cache;
}

/** Test/ops hook: install a dictionary directly and clear it. */
export function setDictionaryCache(d: Dictionary | null): void {
  _cache = d;
}

// ── 3a canonicalization ─────────────────────────────────────────────────────

export function canonicalize(
  parameterRaw: string,
  dict: Dictionary,
): CanonicalParam | null {
  const key = normAlias(parameterRaw);
  const id = dict.aliasIndex.get(key);
  if (id) return dict.params.find((p) => p.canonical_param_id === id) ?? null;
  for (const { re, id: rid } of dict.regexIndex) {
    if (re.test(parameterRaw)) {
      return dict.params.find((p) => p.canonical_param_id === rid) ?? null;
    }
  }
  return null;
}

// ── 3b unit normalization ───────────────────────────────────────────────────

export interface NormalizedUnit {
  value: number | null;
  unit: string | null;
  blocked: boolean;
  note?: string;
}

/**
 * Normalize a raw value+unit to the canonical unit via unit_rules.
 *   identity / alias → value unchanged, unit := canonical
 *   linear / scale   → value := value*factor + offset; guard window applied
 *   nonlinear_blocked→ value KEPT RAW (no conversion), unit KEPT RAW, blocked=true
 *   (no rule)        → value/unit kept as-is, not blocked (caller may review)
 */
export function normalizeUnit(
  value: number | null,
  rawUnit: string | null,
  param: CanonicalParam | null,
  dict: Dictionary,
): NormalizedUnit {
  if (!param) return { value, unit: rawUnit, blocked: false };
  const rules = dict.unitRules.get(param.canonical_param_id);
  const rule = rules?.get(normUnit(rawUnit));

  if (!rule) {
    // Unknown unit for a known param: keep as-is, leave canonical unit unset so
    // the caller can flag unit_ambiguous if it matters.
    return { value, unit: rawUnit ?? param.canonical_unit, blocked: false };
  }

  switch (rule.conversion_kind) {
    case 'nonlinear_blocked':
      // e.g. Lp(a) mg/dL ⇄ nmol/L — the conversion is contested/non-linear.
      // Keep the RAW value and RAW unit; flag for review. NEVER auto-convert.
      return {
        value,
        unit: rawUnit,
        blocked: true,
        note: rule.note ?? 'nonlinear conversion blocked',
      };

    case 'identity':
    case 'alias':
      return { value, unit: param.canonical_unit, blocked: false };

    case 'linear':
    case 'scale': {
      if (value === null) return { value: null, unit: param.canonical_unit, blocked: false };
      const factor = rule.factor ?? 1;
      const offset = rule.offset ?? 0;
      const converted = value * factor + offset;
      return { value: converted, unit: param.canonical_unit, blocked: false };
    }

    default:
      return { value, unit: rawUnit ?? param.canonical_unit, blocked: false };
  }
}

// ── 3c reference-range parsing ──────────────────────────────────────────────

export interface ParsedRef {
  ref_low: number | null;
  ref_high: number | null;
  ref_qualifier: Record<string, unknown> | null;
}

const NUM = '[-+]?\\d*\\.?\\d+';

/**
 * Parse a printed reference-range string into low/high bounds + a sex/age
 * qualifier. Handles: '3.5-5.0', '[8.00-23.00]', '<200', '> 24',
 * 'Negative < 25', 'Male > 51 Years: 56 - 119', 'up to 40'.
 */
export function parseRefRange(refText: string | null): ParsedRef {
  const out: ParsedRef = { ref_low: null, ref_high: null, ref_qualifier: null };
  if (!refText) return out;
  const t = refText.trim();

  // Sex / age qualifier (kept for the analysis layer to apply correctly).
  const qualifier: Record<string, unknown> = {};
  const sexM = /\b(male|female|men|women|m|f)\b/i.exec(t);
  if (sexM) {
    const s = sexM[1]!.toLowerCase();
    qualifier.sex = s.startsWith('m') ? 'male' : 'female';
  }
  const ageGt = /(?:>|over|above)\s*(\d+)\s*(?:years|yrs|y)\b/i.exec(t);
  if (ageGt) qualifier.age_gt = Number(ageGt[1]);
  const ageLt = /(?:<|under|below)\s*(\d+)\s*(?:years|yrs|y)\b/i.exec(t);
  if (ageLt) qualifier.age_lt = Number(ageLt[1]);

  // Strip a leading "label:" so "Male > 51 Years: 56 - 119" parses its range.
  const afterColon = t.includes(':') ? t.slice(t.lastIndexOf(':') + 1).trim() : t;

  // 1) explicit low-high range  (a - b)  — most common.
  const range = new RegExp(`(${NUM})\\s*(?:-|–|to)\\s*(${NUM})`).exec(afterColon);
  if (range) {
    out.ref_low = Number(range[1]);
    out.ref_high = Number(range[2]);
  } else {
    // 2) single-bound forms — but ignore an age clause we already consumed.
    const ageClause = /(?:years|yrs|y)\b/i.test(afterColon);
    const upper = new RegExp(`(?:<|<=|up to|upto|less than|max(?:imum)?)\\s*(${NUM})`, 'i').exec(
      afterColon,
    );
    const lower = new RegExp(`(?:>|>=|greater than|min(?:imum)?|at least)\\s*(${NUM})`, 'i').exec(
      afterColon,
    );
    if (upper && !ageClause) out.ref_high = Number(upper[1]);
    if (lower && !ageClause) out.ref_low = Number(lower[1]);
  }

  if (Object.keys(qualifier).length > 0) out.ref_qualifier = qualifier;
  return out;
}

// ── 3e flag derivation ──────────────────────────────────────────────────────

const FLAG_MAP: Record<string, MeasurementFlag> = {
  h: 'High', hi: 'High', high: 'High', 'h*': 'High', '*h': 'High',
  l: 'Low', lo: 'Low', low: 'Low', 'l*': 'Low', '*l': 'Low',
  n: 'Normal', normal: 'Normal', wnl: 'Normal',
};

/**
 * Derive the flag. Trust a printed lab flag first; else derive from the parsed
 * bounds and the (already unit-normalized) value. Returns null if undeterminable.
 */
export function deriveFlag(
  flagPrinted: string | null,
  value: number | null,
  refLow: number | null,
  refHigh: number | null,
): MeasurementFlag | null {
  if (flagPrinted) {
    const mapped = FLAG_MAP[flagPrinted.trim().toLowerCase()];
    if (mapped) return mapped;
  }
  if (value === null) return null;
  if (refLow !== null && value < refLow) return 'Low';
  if (refHigh !== null && value > refHigh) return 'High';
  if (refLow !== null || refHigh !== null) return 'Normal';
  return null;
}

// ── 3f outlier guard ────────────────────────────────────────────────────────

export interface GuardResult {
  value: number | null;
  outlier: boolean;
}

/**
 * Plausibility guard. If the (post-conversion) value sits outside the canonical
 * parameter's plausibility window, force value=null (so it never enters a line/
 * trend) while value_text is preserved upstream, and flag for review.
 */
export function outlierGuard(
  value: number | null,
  param: CanonicalParam | null,
  ruleGuard?: { guard_min: number | null; guard_max: number | null },
): GuardResult {
  if (value === null) return { value: null, outlier: false };

  const lo = ruleGuard?.guard_min ?? param?.plausibility_low ?? null;
  const hi = ruleGuard?.guard_max ?? param?.plausibility_high ?? null;

  if (lo !== null && value < lo) return { value: null, outlier: true };
  if (hi !== null && value > hi) return { value: null, outlier: true };
  return { value, outlier: false };
}

// ── Main per-report processing ──────────────────────────────────────────────

export function processReport(
  report: ExtractedReport,
  dict: Dictionary,
  opts: PostprocessOptions = {},
): PostprocessResult {
  const reviewConf = opts.reviewConfidence ?? 0.6;
  const autoConf = opts.autoAcceptConfidence ?? 0.9;

  const drafts: ProcessedMeasurement[] = [];

  for (const row of report.rows) {
    const param = canonicalize(row.parameter_raw, dict);

    // 3b unit normalization (handles nonlinear_blocked).
    const norm = normalizeUnit(row.value_numeric, row.unit_raw, param, dict);

    // 3c reference range — prefer cleanly-printed numeric bounds, else parse text.
    let refLow = row.ref_low;
    let refHigh = row.ref_high;
    let refQual: Record<string, unknown> | null = null;
    if (refLow === null && refHigh === null) {
      const parsed = parseRefRange(row.ref_text);
      refLow = parsed.ref_low;
      refHigh = parsed.ref_high;
      refQual = parsed.ref_qualifier;
    } else {
      refQual = parseRefRange(row.ref_text).ref_qualifier;
    }
    // Fall back to dictionary defaults only when nothing was printed.
    if (refLow === null && refHigh === null && param) {
      refLow = param.default_ref_low;
      refHigh = param.default_ref_high;
    }

    // 3f outlier guard — only meaningful for unblocked numeric values.
    const rule = param
      ? dict.unitRules.get(param.canonical_param_id)?.get(normUnit(row.unit_raw))
      : undefined;
    const guard = norm.blocked
      ? { value: norm.value, outlier: false }
      : outlierGuard(
          norm.value,
          param,
          rule ? { guard_min: rule.guard_min, guard_max: rule.guard_max } : undefined,
        );

    // 3e flag — derive from the guarded (final) value.
    const flag = deriveFlag(row.flag_printed, guard.value, refLow, refHigh);

    // Review routing.
    const reasons: string[] = [];
    if (!param) reasons.push('unmapped_param');
    if (norm.blocked) reasons.push('unit_ambiguous');
    if (guard.outlier) reasons.push('outlier');
    if (row.confidence < reviewConf) reasons.push('low_conf');
    else if (row.confidence < autoConf && reasons.length === 0) reasons.push('mid_conf');

    drafts.push({
      parameter: param?.display_name ?? row.parameter_raw,
      parameter_raw: row.parameter_raw,
      category: param?.category ?? null,
      canonical_param_id: param?.canonical_param_id ?? null,
      loinc_code: param?.loinc_code ?? null,
      value: guard.value,
      value_text: row.value_text,
      value_operator: row.value_operator,
      unit: norm.unit,
      unit_raw: row.unit_raw,
      ref_low: refLow,
      ref_high: refHigh,
      ref_text: row.ref_text,
      ref_qualifier: refQual,
      flag,
      field_confidence: { overall: row.confidence },
      review_reasons: reasons,
      unit_blocked: norm.blocked,
    });
  }

  // 3g dedup — collapse rows with the same canonical identity (param + unit),
  // preferring the higher-confidence row; union nothing else here (sources are
  // added at persist time). Identity key uses canonical id when known.
  const deduped = dedupMeasurements(drafts);

  const needsReview = deduped.some((m) =>
    m.review_reasons.some((r) => r !== 'mid_conf'),
  );

  return {
    lab: report.lab,
    report_date: report.report_date,
    measurements: deduped,
    needsReview,
  };
}

/** Collapse identical canonical rows (same id-or-rawname). Keeps best confidence. */
export function dedupMeasurements(
  rows: ProcessedMeasurement[],
): ProcessedMeasurement[] {
  const byKey = new Map<string, ProcessedMeasurement>();
  for (const r of rows) {
    const key = (r.canonical_param_id ?? `raw:${normAlias(r.parameter_raw)}`).toLowerCase();
    const prev = byKey.get(key);
    if (!prev) {
      byKey.set(key, r);
      continue;
    }
    const prevConf = Number((prev.field_confidence as { overall?: number })?.overall ?? 0);
    const curConf = Number((r.field_confidence as { overall?: number })?.overall ?? 0);
    if (curConf > prevConf) byKey.set(key, r);
  }
  return [...byKey.values()];
}
