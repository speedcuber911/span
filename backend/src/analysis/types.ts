/**
 * Shared types for the Span scoring engine.
 * All score functions return ScoreResult; inputs carry explicit unit metadata.
 */

export type EvidenceTier = 1 | 2 | 3;

export interface InputUsed {
  /** Canonical parameter name */
  name: string;
  /** Value as consumed by the formula (post-conversion) */
  value: number;
  /** Unit of the value as consumed by the formula */
  unit: string;
  /** Raw input value (pre-conversion), if a conversion was applied */
  rawValue?: number;
  /** Raw input unit (pre-conversion), if a conversion was applied */
  rawUnit?: string;
  /** Description of unit transformation applied, e.g. "mg/dL * 10 -> g/L" */
  unit_xform?: string;
}

export interface ScoreResult {
  /** The computed score value (null if not computable) */
  value: number | null;
  /** Unit of the score output */
  unit: string;
  /**
   * Clinical interpretation band.
   * null = trend-only, no diagnostic cutoff (e.g. TyG, NLR)
   */
  band: string | null;
  /** Whether the score could be computed with the provided inputs */
  computable: boolean;
  /** Names of inputs that were missing and prevented computation */
  missingInputs: string[];
  /** Clinical or methodological caveats to surface to the user */
  caveats: string[];
  /** Evidence tier: 1=consensus, 2=promising, 3=contested */
  evidenceTier: EvidenceTier;
  /** Full provenance of each input value used, including unit conversions */
  inputsUsed: InputUsed[];
}

/** Extended result for PhenoAge which also returns delta vs chronological age */
export interface PhenoAgeResult extends ScoreResult {
  /** PhenoAge minus chronological age (positive = biologically older) */
  delta: number | null;
}

// ── Unit helper constants ───────────────────────────────────────────────────

export const ALBUMIN_GDL_TO_GL = 10;           // × 10
export const CREATININE_MGDL_TO_UMOLL = 88.42; // × 88.42
export const GLUCOSE_MGDL_TO_MMOLL = 1 / 18;   // ÷ 18
export const CRP_MGL_TO_MGDL = 1 / 10;         // ÷ 10 (mg/L → mg/dL)
