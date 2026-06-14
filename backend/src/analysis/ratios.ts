/**
 * Inflammatory / liver ratio soft-flags.
 * These are TREND INDICATORS, NOT diagnostic thresholds.
 *
 * NLR  — Neutrophil-to-Lymphocyte Ratio = absolute_neutrophils / absolute_lymphocytes
 * AAR  — AST-to-ALT Ratio (De Ritis ratio) = AST / ALT
 * PLR  — Platelet-to-Lymphocyte Ratio = platelets / absolute_lymphocytes
 *
 * All three:
 *   • band = null (no single diagnostic cutoff)
 *   • caveat 'context_dependent_not_diagnostic'
 *   • evidenceTier 3 (context-dependent; values can nudge organ-system tiles
 *     to "monitor" but NEVER alone to "attention")
 *
 * Absolute lymphocyte / neutrophil counts: cells × 10^3/µL (= 10^9/L).
 * Platelets: 10^9/L.
 */

import type { ScoreResult, InputUsed } from './types.js';

const SHARED_CAVEATS = ['context_dependent_not_diagnostic', 'trend_only_not_diagnostic'];

export interface NlrInputs {
  /** Absolute neutrophil count in 10^3/µL */
  neutrophils_k_ul: number | null | undefined;
  /** Absolute lymphocyte count in 10^3/µL */
  lymphocytes_k_ul: number | null | undefined;
}

export interface AarInputs {
  /** AST in U/L */
  ast_ul: number | null | undefined;
  /** ALT in U/L */
  alt_ul: number | null | undefined;
}

export interface PlrInputs {
  /** Platelets in 10^9/L */
  platelets_10_9L: number | null | undefined;
  /** Absolute lymphocyte count in 10^3/µL (= 10^9/L) */
  lymphocytes_k_ul: number | null | undefined;
}

/**
 * Neutrophil-to-Lymphocyte Ratio (NLR).
 */
export function computeNlr(inputs: NlrInputs): ScoreResult {
  const missingInputs: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.neutrophils_k_ul == null) missingInputs.push('neutrophils_k_ul');
  if (inputs.lymphocytes_k_ul == null) missingInputs.push('lymphocytes_k_ul');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs,
      caveats: [...SHARED_CAVEATS],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  const neut = inputs.neutrophils_k_ul as number;
  const lymph = inputs.lymphocytes_k_ul as number;

  if (lymph <= 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: [...SHARED_CAVEATS, 'lymphocytes_must_be_positive'],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  inputsUsed.push({ name: 'neutrophils', value: neut, unit: '10^3/µL' });
  inputsUsed.push({ name: 'lymphocytes', value: lymph, unit: '10^3/µL' });

  return {
    value: neut / lymph,
    unit: 'ratio',
    band: null,
    computable: true,
    missingInputs: [],
    caveats: [...SHARED_CAVEATS],
    evidenceTier: 3,
    inputsUsed,
  };
}

/**
 * AST/ALT Ratio — De Ritis ratio (AAR).
 */
export function computeAar(inputs: AarInputs): ScoreResult {
  const missingInputs: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.ast_ul == null) missingInputs.push('ast_ul');
  if (inputs.alt_ul == null) missingInputs.push('alt_ul');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs,
      caveats: [...SHARED_CAVEATS],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  const ast = inputs.ast_ul as number;
  const alt = inputs.alt_ul as number;

  if (alt <= 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: [...SHARED_CAVEATS, 'alt_must_be_positive'],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  inputsUsed.push({ name: 'ast', value: ast, unit: 'U/L' });
  inputsUsed.push({ name: 'alt', value: alt, unit: 'U/L' });

  return {
    value: ast / alt,
    unit: 'ratio',
    band: null,
    computable: true,
    missingInputs: [],
    caveats: [...SHARED_CAVEATS],
    evidenceTier: 3,
    inputsUsed,
  };
}

/**
 * Platelet-to-Lymphocyte Ratio (PLR).
 */
export function computePlr(inputs: PlrInputs): ScoreResult {
  const missingInputs: string[] = [];
  const inputsUsed: InputUsed[] = [];

  if (inputs.platelets_10_9L == null) missingInputs.push('platelets_10_9L');
  if (inputs.lymphocytes_k_ul == null) missingInputs.push('lymphocytes_k_ul');

  if (missingInputs.length > 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs,
      caveats: [...SHARED_CAVEATS],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  const platelets = inputs.platelets_10_9L as number;
  const lymph = inputs.lymphocytes_k_ul as number;

  if (lymph <= 0) {
    return {
      value: null,
      unit: 'ratio',
      band: null,
      computable: false,
      missingInputs: [],
      caveats: [...SHARED_CAVEATS, 'lymphocytes_must_be_positive'],
      evidenceTier: 3,
      inputsUsed,
    };
  }

  inputsUsed.push({ name: 'platelets', value: platelets, unit: '10^9/L' });
  inputsUsed.push({ name: 'lymphocytes', value: lymph, unit: '10^3/µL' });

  return {
    value: platelets / lymph,
    unit: 'ratio',
    band: null,
    computable: true,
    missingInputs: [],
    caveats: [...SHARED_CAVEATS],
    evidenceTier: 3,
    inputsUsed,
  };
}
