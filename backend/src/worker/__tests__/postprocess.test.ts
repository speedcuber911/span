/**
 * Deterministic post-processing tests (SPAN_MASTER_PLAN.md §5 STAGE 3).
 *
 * Covers the correctness-critical behaviours:
 *   - unit normalization: mg/dL identity, a scale conversion, and a
 *     nonlinear_blocked case that stays RAW + flagged (Lp(a))
 *   - outlier guard: implausible value → value=null but value_text kept
 *   - censored value '<200' preserves value_operator
 */

import { describe, it, expect } from 'vitest';
import {
  buildDictionary,
  processReport,
  normalizeUnit,
  parseRefRange,
  deriveFlag,
  outlierGuard,
  canonicalize,
  type CanonicalParam,
  type UnitRule,
} from '../postprocess.js';
import type { ExtractedReport, ExtractedRow } from '../../ingestion/types.js';

// ── Fixtures: a tiny canonical dictionary ───────────────────────────────────

const params: CanonicalParam[] = [
  {
    canonical_param_id: 'glucose_fasting',
    display_name: 'Fasting Glucose',
    loinc_code: '1558-6',
    category: 'metabolic',
    canonical_unit: 'mg/dL',
    plausibility_low: 20,
    plausibility_high: 1000,
    default_ref_low: 70,
    default_ref_high: 100,
    aliases: ['glucose fasting', 'fasting blood sugar', 'fbs'],
    alias_regexes: ['fasting.*glucose'],
  },
  {
    canonical_param_id: 'vitamin_b12',
    display_name: 'Vitamin B12',
    loinc_code: '2132-9',
    category: 'micronutrient_bone',
    canonical_unit: 'pg/mL',
    plausibility_low: 50,
    plausibility_high: 3000,
    default_ref_low: 200,
    default_ref_high: 900,
    aliases: ['vitamin b12', 'b12', 'cobalamin'],
    alias_regexes: [],
  },
  {
    canonical_param_id: 'lpa',
    display_name: 'Lp(a)',
    loinc_code: '10835-7',
    category: 'cardiovascular',
    canonical_unit: 'nmol/L',
    plausibility_low: 0,
    plausibility_high: 500,
    default_ref_low: null,
    default_ref_high: 75,
    aliases: ['lp(a)', 'lipoprotein a', 'lipoprotein (a)'],
    alias_regexes: [],
  },
  {
    canonical_param_id: 'ferritin',
    display_name: 'Ferritin',
    loinc_code: '2276-4',
    category: 'hematologic',
    canonical_unit: 'ng/mL',
    plausibility_low: 1,
    plausibility_high: 2000,
    default_ref_low: 30,
    default_ref_high: 400,
    aliases: ['ferritin'],
    alias_regexes: [],
  },
];

const rules: UnitRule[] = [
  // Glucose mg/dL → identity (canonical IS mg/dL)
  {
    canonical_param_id: 'glucose_fasting',
    raw_unit_normalized: 'mg/dl',
    conversion_kind: 'identity',
    factor: null,
    offset: null,
    guard_min: 20,
    guard_max: 1000,
    note: null,
  },
  // B12 ng/mL → pg/mL is a ×1000 scale conversion (the classic 1000× trap)
  {
    canonical_param_id: 'vitamin_b12',
    raw_unit_normalized: 'ng/ml',
    conversion_kind: 'scale',
    factor: 1000,
    offset: 0,
    guard_min: 50,
    guard_max: 3000,
    note: 'ng/mL → pg/mL ×1000',
  },
  // B12 pg/mL → identity
  {
    canonical_param_id: 'vitamin_b12',
    raw_unit_normalized: 'pg/ml',
    conversion_kind: 'identity',
    factor: null,
    offset: null,
    guard_min: 50,
    guard_max: 3000,
    note: null,
  },
  // Lp(a) mg/dL → nmol/L is NON-LINEAR / contested → blocked. Keep raw + flag.
  {
    canonical_param_id: 'lpa',
    raw_unit_normalized: 'mg/dl',
    conversion_kind: 'nonlinear_blocked',
    factor: null,
    offset: null,
    guard_min: null,
    guard_max: null,
    note: 'Lp(a) mg/dL⇄nmol/L is non-linear; do not auto-convert',
  },
  // Ferritin ng/mL identity
  {
    canonical_param_id: 'ferritin',
    raw_unit_normalized: 'ng/ml',
    conversion_kind: 'identity',
    factor: null,
    offset: null,
    guard_min: 1,
    guard_max: 2000,
    note: null,
  },
];

