/**
 * FIB-4 index — Liver fibrosis risk (Sterling et al., 2006).
 *
 * Formula: (age × AST) / (platelets[10^9/L] × √ALT)
 *
 * Bands (standard):
 *   < 1.45            → rule_out (low probability of advanced fibrosis)
 *   1.45 – 3.25       → indeterminate
 *   > 3.25            → advanced (high probability of advanced fibrosis)
 *
 * CRITICAL age>65 adjustment (AGA/AASLD guideline):
 *   If age > 65, the lower cutoff shifts from 1.45 to 2.0 to reduce
 *   false positives in older patients. The upper cutoff (3.25) is unchanged.
 *   The active cutoff set is recorded in caveats.
 *
 * Derivation population was HIV/HCV co-infection — context noted in caveats.
 *
 * Evidence tier: 1 (AGA/AASLD guideline endorsed).
 */

import type { ScoreResult, InputUsed } from './types.js';

export interface Fib4Inputs {
  /** Patient age in years */
  age: number | null | undefined;
  /** AST (aspartate aminotransferase) in U/L */
  ast_ul: number | null | undefined;
  /** Platelets in 10^9/L (= ×10³/µL, the common lab unit) */
  platelets_10_9L: number | null | undefined;
  /** ALT (alanine aminotransferase) in U/L */
  alt_ul: number | null | undefined;
}

/** Standard cutoffs */
const CUTOFF_LOWER_STD = 1.45;
const CUTOFF_UPPER = 3.25;
/** Age-adjusted lower cutoff (age > 65) */
const CUTOFF_LOWER_OLDER = 2.0;

function fib4Band(value: number, lowerCutoff: number): string {
  if (value < lowerCutoff) return 'rule_out';
  if (value > CUTOFF_UPPER) return 'advanced';
  return 'indeterminate';
}

/**
 * Compute FIB-4 index.
 */
export function computeFib4(inputs: Fib4Inputs): ScoreResult {
  const missingInputs: string[] = [];
  const caveats: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.age == null) missingInputs.push('age');
  if (inputs.ast_ul == null) missingInputs.push('ast_ul');
  if (inputs.platelets_10_9L == null) missingInputs.push('platelets_10_9L');
  if (inputs.alt_ul == null) missingInputs.push('alt_ul');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs,
      caveats,
      evidenceTier: 1,
      inputsUsed,
    };
  }

  const age = inputs.age as number;
  const ast = inputs.ast_ul as number;
  const platelets = inputs.platelets_10_9L as number;
  const alt = inputs.alt_ul as number;

  // Denominator guard: ALT must be positive (cannot take sqrt of ≤ 0)
  if (alt <= 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: ['alt_must_be_positive'],
      evidenceTier: 1,
      inputsUsed,
    };
  }

  if (platelets <= 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: ['platelets_must_be_positive'],
      evidenceTier: 1,
      inputsUsed,
    };
  }

  const fib4 = (age * ast) / (platelets * Math.sqrt(alt));

  // Age > 65: use lower cutoff 2.0 instead of 1.45
  const useOlderCutoff = age > 65;
  const lowerCutoff = useOlderCutoff ? CUTOFF_LOWER_OLDER : CUTOFF_LOWER_STD;

  if (useOlderCutoff) {
    caveats.push('age_gt65_lower_cutoff_2.0_used');
  } else {
    caveats.push('standard_lower_cutoff_1.45_used');
  }
  caveats.push('derivation_pop_hiv_hcv_coinfection');

  inputsUsed.push({ name: 'age', value: age, unit: 'years' });
  inputsUsed.push({ name: 'ast', value: ast, unit: 'U/L' });
  inputsUsed.push({ name: 'platelets', value: platelets, unit: '10^9/L' });
  inputsUsed.push({ name: 'alt', value: alt, unit: 'U/L' });

  return {
    value: fib4,
    unit: 'index',
    band: fib4Band(fib4, lowerCutoff),
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 1,
    inputsUsed,
  };
}
