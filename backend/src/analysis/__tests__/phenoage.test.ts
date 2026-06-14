/**
 * PhenoAge unit tests (Levine 2018, PMC6388911).
 *
 * Reference value computation (documented here):
 *
 * Test case 1 — healthy 40-year-old:
 *   albumin 4.7 g/dL → 47 g/L
 *   creatinine 0.9 mg/dL → 79.578 µmol/L
 *   glucose 90 mg/dL → 5.0 mmol/L
 *   CRP 0.5 mg/L → 0.05 mg/dL → ln(0.05) ≈ -2.9957
 *   lymphocyte 30%, MCV 90 fL, RDW 13%, ALP 70 U/L, WBC 6 10^3/µL, age 40
 *
 *   xb = -10.0139
 *   M  = 0.00879
 *   PhenoAge ≈ 31.40 years  (delta ≈ -8.60 vs chronological 40)
 *
 * Test case 2 — elevated markers, 50-year-old:
 *   albumin 3.8 g/dL, creatinine 1.4 mg/dL, glucose 110 mg/dL,
 *   CRP 5.0 mg/L, lymph 18%, MCV 100 fL, RDW 15.5%, ALP 120 U/L, WBC 9.5
 *   PhenoAge ≈ 70.09 years  (delta ≈ +20.09 vs chronological 50)
 */

import { describe, it, expect } from 'vitest';
import { computePhenoAge } from '../phenoage.js';

// ── Shared healthy-40 inputs ──────────────────────────────────────────────────
const healthy40 = {
  albumin_gdl: 4.7,
  creatinine_mgdl: 0.9,
  glucose_mgdl: 90,
  crp_mgl: 0.5,
  lymphocyte_pct: 30,
  mcv_fl: 90,
  rdw_pct: 13,
  alp_ul: 70,
  wbc_k_ul: 6,
  age: 40,
};

