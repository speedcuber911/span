/**
 * PhenoAge — Biological age estimate (Levine 2018, PMC6388911).
 *
 * Accepts inputs in COMMON lab units and converts internally to the formula's
 * required units, recording each conversion in inputsUsed.
 *
 * Required common-unit inputs:
 *   albumin       g/dL     → formula uses g/L          (× 10)
 *   creatinine    mg/dL    → formula uses µmol/L        (× 88.42)
 *   glucose       mg/dL    → formula uses mmol/L         (÷ 18)
 *   crp           mg/L     → formula uses mg/dL          (÷ 10, then ln)
 *   lymphocyte    %        → no conversion
 *   mcv           fL       → no conversion
 *   rdw           %        → no conversion
 *   alp           U/L      → no conversion
 *   wbc           10^3/µL  → no conversion
 *   age           years    → no conversion
 *
 * Evidence tier: 2 (promising, validated; trained on NHANES — may not be
 * calibrated for Indian populations; caption caveats in UI).
 */

import type { PhenoAgeResult, InputUsed } from './types.js';
import {
  ALBUMIN_GDL_TO_GL,
  CREATININE_MGDL_TO_UMOLL,
  GLUCOSE_MGDL_TO_MMOLL,
  CRP_MGL_TO_MGDL,
} from './types.js';

export interface PhenoAgeInputs {
  /** Albumin in g/dL (common lab unit) */
  albumin_gdl: number | null | undefined;
  /** Creatinine in mg/dL (common lab unit) */
  creatinine_mgdl: number | null | undefined;
  /** Glucose (fasting or random) in mg/dL */
  glucose_mgdl: number | null | undefined;
  /** C-reactive protein in mg/L (common lab unit — NOT mg/dL) */
  crp_mgl: number | null | undefined;
  /** Lymphocyte percentage (%) */
  lymphocyte_pct: number | null | undefined;
  /** Mean corpuscular volume in fL */
  mcv_fl: number | null | undefined;
  /** Red cell distribution width (%) */
  rdw_pct: number | null | undefined;
  /** Alkaline phosphatase in U/L */
  alp_ul: number | null | undefined;
  /** White blood cell count in 10^3/µL */
  wbc_k_ul: number | null | undefined;
  /** Chronological age in years */
  age: number | null | undefined;
}

/**
 * The CRP limit of detection substitute used when CRP ≤ 0.
 * Using 0.01 mg/L (= 0.001 mg/dL) as a common LoD floor.
 */
const CRP_LOD_MGL = 0.01;

/**
 * Compute PhenoAge biological age (Levine 2018).
 *
 * All 9 biomarker inputs + age are required.
 * Returns computable:false with missingInputs populated if any are absent.
 */
