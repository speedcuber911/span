/**
 * NAFLD Fibrosis Score (NFS) — Advanced fibrosis in NAFLD/MASLD.
 * (Angulo et al., 2007, PMID 17393509)
 *
 * Formula:
 *   NFS = -1.675
 *         + 0.037  × age
 *         + 0.094  × BMI[kg/m²]
 *         + 1.13   × (IFG_or_diabetes ? 1 : 0)
 *         + 0.99   × (AST/ALT)
 *         - 0.013  × platelets[10^9/L]
 *         - 0.66   × albumin[g/dL]
 *
 * Bands:
 *   < -1.455   → exclude advanced fibrosis
 *   > 0.676    → advanced fibrosis
 *   between    → indeterminate
 *
 * GATED: requires BMI and diabetes/IFG flag (onboarding inputs).
 * If either is absent, computable:false.
 *
 * Evidence tier: 2 (validated but context-dependent).
 */

import type { ScoreResult, InputUsed } from './types.js';

export interface NafldFsInputs {
  /** Age in years */
  age: number | null | undefined;
  /** BMI in kg/m² — required (onboarding input) */
  bmi_kg_m2: number | null | undefined;
  /** Impaired fasting glucose OR known diabetes — required (onboarding input) */
  diabetes_or_ifg: boolean | null | undefined;
  /** AST in U/L */
  ast_ul: number | null | undefined;
  /** ALT in U/L */
  alt_ul: number | null | undefined;
  /** Platelets in 10^9/L */
  platelets_10_9L: number | null | undefined;
  /** Albumin in g/dL */
  albumin_gdl: number | null | undefined;
}

const BAND_EXCLUDE_UPPER = -1.455;
const BAND_ADVANCED_LOWER = 0.676;

function nafldFsBand(value: number): string {
  if (value < BAND_EXCLUDE_UPPER) return 'exclude_advanced';
  if (value > BAND_ADVANCED_LOWER) return 'advanced';
  return 'indeterminate';
}

/**
 * Compute NAFLD Fibrosis Score.
 */
export function computeNafldFs(inputs: NafldFsInputs): ScoreResult {
  const missingInputs: string[] = [];
  const caveats: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.age == null) missingInputs.push('age');
  if (inputs.bmi_kg_m2 == null) missingInputs.push('bmi_kg_m2');
  if (inputs.diabetes_or_ifg == null) missingInputs.push('diabetes_or_ifg');
  if (inputs.ast_ul == null) missingInputs.push('ast_ul');
  if (inputs.alt_ul == null) missingInputs.push('alt_ul');
  if (inputs.platelets_10_9L == null) missingInputs.push('platelets_10_9L');
  if (inputs.albumin_gdl == null) missingInputs.push('albumin_gdl');

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

  const age = inputs.age as number;
  const bmi = inputs.bmi_kg_m2 as number;
  const diabFlag = inputs.diabetes_or_ifg as boolean;
  const ast = inputs.ast_ul as number;
  const alt = inputs.alt_ul as number;
  const platelets = inputs.platelets_10_9L as number;
  const albumin = inputs.albumin_gdl as number;

  // Guard: ALT must be positive for AST/ALT ratio
  if (alt <= 0) {
    return {
      value: null,
      unit: 'index',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: ['alt_must_be_positive'],
      evidenceTier: 2,
      inputsUsed,
    };
  }

  const nfs =
    -1.675 +
    0.037 * age +
    0.094 * bmi +
    1.13 * (diabFlag ? 1 : 0) +
    0.99 * (ast / alt) -
    0.013 * platelets -
    0.66 * albumin;

  inputsUsed.push({ name: 'age', value: age, unit: 'years' });
  inputsUsed.push({ name: 'bmi', value: bmi, unit: 'kg/m²' });
  inputsUsed.push({ name: 'diabetes_or_ifg', value: diabFlag ? 1 : 0, unit: 'boolean_int' });
  inputsUsed.push({ name: 'ast', value: ast, unit: 'U/L' });
  inputsUsed.push({ name: 'alt', value: alt, unit: 'U/L' });
  inputsUsed.push({ name: 'platelets', value: platelets, unit: '10^9/L' });
  inputsUsed.push({ name: 'albumin', value: albumin, unit: 'g/dL' });

  caveats.push('bmi_and_diabetes_required_onboarding');

  return {
    value: nfs,
    unit: 'index',
    band: nafldFsBand(nfs),
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 2,
    inputsUsed,
  };
}
