/**
 * TyG Index — Triglyceride-Glucose Index (surrogate for insulin resistance).
 *
 * Formula: ln(triglycerides[mg/dL] × fasting_glucose[mg/dL] / 2)
 *
 * No universal diagnostic cutoff — trend and relative comparison only.
 * Band is always null; caveat 'no_cutoff_trend_only' is always present.
 *
 * No fasting insulin needed (unlike HOMA-IR), making this available for
 * most routine lab panels.
 *
 * Evidence tier: 2 (validated surrogate; no outcome RCT as primary endpoint).
 */

import type { ScoreResult, InputUsed } from './types.js';

export interface TygInputs {
  /** Triglycerides in mg/dL */
  triglycerides_mgdl: number | null | undefined;
  /** Fasting glucose in mg/dL */
  fasting_glucose_mgdl: number | null | undefined;
}

/**
 * Compute TyG index.
 */
export function computeTyg(inputs: TygInputs): ScoreResult {
  const missingInputs: string[] = [];
  const caveats: string[] = ['no_cutoff_trend_only'];
  const inputsUsed: InputUsed[] = [];

  if (inputs.triglycerides_mgdl == null) missingInputs.push('triglycerides_mgdl');
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

  const tg = inputs.triglycerides_mgdl as number;
  const fg = inputs.fasting_glucose_mgdl as number;

  if (tg <= 0 || fg <= 0) {
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

  const tyg = Math.log(tg * fg / 2);

  inputsUsed.push({ name: 'triglycerides', value: tg, unit: 'mg/dL' });
  inputsUsed.push({ name: 'fasting_glucose', value: fg, unit: 'mg/dL' });

  return {
    value: tyg,
    unit: 'index',
    band: null,
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 2,
    inputsUsed,
  };
}
