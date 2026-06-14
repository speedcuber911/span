/**
 * CKD-EPI 2021 race-free eGFR tests.
 *
 * Reference values:
 *   Male, creatinine 0.9 mg/dL, age 40 → eGFR ≈ 110.73 mL/min/1.73m²
 *   Female, creatinine 0.9 mg/dL, age 40 → eGFR ≈ 82.88 mL/min/1.73m²
 *   2009 formula (same inputs) → ≈ 106.03 (different from 2021)
 *
 * The 2021 formula uses α = -0.302 (M) / -0.241 (F).
 * The 2009 formula uses α = -0.411 (M) / -0.329 (F).
 * They produce different values — the regression test below confirms 2021 is in use.
 */

import { describe, it, expect } from 'vitest';
import { computeEgfr } from '../egfr.js';

describe('computeEgfr (CKD-EPI 2021)', () => {
  // ── Known reference case: male ───────────────────────────────────────────

  it('returns ~110.73 for male, creatinine 0.9, age 40', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    expect(result.computable).toBe(true);
    expect(result.value).not.toBeNull();
    expect(result.value as number).toBeCloseTo(110.73, 1);
  });

  it('male eGFR > 90 → band G1_normal_high', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    expect(result.band).toBe('G1_normal_high');
  });

  // ── Female sex multiplier (1.012) ─────────────────────────────────────────

  it('returns ~82.88 for female, creatinine 0.9, age 40', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'F' });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(82.88, 1);
  });

  it('female eGFR differs from male eGFR (sex multiplier applied)', () => {
    const male = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    const female = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'F' });
    expect(male.value as number).not.toBeCloseTo(female.value as number, 0);
  });

  // ── 2021 vs 2009 regression test ──────────────────────────────────────────

  it('2021 male result differs from 2009 formula value (~106.03)', () => {
    // 2009 formula: 141 * min(Scr/k,1)^-0.411 * max(Scr/k,1)^-1.209 * 0.9929^age
    // For Scr=0.9, k=0.9, Scr/k=1 → min=1, max=1 → 141 * 1^-0.411 * 1^-1.209 * 0.9929^40
    const expected2009 = 141 * Math.pow(0.9929, 40); // ≈ 106.03
    const result2021 = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    // The 2021 value (≈110.73) should NOT equal the 2009 value (≈106.03)
    expect(Math.abs((result2021.value as number) - expected2009)).toBeGreaterThan(1);
    // 2021 value should be ~110.73, not ~106.03
    expect(result2021.value as number).toBeGreaterThan(108);
  });

  // ── Impaired kidney function bands ───────────────────────────────────────

  it('high creatinine → reduced eGFR with correct band', () => {
    // Female, creatinine 2.5, age 65 → moderately reduced
    const result = computeEgfr({ creatinine_mgdl: 2.5, age: 65, sex: 'F' });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeLessThan(45);
    expect(['G3b_moderate_severe', 'G4_severely_decreased']).toContain(result.band);
  });

  // ── Missing sex → not computable ──────────────────────────────────────────

  it('returns computable:false when sex is missing', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('sex');
    expect(result.value).toBeNull();
  });

  it('returns computable:false when creatinine is missing', () => {
    const result = computeEgfr({ creatinine_mgdl: null, age: 40, sex: 'M' });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('creatinine_mgdl');
  });

  it('returns computable:false when age is missing', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: null, sex: 'M' });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('age');
  });

  // ── Evidence tier and unit ────────────────────────────────────────────────

  it('returns evidenceTier 1', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    expect(result.evidenceTier).toBe(1);
  });

  it('returns unit mL/min/1.73m²', () => {
    const result = computeEgfr({ creatinine_mgdl: 0.9, age: 40, sex: 'M' });
    expect(result.unit).toBe('mL/min/1.73m²');
  });
});