const dict = buildDictionary(params, rules, 1);

function row(overrides: Partial<ExtractedRow>): ExtractedRow {
  return {
    parameter_raw: 'Fasting Glucose',
    value_text: '90',
    value_numeric: 90,
    value_operator: null,
    unit_raw: 'mg/dL',
    ref_text: '70-100',
    ref_low: null,
    ref_high: null,
    flag_printed: null,
    confidence: 0.97,
    ...overrides,
  };
}

function report(rows: ExtractedRow[]): ExtractedReport {
  return { lab: 'TestLab', report_date: '2026-01-15', rows };
}

// ── Unit normalization ──────────────────────────────────────────────────────

describe('unit normalization', () => {
  it('mg/dL is identity (value unchanged, canonical unit set)', () => {
    const p = canonicalize('Fasting Glucose', dict)!;
    const n = normalizeUnit(90, 'mg/dL', p, dict);
    expect(n.value).toBe(90);
    expect(n.unit).toBe('mg/dL');
    expect(n.blocked).toBe(false);
  });

  it('applies a ×1000 scale conversion (B12 ng/mL → pg/mL)', () => {
    const p = canonicalize('B12', dict)!;
    const n = normalizeUnit(0.4, 'ng/mL', p, dict);
    expect(n.value).toBeCloseTo(400, 6);
    expect(n.unit).toBe('pg/mL');
    expect(n.blocked).toBe(false);
  });

  it('nonlinear_blocked (Lp(a) mg/dL) stays RAW and is flagged', () => {
    const p = canonicalize('Lp(a)', dict)!;
    const n = normalizeUnit(30, 'mg/dL', p, dict);
    // value NOT converted; unit kept raw; blocked=true
    expect(n.value).toBe(30);
    expect(n.unit).toBe('mg/dL');
    expect(n.blocked).toBe(true);

    // and end-to-end the row routes to review with unit_ambiguous
    const res = processReport(
      report([
        row({
          parameter_raw: 'Lp(a)',
          value_text: '30',
          value_numeric: 30,
          unit_raw: 'mg/dL',
          ref_text: '< 75',
        }),
      ]),
      dict,
    );
    const m = res.measurements[0]!;
    expect(m.unit_blocked).toBe(true);
    expect(m.value).toBe(30); // unconverted
    expect(m.unit).toBe('mg/dL'); // raw unit preserved
    expect(m.review_reasons).toContain('unit_ambiguous');
    expect(res.needsReview).toBe(true);
  });
});

// ── Outlier guard ───────────────────────────────────────────────────────────

describe('outlier guard', () => {
  it('forces an implausible value to null but keeps value_text', () => {
    const p = canonicalize('Ferritin', dict)!;
    // 99999 ng/mL is way past plausibility_high (2000)
    const g = outlierGuard(99999, p);
    expect(g.value).toBeNull();
    expect(g.outlier).toBe(true);

    const res = processReport(
      report([
        row({
          parameter_raw: 'Ferritin',
          value_text: '99999',
          value_numeric: 99999,
          unit_raw: 'ng/mL',
          ref_text: '30-400',
        }),
      ]),
      dict,
    );
    const m = res.measurements[0]!;
    expect(m.value).toBeNull(); // excluded from the line/trend
    expect(m.value_text).toBe('99999'); // but preserved verbatim
    expect(m.review_reasons).toContain('outlier');
    expect(res.needsReview).toBe(true);
  });

  it('keeps a plausible value', () => {
    const p = canonicalize('Ferritin', dict)!;
    const g = outlierGuard(120, p);
    expect(g.value).toBe(120);
    expect(g.outlier).toBe(false);
  });
});

// ── Censored values ─────────────────────────────────────────────────────────

