/**
 * Ratio soft-flag tests (NLR, AAR/De Ritis, PLR).
 *
 * Reference values:
 *   NLR: neutrophils=4.2, lymphocytes=1.8 → 2.333
 *   AAR: AST=35, ALT=28 → 1.25
 *   PLR: platelets=220, lymphocytes=1.8 → 122.22
 */

import { describe, it, expect } from 'vitest';
import { computeNlr, computeAar, computePlr } from '../ratios.js';

describe('computeNlr', () => {
  it('computes NLR correctly: neutrophils / lymphocytes', () => {
    const result = computeNlr({ neutrophils_k_ul: 4.2, lymphocytes_k_ul: 1.8 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(4.2 / 1.8, 4);
    expect(result.value as number).toBeCloseTo(2.333, 2);
  });

  it('band is null (trend-only, not diagnostic)', () => {
    const result = computeNlr({ neutrophils_k_ul: 4.2, lymphocytes_k_ul: 1.8 });
    expect(result.band).toBeNull();
  });

  it('includes context_dependent_not_diagnostic caveat', () => {
    const result = computeNlr({ neutrophils_k_ul: 4.2, lymphocytes_k_ul: 1.8 });
    expect(result.caveats).toContain('context_dependent_not_diagnostic');
  });

  it('returns evidenceTier 3', () => {
    const result = computeNlr({ neutrophils_k_ul: 4.2, lymphocytes_k_ul: 1.8 });
    expect(result.evidenceTier).toBe(3);
  });

  it('returns computable:false when neutrophils missing', () => {
    const result = computeNlr({ neutrophils_k_ul: null, lymphocytes_k_ul: 1.8 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('neutrophils_k_ul');
  });

  it('returns computable:false when lymphocytes missing', () => {
    const result = computeNlr({ neutrophils_k_ul: 4.2, lymphocytes_k_ul: null });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('lymphocytes_k_ul');
  });
});

describe('computeAar (De Ritis ratio)', () => {
  it('computes AAR correctly: AST / ALT', () => {
    const result = computeAar({ ast_ul: 35, alt_ul: 28 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(35 / 28, 4);
    expect(result.value as number).toBeCloseTo(1.25, 4);
  });

  it('band is null (trend-only)', () => {
    const result = computeAar({ ast_ul: 35, alt_ul: 28 });
    expect(result.band).toBeNull();
  });

  it('includes context_dependent_not_diagnostic caveat', () => {
    const result = computeAar({ ast_ul: 35, alt_ul: 28 });
    expect(result.caveats).toContain('context_dependent_not_diagnostic');
  });

  it('returns evidenceTier 3', () => {
    const result = computeAar({ ast_ul: 35, alt_ul: 28 });
    expect(result.evidenceTier).toBe(3);
  });

  it('returns computable:false when AST missing', () => {
    const result = computeAar({ ast_ul: null, alt_ul: 28 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('ast_ul');
  });

  it('returns computable:false when ALT is zero', () => {
    const result = computeAar({ ast_ul: 35, alt_ul: 0 });
    expect(result.computable).toBe(false);
    expect(result.caveats).toContain('alt_must_be_positive');
  });
});

describe('computePlr', () => {
  it('computes PLR correctly: platelets / lymphocytes', () => {
    const result = computePlr({ platelets_10_9L: 220, lymphocytes_k_ul: 1.8 });
    expect(result.computable).toBe(true);
    expect(result.value as number).toBeCloseTo(220 / 1.8, 3);
    expect(result.value as number).toBeCloseTo(122.22, 1);
  });

  it('band is null (trend-only)', () => {
    const result = computePlr({ platelets_10_9L: 220, lymphocytes_k_ul: 1.8 });
    expect(result.band).toBeNull();
  });

  it('includes context_dependent_not_diagnostic caveat', () => {
    const result = computePlr({ platelets_10_9L: 220, lymphocytes_k_ul: 1.8 });
    expect(result.caveats).toContain('context_dependent_not_diagnostic');
  });

  it('returns evidenceTier 3', () => {
    const result = computePlr({ platelets_10_9L: 220, lymphocytes_k_ul: 1.8 });
    expect(result.evidenceTier).toBe(3);
  });

  it('returns computable:false when platelets missing', () => {
    const result = computePlr({ platelets_10_9L: null, lymphocytes_k_ul: 1.8 });
    expect(result.computable).toBe(false);
    expect(result.missingInputs).toContain('platelets_10_9L');
  });

  it('returns computable:false when lymphocytes are zero', () => {
    const result = computePlr({ platelets_10_9L: 220, lymphocytes_k_ul: 0 });
    expect(result.computable).toBe(false);
    expect(result.caveats).toContain('lymphocytes_must_be_positive');
  });
});
