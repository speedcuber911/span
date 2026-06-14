/**
 * NAFLD Fibrosis Score tests (Angulo 2007).
 *
 * Reference values:
 *   Exclude: age=45, BMI=27, diab=false, AST=25, ALT=30, plt=200, alb=4.2 → -2.019 (<-1.455)
 *   Advanced: age=60, BMI=35, diab=true, AST=80, ALT=40, plt=120, alb=3.5 → 3.075 (>0.676)
 */

import { describe, it, expect } from 'vitest';
import { computeNafldFs } from '../nafld_fs.js';

describe('computeNafldFs', () => {
  // ── Exclude-advanced case ────────────────────────────────────────────────

  it('returns band exclude_advanced for NFS < -1.455', () => {
    const result = computeNafldFs({
      age: 45,
      bmi_kg_m2: 27,
      diabetes_or_ifg: false,
      ast_ul: 25,
      alt_ul: 30,
      platelets_10_9L: 200,
      albumin_gdl: 4.2,
    });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(-2.019, 2);
    expect(result.band).toBe('exclude_advanced');
  });

  // ── Advanced case ─────────────────────────────────────────────────────────

  it('returns band advanced for NFS > 0.676', () => {
    const result = computeNafldFs({
      age: 60,
      bmi_kg_m2: 35,
      diabetes_or_ifg: true,
      ast_ul: 80,
      alt_ul: 40,
      platelets_10_9L: 120,
      albumin_gdl: 3.5,
    });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(3.075, 2);
    expect(result.band).toBe('advanced');
  });

  // ── Indeterminate case ───────────────────────────────────────────────────

  it('returns band indeterminate for NFS between -1.455 and 0.676', () => {
    // age=50, BMI=30, diab=false, AST=50, ALT=40, plt=180, alb=4.0
    // NFS = -1.675 + 0.037*50 + 0.094*30 + 0 + 0.99*(50/40) - 0.013*180 - 0.66*4.0
    //     = -1.675 + 1.85 + 2.82 + 0 + 1.2375 - 2.34 - 2.64 = -0.7475
    const result = computeNafldFs({
      age: 50,
      bmi_kg_m2: 30,
      diabetes_or_ifg: false,
      ast_ul: 50,
      alt_ul: 40,
      platelets_10_9L: 180,
      albumin_gdl: 4.0,
    });
    expect(result.computable).toBe(true);
    expect(result.band).toBe('indeterminate');
  });

  // ── Missing BMI → computable:false ────────────────────────────────────────

  it('returns computable:false when BMI is missing (gated onboarding input)', () => {
    const result = computeNafldFs({
      age: 45,
      bmi_kg_m2: null,
      diabetes_or_ifg: false,
      ast_ul: 25,
      alt_ul: 30,
      platelets_10_9L: 200,
      albumin_gdl: 4.2,
    });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('bmi_kg_m2');
  });

  // ── Missing diabFlag → computable:false ──────────────────────────────────

  it('returns computable:false when diabetes_or_ifg is missing (gated onboarding input)', () => {
    const result = computeNafldFs({
      age: 45,
      bmi_kg_m2: 27,
      diabetes_or_ifg: null,
      ast_ul: 25,
      alt_ul: 30,
      platelets_10_9L: 200,
      albumin_gdl: 4.2,
    });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('diabetes_or_ifg');
  });

  // ── Diabetes flag effect ───────────────────────────────────────────────────

  it('diabetes flag=true gives higher score than false (all else equal)', () => {
    const base = {
      age: 50,
      bmi_kg_m2: 28,
      ast_ul: 35,
      alt_ul: 30,
      platelets_10_9L: 190,
      albumin_gdl: 4.0,
    };
    const withDiab = computeNafldFs({ ...base, diabetes_or_ifg: true });
    const withoutDiab = computeNafldFs({ ...base, diabetes_or_ifg: false });
    expect(withDiab.value as number).toBeGreaterThan(withoutDiab.value as number);
    // Difference should be 1.13 (the diabetes coefficient)
    expect((withDiab.value as number) - (withoutDiab.value as number)).toBeCloseTo(1.13, 5);
  });

  // ── Evidence tier ─────────────────────────────────────────────────────────

  it('returns evidenceTier 2', () => {
    const result = computeNafldFs({
      age: 45,
      bmi_kg_m2: 27,
      diabetes_or_ifg: false,
      ast_ul: 25,
      alt_ul: 30,
      platelets_10_9L: 200,
      albumin_gdl: 4.2,
    });
    expect(result.evidenceTier).toBe(2);
  });
});