describe('censored / operator values', () => {
  it("preserves value_operator for '<200'", () => {
    const res = processReport(
      report([
        row({
          parameter_raw: 'Fasting Glucose',
          value_text: '<200',
          value_numeric: null, // LLM leaves numeric null for censored
          value_operator: '<',
          unit_raw: 'mg/dL',
          ref_text: '70-100',
        }),
      ]),
      dict,
    );
    const m = res.measurements[0]!;
    expect(m.value_operator).toBe('<');
    expect(m.value_text).toBe('<200');
    expect(m.value).toBeNull(); // censored → no numeric value on the line
  });

  it("preserves '> 24' operator and text", () => {
    const res = processReport(
      report([
        row({
          parameter_raw: 'Ferritin',
          value_text: '> 24',
          value_numeric: null,
          value_operator: '>',
          unit_raw: 'ng/mL',
          ref_text: '30-400',
        }),
      ]),
      dict,
    );
    const m = res.measurements[0]!;
    expect(m.value_operator).toBe('>');
    expect(m.value_text).toBe('> 24');
  });
});

// ── Reference-range parsing + flag derivation (supporting coverage) ─────────

describe('reference-range parsing', () => {
  it('parses a simple low-high range', () => {
    expect(parseRefRange('3.5-5.0')).toMatchObject({ ref_low: 3.5, ref_high: 5.0 });
  });
  it('parses bracketed ranges', () => {
    expect(parseRefRange('[8.00-23.00]')).toMatchObject({ ref_low: 8, ref_high: 23 });
  });
  it('parses an upper-only bound', () => {
    expect(parseRefRange('<200 IU/ml')).toMatchObject({ ref_low: null, ref_high: 200 });
  });
  it('captures a sex/age qualifier and the range after the label', () => {
    const r = parseRefRange('Male > 51 Years: 56 - 119');
    expect(r.ref_low).toBe(56);
    expect(r.ref_high).toBe(119);
    expect(r.ref_qualifier).toMatchObject({ sex: 'male', age_gt: 51 });
  });
});

describe('flag derivation', () => {
  it('trusts a printed H/L flag', () => {
    expect(deriveFlag('H', 5, 1, 10)).toBe('High');
    expect(deriveFlag('L', 5, 1, 10)).toBe('Low');
  });
  it('derives from bounds when no printed flag', () => {
    expect(deriveFlag(null, 150, 70, 100)).toBe('High');
    expect(deriveFlag(null, 50, 70, 100)).toBe('Low');
    expect(deriveFlag(null, 85, 70, 100)).toBe('Normal');
  });
  it('returns null when undeterminable', () => {
    expect(deriveFlag(null, null, null, null)).toBeNull();
    expect(deriveFlag(null, 85, null, null)).toBeNull();
  });
});

// ── Canonicalization + dedup ────────────────────────────────────────────────

describe('canonicalization', () => {
  it('matches an alias', () => {
    expect(canonicalize('FBS', dict)?.canonical_param_id).toBe('glucose_fasting');
  });
  it('matches a regex alias', () => {
    expect(canonicalize('Fasting Plasma Glucose', dict)?.canonical_param_id).toBe(
      'glucose_fasting',
    );
  });
  it('returns null + routes unmapped param to review', () => {
    expect(canonicalize('Some Novel Marker', dict)).toBeNull();
    const res = processReport(
      report([row({ parameter_raw: 'Some Novel Marker', confidence: 0.99 })]),
      dict,
    );
    expect(res.measurements[0]!.canonical_param_id).toBeNull();
    expect(res.measurements[0]!.review_reasons).toContain('unmapped_param');
  });
});

describe('dedup', () => {
  it('collapses identical canonical rows, keeping higher confidence', () => {
    const res = processReport(
      report([
        row({ parameter_raw: 'Fasting Glucose', value_numeric: 90, confidence: 0.7 }),
        row({ parameter_raw: 'FBS', value_numeric: 92, confidence: 0.95 }),
      ]),
      dict,
    );
    expect(res.measurements).toHaveLength(1);
    expect(res.measurements[0]!.value).toBe(92); // the higher-confidence row won
  });
});
