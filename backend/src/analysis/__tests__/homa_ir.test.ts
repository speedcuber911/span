/**
 * HOMA-IR tests.
 *
 * Reference value: insulin=10 µU/mL, glucose=95 mg/dL → (10*95)/405 ≈ 2.346
 */

import { describe, it, expect } from 'vitest';
import { computeHomaIr } from '../homa_ir.js';

describe('computeHomaIr', () => {
  it('computes HOMA-IR correctly: (insulin*glucose)/405', () => {
    const result = computeHomaIr({ fasting_insulin_uU_ml: 10, fasting_glucose_mgdl: 95 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo((10 * 95) / 405, 4);
    expect(result.value as number).toBeCloseTo(2.346, 2);
  });

  it('returns computable:false when insulin is missing', () => {
    const result = computeHomaIr({ fasting_insulin_uU_ml: null, fasting_glucose_mgdl: 95 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('fasting_insulin_uU_ml');
    expect(result.value).toBeNull();
  });

  it('returns computable:false when glucose is missing', () => {
    const result = computeHomaIr({ fasting_insulin_uU_ml: 10, fasting_glucose_mgdl: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('fasting_glucose_mgdl');
  });

  it('low HOMA-IR → likely_sensitive band', () => {
    // insulin=5, glucose=80 → (5*80)/405 ≈ 0.988
    const result = computeHomaIr({ fasting_insulin_uU_ml: 5, fasting_glucose_mgdl: 80 });
    expect(result.computable).toBe(true);
    expect(result.band).toBe('likely_sensitive');
  });

  it('borderline HOMA-IR → borderline band', () => {
    // insulin=10, glucose=95 → 2.346 (between 1.0 and 2.5)
    const result = computeHomaIr({ fasting_insulin_uU_ml: 10, fasting_glucose_mgdl: 95 });
    expect(result.band).toBe('borderline');
  });

  it('high HOMA-IR → insulin_resistant band', () => {
    // insulin=20, glucose=120 → (20*120)/405 ≈ 5.93
    const result = computeHomaIr({ fasting_insulin_uU_ml: 20, fasting_glucose_mgdl: 120 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeGreaterThan(2.5);
    expect(result.band).toBe('insulin_resistant');
  });

  it('returns evidenceTier 2', () => {
    const result = computeHomaIr({ fasting_insulin_uU_ml: 10, fasting_glucose_mgdl: 95 });
    expect(result.evidenceTier).toBe(2);
  });

  it('includes insulin assay variability caveat', () => {
    const result = computeHomaIr({ fasting_insulin_uU_ml: 10, fasting_glucose_mgdl: 95 });
    expect(result.caveats).toContain('insulin_assay_variability_limits_cross_lab_comparison');
  });
});
