/**
 * CKD-EPI 2021 race-free eGFR (Inker et al., NEJM 2021).
 *
 * Uses 2021 exponents:
 *   κ = 0.7 (F) / 0.9 (M)
 *   α = -0.241 (F) / -0.302 (M)
 *   exponent on max(Scr/κ, 1): -1.200 (both sexes)
 *
 * NOT the 2009 exponents (−0.329 F / −0.411 M), which this implementation
 * deliberately differs from.
 *
 * Input:  creatinine in mg/dL, age in years, sex as 'M' | 'F'
 * Output: eGFR in mL/min/1.73m²
 *
 * Missing sex → computable:false (no default assumed — the sex-specific
 * κ and α parameters are material, not a cosmetic multiplier).
 *
 * Evidence tier: 1 (consensus guideline formula, KDIGO 2021 endorsed).
 */

import type { ScoreResult, InputUsed } from './types.js';

export type Sex = 'M' | 'F';

export interface EgfrInputs {
  /** Serum creatinine in mg/dL */
  creatinine_mgdl: number | null | undefined;
  /** Age in years */
  age: number | null | undefined;
  /** Biological sex — required; no default assumed */
  sex: Sex | null | undefined;
}

/**
 * CKD-EPI 2021 eGFR classification bands.
 * Based on KDIGO G-stage thresholds.
 */
function egfrBand(egfr: number): string {
  if (egfr >= 90) return 'G1_normal_high';
  if (egfr >= 60) return 'G2_mildly_decreased';
  if (egfr >= 45) return 'G3a_mild_moderate';
  if (egfr >= 30) return 'G3b_moderate_severe';
  if (egfr >= 15) return 'G4_severely_decreased';
  return 'G5_kidney_failure';
}

/**
 * Compute CKD-EPI 2021 race-free eGFR.
 */
export function computeEgfr(inputs: EgfrInputs): ScoreResult {
  const missingInputs: string[] = [];
  const caveats: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.creatinine_mgdl == null) missingInputs.push('creatinine_mgdl');
  if (inputs.age == null) missingInputs.push('age');
  if (inputs.sex == null) missingInputs.push('sex');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'mL/min/1.73m²',
      band: null,
      computable: false,
      missingInputs,
      caveats,
      evidenceTier: 1,
      inputsUsed,
    };
  }

  const scr = inputs.creatinine_mgdl as number;
  const age = inputs.age as number;
  const sex = inputs.sex as Sex;

  // CKD-EPI 2021 race-free constants (NOT 2009)
  const k = sex === 'F' ? 0.7 : 0.9;
  const alpha = sex === 'F' ? -0.241 : -0.302;
  const sexMultiplier = sex === 'F' ? 1.012 : 1.0;

  const scrK = scr / k;

  const eGFR =
    142 *
    Math.pow(Math.min(scrK, 1), alpha) *
    Math.pow(Math.max(scrK, 1), -1.2) *
    Math.pow(0.9938, age) *
    sexMultiplier;

  inputsUsed.push({
    name: 'creatinine',
    value: scr,
    unit: 'mg/dL',
  });
  inputsUsed.push({ name: 'age', value: age, unit: 'years' });
  inputsUsed.push({ name: 'sex', value: sex === 'F' ? 0 : 1, unit: 'M/F' });

  caveats.push('ckd_epi_2021_race_free');

  return {
    value: eGFR,
    unit: 'mL/min/1.73m²',
    band: egfrBand(eGFR),
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 1,
    inputsUsed,
  };
}