describe('computePhenoAge', () => {
  // ── Reference value: healthy 40-year-old ──────────────────────────────────

  it('computes a finite, plausible PhenoAge for a healthy 40-year-old', () => {
    const result = computePhenoAge(healthy40);
    expect(result.computable).toBe(true);
    expect(result.value).not.toBeNull();
    expect(isFinite(result.value as number)).toBe(true);
    // Expected ≈ 31.40 years (biologically younger than chronological age)
    expect(result.value as number).toBeCloseTo(31.40, 1);
  });

  it('returns the correct delta for the healthy-40 reference case', () => {
    const result = computePhenoAge(healthy40);
    expect(result.delta).not.toBeNull();
    // delta = PhenoAge - chronoAge ≈ -8.60 (biologically younger)
    expect(result.delta as number).toBeCloseTo(-8.60, 1);
    expect(result.delta as number).toBeLessThan(0);
  });

  it('returns unit "years"', () => {
    const result = computePhenoAge(healthy40);
    expect(result.unit).toBe('years');
  });

  // ── Reference value: elevated markers, 50-year-old ───────────────────────

  it('returns a biologically OLDER PhenoAge for elevated-marker inputs', () => {
    const elevated = {
      albumin_gdl: 3.8,
      creatinine_mgdl: 1.4,
      glucose_mgdl: 110,
      crp_mgl: 5.0,
      lymphocyte_pct: 18,
      mcv_fl: 100,
      rdw_pct: 15.5,
      alp_ul: 120,
      wbc_k_ul: 9.5,
      age: 50,
    };
    const result = computePhenoAge(elevated);
    expect(result.computable).toBe(true);
    // Expected ≈ 70.09 (delta ≈ +20.09, biologically older)
    expect(result.value as number).toBeCloseTo(70.09, 1);
    expect(result.delta as number).toBeCloseTo(20.09, 1);
    expect(result.delta as number).toBeGreaterThan(0);
  });

  it('elevated case PhenoAge > healthy case PhenoAge', () => {
    const elevated = {
      albumin_gdl: 3.8,
      creatinine_mgdl: 1.4,
      glucose_mgdl: 110,
      crp_mgl: 5.0,
      lymphocyte_pct: 18,
      mcv_fl: 100,
      rdw_pct: 15.5,
      alp_ul: 120,
      wbc_k_ul: 9.5,
      age: 50,
    };
    const r1 = computePhenoAge(healthy40);
    const r2 = computePhenoAge(elevated);
    expect(r2.value as number).toBeGreaterThan(r1.value as number);
  });

  // ── Unit conversion checks ────────────────────────────────────────────────

  it('records CRP unit conversion: mg/L input → mg/dL in formula', () => {
    const result = computePhenoAge(healthy40);
    const crpUsed = result.inputsUsed.find((u) => u.name === 'crp');
    expect(crpUsed).toBeDefined();
    // Raw in mg/L (0.5), converted to mg/dL (0.05)
    expect(crpUsed!.rawValue).toBeCloseTo(0.5);
    expect(crpUsed!.rawUnit).toBe('mg/L');
    expect(crpUsed!.value).toBeCloseTo(0.05);
    expect(crpUsed!.unit).toBe('mg/dL');
    expect(crpUsed!.unit_xform).toContain('10');
  });

  it('records albumin unit conversion: g/dL → g/L (× 10)', () => {
    const result = computePhenoAge(healthy40);
    const albUsed = result.inputsUsed.find((u) => u.name === 'albumin');
    expect(albUsed).toBeDefined();
    expect(albUsed!.rawValue).toBeCloseTo(4.7);
    expect(albUsed!.rawUnit).toBe('g/dL');
    expect(albUsed!.value).toBeCloseTo(47);
    expect(albUsed!.unit).toBe('g/L');
  });

  it('records creatinine unit conversion: mg/dL → µmol/L (× 88.42)', () => {
    const result = computePhenoAge(healthy40);
    const creUsed = result.inputsUsed.find((u) => u.name === 'creatinine');
    expect(creUsed).toBeDefined();
    expect(creUsed!.rawValue).toBeCloseTo(0.9);
    expect(creUsed!.rawUnit).toBe('mg/dL');
    expect(creUsed!.value).toBeCloseTo(0.9 * 88.42, 3);
    expect(creUsed!.unit).toBe('µmol/L');
  });

  it('records glucose unit conversion: mg/dL → mmol/L (÷ 18)', () => {
    const result = computePhenoAge(healthy40);
    const gluUsed = result.inputsUsed.find((u) => u.name === 'glucose');
    expect(gluUsed).toBeDefined();
    expect(gluUsed!.rawValue).toBeCloseTo(90);
    expect(gluUsed!.value).toBeCloseTo(90 / 18, 5);
    expect(gluUsed!.unit).toBe('mmol/L');
  });

  // ── CRP ≤ 0 guard ─────────────────────────────────────────────────────────

  it('substitutes LoD and adds caveat when CRP = 0', () => {
    const result = computePhenoAge({ ...healthy40, crp_mgl: 0 });
    expect(result.computable).toBe(true);
    expect(result.caveats).toContain('crp_below_lod');
    expect(isFinite(result.value as number)).toBe(true);
  });

  it('substitutes LoD and adds caveat when CRP is negative', () => {
    const result = computePhenoAge({ ...healthy40, crp_mgl: -1 });
    expect(result.computable).toBe(true);
    expect(result.caveats).toContain('crp_below_lod');
  });

  // ── Missing inputs → not computable ─────────────────────────────────────

  it('returns computable:false when albumin is missing', () => {
    const result = computePhenoAge({ ...healthy40, albumin_gdl: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('albumin_gdl');
    expect(result.value).toBeNull();
    expect(result.delta).toBeNull();
  });

  it('returns computable:false when age is missing', () => {
    const result = computePhenoAge({ ...healthy40, age: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('age');
  });

  it('returns computable:false when multiple inputs missing', () => {
    const result = computePhenoAge({
      albumin_gdl: null,
      creatinine_mgdl: null,
      glucose_mgdl: 90,
      crp_mgl: 0.5,
      lymphocyte_pct: null,
      mcv_fl: 90,
      rdw_pct: 13,
      alp_ul: null,
      wbc_k_ul: 6,
      age: 40,
    });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('albumin_gdl');
    expect(result.missingInputs).toContain('creatinine_mgdl');
    expect(result.missingInputs).toContain('lymphocyte_pct');
    expect(result.missingInputs).toContain('alp_ul');
  });

  // ── Evidence tier and structure ────────────────────────────────────────────

  it('returns evidenceTier 2', () => {
    const result = computePhenoAge(healthy40);
    expect(result.evidenceTier).toBe(2);
  });

  it('has non-empty inputsUsed with 10 entries when computable', () => {
    const result = computePhenoAge(healthy40);
    expect(result.inputsUsed.length).toBe(10);
  });
});
