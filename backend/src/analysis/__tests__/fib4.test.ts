/**
 * FIB-4 index tests.
 *
 * Reference values:
 *   Rule-out: age=35, AST=25, plt=220, ALT=30 → 0.726 (<1.45)
 *   Advanced:  age=55, AST=90, plt=100, ALT=40 → 7.827 (>3.25)
 *   Age>65:   age=70, AST=45, plt=150, ALT=35 → 3.550 (>2.0 → advanced with older cutoff)
 */

import { describe, it, expect } from 'vitest';
import { computeFib4 } from '../fib4.js';

describe('computeFib4', () => {
  // ── Rule-out case ────────────────────────────────────────────────────────

  it('returns band rule_out for low FIB-4 (<1.45)', () => {
    const result = computeFib4({ age: 35, ast_ul: 25, platelets_10_9L: 220, alt_ul: 30 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(0.726, 2);
    expect(result.band).toBe('rule_out');
  });

  // ── Advanced case ────────────────────────────────────────────────────────

  it('returns band advanced for high FIB-4 (>3.25)', () => {
    const result = computeFib4({ age: 55, ast_ul: 90, platelets_10_9L: 100, alt_ul: 40 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(7.827, 2);
    expect(result.band).toBe('advanced');
  });

  // ── Indeterminate case ───────────────────────────────────────────────────

  it('returns band indeterminate for FIB-4 between 1.45 and 3.25', () => {
    // age=45, AST=55, plt=200, ALT=25
    // FIB-4 = (45*55)/(200*sqrt(25)) = 2475/1000 = 2.475
    const result = computeFib4({ age: 45, ast_ul: 55, platelets_10_9L: 200, alt_ul: 25 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(2.475, 2);
    expect(result.band).toBe('indeterminate');
  });

  // ── Age > 65: lower cutoff switches to 2.0 ───────────────────────────────

  it('uses lower cutoff 2.0 for age > 65, records caveat', () => {
    // age=70, AST=45, plt=150, ALT=35 → FIB-4 ≈ 3.550
    // With age>65 cutoff 2.0: 3.550 > 3.25 → advanced either way
    // Let's test a value between 1.45 and 2.0: would be rule_out (<1.45 standard)
    // but advanced (>2.0 older) — shows the switch matters
    // age=68, AST=35, plt=250, ALT=30 → (68*35)/(250*sqrt(30)) = 2380/1369.3 ≈ 1.738
    const result = computeFib4({ age: 68, ast_ul: 35, platelets_10_9L: 250, alt_ul: 30 });
    expect(result.computable).toBe(true);
    const val = result.value as number;
    expect(val).toBeCloseTo(1.738, 1);
    // With cutoff 2.0 (age>65): 1.738 < 2.0 → rule_out
    // With cutoff 1.45 (standard): 1.738 > 1.45 → indeterminate
    // This test confirms the age>65 cutoff was applied (rule_out, not indeterminate)
    expect(result.band).toBe('rule_out');
    expect(result.caveats).toContain('age_gt65_lower_cutoff_2.0_used');
  });

  it('records standard cutoff caveat when age <= 65', () => {
    const result = computeFib4({ age: 50, ast_ul: 30, platelets_10_9L: 200, alt_ul: 25 });
    expect(result.caveats).toContain('standard_lower_cutoff_1.45_used');
    expect(result.caveats).not.toContain('age_gt65_lower_cutoff_2.0_used');
  });

  it('reference age>65 case: FIB-4 ≈ 3.550 → advanced', () => {
    const result = computeFib4({ age: 70, ast_ul: 45, platelets_10_9L: 150, alt_ul: 35 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(3.550, 1);
    expect(result.band).toBe('advanced');
    expect(result.caveats).toContain('age_gt65_lower_cutoff_2.0_used');
  });

  // ── Missing inputs ────────────────────────────────────────────────────────

  it('returns computable:false when age is missing', () => {
    const result = computeFib4({ age: null, ast_ul: 25, platelets_10_9L: 220, alt_ul: 30 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('age');
  });

  it('returns computable:false when any required input is missing', () => {
    const result = computeFib4({ age: 45, ast_ul: null, platelets_10_9L: null, alt_ul: 30 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('ast_ul');
    expect(result.missingInputs).toContain('platelets_10_9L');
  });

  // ── Evidence tier ─────────────────────────────────────────────────────────

  it('returns evidenceTier 1', () => {
    const result = computeFib4({ age: 45, ast_ul: 30, platelets_10_9L: 200, alt_ul: 25 });
    expect(result.evidenceTier).toBe(1);
  });

  it('includes derivation population caveat', () => {
    const result = computeFib4({ age: 45, ast_ul: 30, platelets_10_9L: 200, alt_ul: 25 });
    expect(result.caveats).toContain('derivation_pop_hiv_hcv_coinfection');
  });
});
