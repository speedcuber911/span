/**
 * Span Scoring Engine — public API.
 *
 * Re-exports all score functions and shared types.
 * All functions are pure, stateless, and deterministic.
 * No DB calls, no network calls, no side effects.
 */

// Shared types and unit helpers
export type {
  EvidenceTier,
  InputUsed,
  ScoreResult,
  PhenoAgeResult,
} from './types.js';

export {
  ALBUMIN_GDL_TO_GL,
  CREATININE_MGDL_TO_UMOLL,
  GLUCOSE_MGDL_TO_MMOLL,
  CRP_MGL_TO_MGDL,
} from './types.js';

// PhenoAge (Levine 2018)
export type { PhenoAgeInputs } from './phenoage.js';
export { computePhenoAge } from './phenoage.js';

// CKD-EPI 2021 eGFR (Inker et al., NEJM 2021)
export type { EgfrInputs, Sex } from './egfr.js';
export { computeEgfr } from './egfr.js';

// FIB-4 (Sterling 2006)
export type { Fib4Inputs } from './fib4.js';
export { computeFib4 } from './fib4.js';

// NAFLD Fibrosis Score (Angulo 2007)
export type { NafldFsInputs } from './nafld_fs.js';
export { computeNafldFs } from './nafld_fs.js';

// TyG Index
export type { TygInputs } from './tyg.js';
export { computeTyg } from './tyg.js';

// HOMA-IR
export type { HomaIrInputs } from './homa_ir.js';
export { computeHomaIr } from './homa_ir.js';

// Ratio soft-flags (NLR, AAR/De Ritis, PLR)
export type { NlrInputs, AarInputs, PlrInputs } from './ratios.js';
export { computeNlr, computeAar, computePlr } from './ratios.js';
