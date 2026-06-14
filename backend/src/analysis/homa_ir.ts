/**
 * HOMA-IR — Homeostatic Model Assessment of Insulin Resistance.
 *
 * Formula: (fasting_insulin[µU/mL] × fasting_glucose[mg/dL]) / 405
 *
 * Only computable when fasting insulin is available.
 * Most Indian routine panels do not include fasting insulin — this score
 * will commonly be unavailable; present TyG as an alternative.
 *
 * Evidence tier: 2 (validated surrogate; insulin assay variability is a
 * known limitation — values are not interchangeable across assay platforms).
 */

import type { ScoreResult, InputUsed } from './types.js';

export interface HomaIrInputs {
  /** Fasting insulin in µU/mL (also written as mIU/L — same numerically) */
  fasting_insulin_uU_ml: number | null | undefined;
  /** Fasting glucose in mg/dL */
  fasting_glucose_mgdl: number | null | undefined;
}

/**
 * Compute HOMA-IR.
 * Returns computable:false if fasting insulin is not present.
 */
export function computeHomaIr(inputs: HomaIrInputs): ScoreResult {
  const missingInputs: string[] = [];
  const caveats: string[] = [
    'insulin_assay_variability_limits_cross_lab_comparison',
    'fasting_state_required',
  ];
  const inputsUsed: InputUsed[] = [];

  if (inputs.fasting_insulin_uU_ml == null) missingInputs.push('fasting_insulin_uU_ml');
  if (inputs.fasting_glucose_mgdl == null) missingInputs.push('fasting_glucose_mgdl');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs,
      caveats,
      evidenceTier: 2,
      inputsUsed,
    };
  }

  const insulin = inputs.fasting_insulin_uU_ml as number;
  const glucose = inputs.fasting_glucose_mgdl as number;

  if (insulin <= 0 || glucose <= 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: [...caveats, 'inputs_must_be_positive'],
      evidenceTier: 2,
      inputsUsed,
    };
  }

  const homaIr = (insulin * glucose) / 405;

  inputsUsed.push({ name: 'fasting_insulin', value: insulin, unit: 'µU/mL' });
  inputsUsed.push({ name: 'fasting_glucose', value: glucose, unit: 'mg/dL' });

  // Soft reference band (population-based; varies by lab/assay)
  // IR commonly defined as > 2.0–2.5; no universal cutoff
  const band = homaIr < 1.0
    ? 'likely_sensitive'
    : homaIr < 2.5
    ? 'borderline'
    : 'insulin_resistant';

  return {
    value: homaIr,
    unit: 'index',
    band,
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 2,
    inputsUsed,
  };
}