export function computePhenoAge(inputs: PhenoAgeInputs): PhenoAgeResult {
  const missingInputs: string[] = [];
  const caveats: string[] = [];
  const inputsUsed: InputUsed[] = [];

  // ── Check for missing inputs ──────────────────────────────────────────────
  if (inputs.albumin_gdl == null) missingInputs.push('albumin_gdl');
  if (inputs.creatinine_mgdl == null) missingInputs.push('creatinine_mgdl');
  if (inputs.glucose_mgdl == null) missingInputs.push('glucose_mgdl');
  if (inputs.crp_mgl == null) missingInputs.push('crp_mgl');
  if (inputs.lymphocyte_pct == null) missingInputs.push('lymphocyte_pct');
  if (inputs.mcv_fl == null) missingInputs.push('mcv_fl');
  if (inputs.rdw_pct == null) missingInputs.push('rdw_pct');
  if (inputs.alp_ul == null) missingInputs.push('alp_ul');
  if (inputs.wbc_k_ul == null) missingInputs.push('wbc_k_ul');
  if (inputs.age == null) missingInputs.push('age');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'years',
      band: null,
      computable: false,
      missingInputs,
      caveats,
      evidenceTier: 2,
      inputsUsed,
      delta: null,
    };
  }

  // At this point TypeScript still sees these as possibly null from the type,
  // but we've confirmed above that none are null/undefined.
  const raw_albumin = inputs.albumin_gdl as number;
  const raw_creatinine = inputs.creatinine_mgdl as number;
  const raw_glucose = inputs.glucose_mgdl as number;
  const raw_crp = inputs.crp_mgl as number;
  const lymphocyte_pct = inputs.lymphocyte_pct as number;
  const mcv_fl = inputs.mcv_fl as number;
  const rdw_pct = inputs.rdw_pct as number;
  const alp_ul = inputs.alp_ul as number;
  const wbc_k_ul = inputs.wbc_k_ul as number;
  const age = inputs.age as number;

  // ── Unit conversions ──────────────────────────────────────────────────────

  // Albumin: g/dL → g/L (× 10)
  const albumin_gL = raw_albumin * ALBUMIN_GDL_TO_GL;
  inputsUsed.push({
    name: 'albumin',
    value: albumin_gL,
    unit: 'g/L',
    rawValue: raw_albumin,
    rawUnit: 'g/dL',
    unit_xform: 'g/dL * 10 -> g/L',
  });

  // Creatinine: mg/dL → µmol/L (× 88.42)
  const creatinine_umolL = raw_creatinine * CREATININE_MGDL_TO_UMOLL;
  inputsUsed.push({
    name: 'creatinine',
    value: creatinine_umolL,
    unit: 'µmol/L',
    rawValue: raw_creatinine,
    rawUnit: 'mg/dL',
    unit_xform: 'mg/dL * 88.42 -> µmol/L',
  });

  // Glucose: mg/dL → mmol/L (÷ 18)
  const glucose_mmolL = raw_glucose * GLUCOSE_MGDL_TO_MMOLL;
  inputsUsed.push({
    name: 'glucose',
    value: glucose_mmolL,
    unit: 'mmol/L',
    rawValue: raw_glucose,
    rawUnit: 'mg/dL',
    unit_xform: 'mg/dL / 18 -> mmol/L',
  });

  // CRP: mg/L → mg/dL (÷ 10); guard against ≤ 0 before ln
  let crp_mgdL = raw_crp * CRP_MGL_TO_MGDL;
  if (crp_mgdL <= 0) {
    caveats.push('crp_below_lod');
    crp_mgdL = CRP_LOD_MGL * CRP_MGL_TO_MGDL; // substitute LoD
  }
  const ln_crp = Math.log(crp_mgdL);
  inputsUsed.push({
    name: 'crp',
    value: crp_mgdL,
    unit: 'mg/dL',
    rawValue: raw_crp,
    rawUnit: 'mg/L',
    unit_xform: 'mg/L / 10 -> mg/dL (then ln in formula)',
  });

  // No conversion for these:
  inputsUsed.push({ name: 'lymphocyte_pct', value: lymphocyte_pct, unit: '%' });
  inputsUsed.push({ name: 'mcv', value: mcv_fl, unit: 'fL' });
  inputsUsed.push({ name: 'rdw', value: rdw_pct, unit: '%' });
  inputsUsed.push({ name: 'alp', value: alp_ul, unit: 'U/L' });
  inputsUsed.push({ name: 'wbc', value: wbc_k_ul, unit: '10^3/µL' });
  inputsUsed.push({ name: 'age', value: age, unit: 'years' });

  // ── Levine 2018 formula ───────────────────────────────────────────────────

  const xb =
    -19.90667 -
    0.03359355 * albumin_gL +
    0.009506491 * creatinine_umolL +
    0.1953192 * glucose_mmolL +
    0.09536762 * ln_crp -
    0.01199984 * lymphocyte_pct +
    0.02676401 * mcv_fl +
    0.3306156 * rdw_pct +
    0.001868778 * alp_ul +
    0.05542406 * wbc_k_ul +
    0.08035356 * age;

  // 10-year mortality score (Gompertz)
  const M = 1 - Math.exp((-1.51714 * Math.exp(xb)) / 0.0076927);

  // PhenoAge in years
  const phenoAge =
    141.50225 + Math.log(-0.0055305 * Math.log(1 - M)) / 0.090165;

  const delta = phenoAge - age;

  caveats.push('trained_nhanes3');
  caveats.push('not_calibrated_india');

  return {
    value: phenoAge,
    unit: 'years',
    band: null,
    computable: true,
    missingInputs: [],
    caveats,
    evidenceTier: 2,
    inputsUsed,
    delta,
  };
}
