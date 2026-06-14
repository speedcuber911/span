/**
 * TyG Index tests.
 *
 * Reference value: TG=150, FG=100 → ln(150*100/2) = ln(7500) ≈ 8.9227
 */

import { describe, it, expect } from 'vitest';
import { computeTyg } from '../tyg.js';

describe('computeTyg', () => {
  it('computes TyG correctly: ln(TG*FG/2)', () => {
    const result = computeTyg({ triglycerides_mgdl: 150, fasting_glucose_mgdl: 100 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(Math.log(150 * 100 / 2), 5);
    expect(result.value as number).toBeCloseTo(8.9227, 3);
  });

  it('band is always null (no diagnostic cutoff)', () => {
    const result = computeTyg({ triglycerides_mgdl: 150, fasting_glucose_mgdl: 100 });
    expect(result.band).toBeNull();
  });

  it('includes caveat no_cutoff_trend_only', () => {
    const result = computeTyg({ triglycerides_mgdl: 150, fasting_glucose_mgdl: 100 });
    expect(result.caveats).toContain('no_cutoff_trend_only');
  });

  it('returns computable:false when triglycerides missing', () => {
    const result = computeTyg({ triglycerides_mgdl: null, fasting_glucose_mgdl: 100 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('triglycerides_mgdl');
  });

  it('returns computable:false when glucose missing', () => {
    const result = computeTyg({ triglycerides_mgdl: 150, fasting_glucose_mgdl: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('fasting_glucose_mgdl');
  });

  it('returns computable:false when TG is zero (ln undefined)', () => {
    const result = computeTyg({ triglycerides_mgdl: 0, fasting_glucose_mgdl: 100 });
    expect(result.computable).toBe(false);
  });

  it('returns evidenceTier 2', () => {
    const result = computeTyg({ triglycerides_mgdl: 150, fasting_glucose_mgdl: 100 });
    expect(result.evidenceTier).toBe(2);
  });

  it('higher TG and glucose → higher TyG index', () => {
    const low = computeTyg({ triglycerides_mgdl: 80, fasting_glucose_mgdl: 85 });
    const high = computeTyg({ triglycerides_mgdl: 300, fasting_glucose_mgdl: 140 });
    expect(high.value as number).toBeGreaterThan(low.value as number);
  });
});
