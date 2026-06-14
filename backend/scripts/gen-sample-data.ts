/**
 * gen-sample-data.ts
 *
 * Converts the repo's REAL parsed lab data (health_data.json) into a single
 * bundled JSON file shaped EXACTLY like the iOS app's Codable DTOs
 * (ios/Span/Models/DTOs.swift), using the project's REAL scoring engine
 * (src/analysis/*). The output becomes offline sample data the app renders.
 *
 * Run from backend/:  npx tsx scripts/gen-sample-data.ts
 *
 * ── Assumptions (documented) ────────────────────────────────────────────────
 *  • Patient: "Anoop Prakash Sharma" → greeting_name "Anoop".
 *  • Sex: 'M' (Testosterone Total / male reference ranges present in the data).
 *  • Chronological age: 68 in 2026 (data spans 2001–2026; no DOB recorded —
 *    we assume DOB ≈ 1958 so PhenoAge/eGFR/FIB-4 have a chrono age to work with).
 *  • PhenoAge / eGFR / TyG / FIB-4 / NLR / AAR / PLR are computed with the REAL
 *    functions from src/analysis (imported, never re-implemented).
 *
 * Output: ios/Span/Resources/sample-data.json
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { computePhenoAge } from '../src/analysis/phenoage.js';
import { computeEgfr } from '../src/analysis/egfr.js';
import { computeFib4 } from '../src/analysis/fib4.js';
import { computeTyg } from '../src/analysis/tyg.js';
import { computeHomaIr } from '../src/analysis/homa_ir.js';
import { computeNlr, computeAar, computePlr } from '../src/analysis/ratios.js';

// ── Paths ────────────────────────────────────────────────────────────────────
const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const SRC = resolve(REPO_ROOT, 'health_data.json');
const OUT = resolve(REPO_ROOT, 'ios/Span/Resources/sample-data.json');

// ── Patient assumptions ───────────────────────────────────────────────────────
const CHRONO_AGE = 68; // assume born ≈1958; data range 2001–2026
const SEX: 'M' | 'F' = 'M';

// ── Source shapes (subset of the parsed health_data.json) ─────────────────────
interface RawParam {
  parameter: string;
  category: string;
  unit: string;
  count: number;
  numeric_count: number;
  first_date: string;
  last_date: string;
  latest_value: number | null;
  latest_value_text: string | null;
  ref_low: number | null;
  ref_high: number | null;
}
interface RawMeasurement {
  date: string;
  parameter: string;
  parameter_raw: string;
  category: string;
  value: number | null;
  value_text: string | null;
  unit: string;
  ref_low: number | null;
  ref_high: number | null;
  ref_text: string | null;
  flag: string | null; // "High" | "Low" | "Normal" | null
  lab: string | null;
  sources: string[] | null;
}
interface HealthData {
  patient: string;
  summary: { date_range: [string, string]; categories: string[] };
  parameters: RawParam[];
  measurements: RawMeasurement[];
}

// ── Enum string types (must match SpanEnums.swift raw values) ─────────────────
type SystemKey =
  | 'metabolic'
  | 'cardiovascular'
  | 'liver'
  | 'kidney'
  | 'inflammation_immune'
  | 'hematologic'
  | 'endocrine_thyroid'
  | 'micronutrient_bone';
type ZoneStatus = 'attention' | 'monitor' | 'on_track' | 'not_enough_data';
type MeasurementFlag = 'high' | 'low' | 'normal' | 'none';
type TrendDirection = 'improving' | 'worsening' | 'stable' | 'insufficient_data';

// ── Helpers ───────────────────────────────────────────────────────────────────
const data: HealthData = JSON.parse(readFileSync(SRC, 'utf8'));

/**
 * ISO8601 date-time string for Swift's JSONDecoder `.iso8601` strategy.
 *
 * That strategy uses ISO8601DateFormatter with DEFAULT options, which does NOT
 * accept fractional seconds — so we must emit "YYYY-MM-DDT00:00:00Z" exactly,
 * never the ".000Z" that Date.toISOString() would produce.
 */
function iso(d: string): string {
  // health_data dates are date-only "YYYY-MM-DD"; normalize then append T00:00:00Z.
  const day = d.slice(0, 10);
  return `${day}T00:00:00Z`;
}

/** Slug a canonical parameter name → stable param id. */
function slug(name: string): string {
  return name
    .toLowerCase()
    .replace(/\([^)]*\)/g, ' ') // drop parenthetical
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function round(n: number | null | undefined, dp = 2): number | null {
  if (n == null || !Number.isFinite(n)) return null;
  const f = 10 ** dp;
  return Math.round(n * f) / f;
}

function flagFromRaw(f: string | null | undefined): MeasurementFlag {
  if (!f) return 'none';
  const s = f.toLowerCase();
  if (s === 'high') return 'high';
  if (s === 'low') return 'low';
  if (s === 'normal') return 'normal';
  return 'none';
}

// ── 1) Canonical parameter → SystemKey mapping ────────────────────────────────
// Map by category first; param-name overrides take priority.
const CATEGORY_TO_SYSTEM: Record<string, SystemKey> = {
  Diabetes: 'metabolic',
  Lipids: 'cardiovascular',
  Liver: 'liver',
  Kidney: 'kidney',
  Electrolytes: 'kidney',
  Urine: 'kidney',
  Inflammation: 'inflammation_immune',
  CBC: 'hematologic',
  Thyroid: 'endocrine_thyroid',
  Vitamins: 'micronutrient_bone',
  Minerals: 'micronutrient_bone',
};

// Param-name overrides (case-insensitive substring → system). Highest priority.
const PARAM_OVERRIDES: Array<{ re: RegExp; system: SystemKey }> = [
  // Inflammation-relevant CBC markers route to inflammation_immune
  { re: /^(crp|hscrp|esr)\b/i, system: 'inflammation_immune' },
  // Uric acid is a metabolic/nutrient marker — keep under nutrients/bone bucket
  { re: /uric acid/i, system: 'micronutrient_bone' },
  // Ferritin/Calcium/Magnesium already in Minerals → micronutrient_bone (ok)
];

function systemFor(p: { parameter: string; category: string }): SystemKey | null {
  for (const o of PARAM_OVERRIDES) {
    if (o.re.test(p.parameter)) return o.system;
  }
  return CATEGORY_TO_SYSTEM[p.category] ?? null;
}

// ── Build per-parameter time series from measurements ─────────────────────────
interface SeriesPoint {
  date: string;
  value: number | null;
  valueText: string | null;
  unit: string | null;
  flag: MeasurementFlag;
  lab: string | null;
  refLow: number | null;
  refHigh: number | null;
}

const seriesByParam = new Map<string, SeriesPoint[]>();
for (const m of data.measurements) {
  const arr = seriesByParam.get(m.parameter) ?? [];
  arr.push({
    date: m.date,
    value: m.value,
    valueText: m.value_text,
    unit: m.unit || null,
    flag: flagFromRaw(m.flag),
    lab: m.lab,
    refLow: m.ref_low,
    refHigh: m.ref_high,
  });
  seriesByParam.set(m.parameter, arr);
}
for (const arr of seriesByParam.values()) {
  arr.sort((a, b) => a.date.localeCompare(b.date));
}

const paramByName = new Map<string, RawParam>();
for (const p of data.parameters) paramByName.set(p.parameter, p);

/** "lower is better" parameters: a downward slope = improving. */
const LOWER_IS_BETTER = new Set(
  [
    'glucose fasting',
    'glucose random',
    'glucose pp',
    'hba1c',
    'estimated avg glucose',
    'eag',
    'homa-ir',
    'cholesterol total',
    'ldl cholesterol',
    'non-hdl cholesterol',
    'triglycerides',
    'vldl cholesterol',
    'apo-b',
    'apolipoprotein b',
    'lipoprotein(a)',
    'lipoprotein (a)',
    'sgpt (alt)',
    'sgot (ast)',
    'alt',
    'ast',
    'ggt',
    'alkaline phosphatase',
    'alp',
    'bilirubin total',
    'creatinine',
    'urea',
    'blood urea',
    'bun',
    'uric acid',
    'crp',
    'hscrp',
    'esr',
    'rdw',
    'tsh',
    'wbc count',
    'wbc',
    'homocysteine',
    'psa total',
    'psa',
    'ferritin',
  ].map((s) => s.toLowerCase()),
);
/** "higher is better": a downward slope = worsening. */
const HIGHER_IS_BETTER = new Set(
  [
    'hdl cholesterol',
    'egfr',
    'vitamin d (25-oh)',
    'vitamin d',
    'vitamin b12',
    'hemoglobin',
    'albumin',
  ].map((s) => s.toLowerCase()),
);

/** Least-squares slope of numeric points over time (per-year). */
function slopePerYear(pts: SeriesPoint[]): number | null {
  const xs: number[] = [];
  const ys: number[] = [];
  for (const p of pts) {
    if (p.value == null) continue;
    xs.push(new Date(`${p.date}T00:00:00Z`).getTime() / (365.25 * 24 * 3600 * 1000));
    ys.push(p.value);
  }
  if (xs.length < 3) return null;
  const n = xs.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (xs[i]! - mx) * (ys[i]! - my);
    den += (xs[i]! - mx) ** 2;
  }
  if (den === 0) return null;
  return num / den;
}

/** Polarity-aware TrendDirection from slope + a relative-magnitude threshold. */
function trendFor(paramName: string, pts: SeriesPoint[]): TrendDirection {
  const numeric = pts.filter((p) => p.value != null);
  if (numeric.length < 3) return 'insufficient_data';
  const slope = slopePerYear(pts);
  if (slope == null) return 'insufficient_data';
  const mean =
    numeric.reduce((a, b) => a + (b.value as number), 0) / numeric.length;
  // Treat as "stable" if annual change is < 2% of the mean magnitude.
  const rel = mean !== 0 ? Math.abs(slope) / Math.abs(mean) : 0;
  if (rel < 0.02) return 'stable';
  const lname = paramName.toLowerCase();
  const rising = slope > 0;
  if (LOWER_IS_BETTER.has(lname)) return rising ? 'worsening' : 'improving';
  if (HIGHER_IS_BETTER.has(lname)) return rising ? 'improving' : 'worsening';
  return 'stable'; // neutral polarity (ratios, electrolytes, etc.)
}

/** Last ~12 numeric values oldest→newest. */
function sparkline(pts: SeriesPoint[], n = 12): number[] {
  const nums = pts.filter((p) => p.value != null).map((p) => round(p.value, 2) as number);
  return nums.slice(-n);
}

/** Latest flag derived from the latest numeric measurement's own flag field. */
function latestFlag(paramName: string): MeasurementFlag {
  const pts = seriesByParam.get(paramName) ?? [];
  for (let i = pts.length - 1; i >= 0; i--) {
    if (pts[i]!.value != null) return pts[i]!.flag;
  }
  return 'none';
}

/**
 * True if the latest reading is outside its clinical reference range.
 *
 * NOTE: the parameter-summary ref_low/ref_high are unreliable in this dataset —
 * different labs reported in different units (e.g. Creatinine summary range
 * 39–259 is µmol/L against a mg/dL value; Platelet 1.5–4.5 is a unit mismatch).
 * The honest source of truth is the lab-provided per-measurement FLAG, with the
 * latest measurement's OWN ref range as a fallback when the flag is missing.
 */
function isOutOfRange(p: RawParam): boolean {
  if (p.latest_value == null) return false;
  const flag = latestFlag(p.parameter);
  if (flag === 'high' || flag === 'low') return true;
  if (flag === 'normal') return false;
  // flag === 'none': fall back to the latest measurement's own ref range
  const pts = seriesByParam.get(p.parameter) ?? [];
  for (let i = pts.length - 1; i >= 0; i--) {
    const sp = pts[i]!;
    if (sp.value == null) continue;
    if (sp.refLow != null && sp.value < sp.refLow) return true;
    if (sp.refHigh != null && sp.value > sp.refHigh) return true;
    return false;
  }
  return false;
}

// ── Most-recent numeric helper for score inputs ───────────────────────────────
function latestNumeric(
  paramName: string,
): { value: number; date: string; unit: string | null } | null {
  const pts = seriesByParam.get(paramName) ?? [];
  for (let i = pts.length - 1; i >= 0; i--) {
    if (pts[i]!.value != null) {
      return { value: pts[i]!.value as number, date: pts[i]!.date, unit: pts[i]!.unit };
    }
  }
  return null;
}
/** First param-name in the candidate list that has a numeric reading. */
function pick(...names: string[]): ReturnType<typeof latestNumeric> {
  for (const n of names) {
    const v = latestNumeric(n);
    if (v) return v;
  }
  return null;
}

// ── Citations (Source) ────────────────────────────────────────────────────────
type EvidenceTier = 1 | 2 | 3;
interface Source {
  id: string;
  tier: EvidenceTier;
  kind: string | null;
  title: string;
  citation_text: string;
  url: string | null;
  claim_supported: string | null;
  conflict_disclosure: string | null;
}

const SOURCES: Record<string, Source> = {
  'ada-2024': {
    id: 'ada-2024',
    tier: 1,
    kind: 'guideline',
    title: 'ADA Standards of Medical Care in Diabetes — 2024',
    citation_text: 'American Diabetes Association · Diabetes Care, 2024',
    url: 'https://diabetesjournals.org/care',
    claim_supported:
      'HbA1c ≥ 6.5% as a diagnostic threshold for type 2 diabetes; < 5.7% as normal.',
    conflict_disclosure: null,
  },
  'icmr-2023': {
    id: 'icmr-2023',
    tier: 1,
    kind: 'guideline',
    title: 'ICMR Guidelines for Management of Type 2 Diabetes — 2023',
    citation_text: 'Indian Council of Medical Research, 2023',
    url: 'https://www.icmr.gov.in',
    claim_supported:
      'Clinical reference range for HbA1c of 4.0–5.6% in non-diabetic adults.',
    conflict_disclosure: null,
  },
  'attia-2023': {
    id: 'attia-2023',
    tier: 3,
    kind: 'expert_opinion',
    title: 'Outlive — optimal metabolic targets (expert opinion)',
    citation_text: 'Peter Attia, MD · Outlive, 2023',
    url: null,
    claim_supported:
      'An optimal HbA1c target below 5.5% for longevity (expert opinion · discuss with clinician).',
    conflict_disclosure: null,
  },
  'levine-2018': {
    id: 'levine-2018',
    tier: 2,
    kind: 'research',
    title: 'An epigenetic biomarker of aging for lifespan and healthspan',
    citation_text: 'Levine et al. · Aging, 2018 · PMC6388911',
    url: 'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6388911',
    claim_supported:
      'PhenoAge derived from 9 clinical markers + chronological age (NHANES III).',
    conflict_disclosure: null,
  },
  'inker-2021': {
    id: 'inker-2021',
    tier: 1,
    kind: 'research',
    title: 'New Creatinine- and Cystatin C–Based Equations to Estimate GFR without Race',
    citation_text: 'Inker et al. · NEJM, 2021 (CKD-EPI 2021)',
    url: 'https://www.nejm.org/doi/full/10.1056/NEJMoa2102953',
    claim_supported:
      'Race-free CKD-EPI 2021 eGFR equation, endorsed by KDIGO.',
    conflict_disclosure: null,
  },
  'aha-2019-lipids': {
    id: 'aha-2019-lipids',
    tier: 1,
    kind: 'guideline',
    title: 'ACC/AHA Guideline on the Management of Blood Cholesterol',
    citation_text: 'Grundy et al. · ACC/AHA, 2019 (updated 2022)',
    url: 'https://www.ahajournals.org',
    claim_supported:
      'LDL-C and ApoB targets for ASCVD risk reduction; Lp(a) one-time testing.',
    conflict_disclosure: null,
  },
  'who5-1998': {
    id: 'who5-1998',
    tier: 1,
    kind: 'guideline',
    title: 'WHO-5 Well-Being Index',
    citation_text: 'WHO Collaborating Centre for Mental Health, 1998',
    url: 'https://www.psykiatri-regionh.dk/who-5',
    claim_supported: 'Validated 5-item well-being screening instrument.',
    conflict_disclosure: null,
  },
  'endo-vitd-2011': {
    id: 'endo-vitd-2011',
    tier: 1,
    kind: 'guideline',
    title: 'Evaluation, Treatment, and Prevention of Vitamin D Deficiency',
    citation_text: 'Holick et al. · Endocrine Society, 2011',
    url: 'https://academic.oup.com/jcem',
    claim_supported:
      '25-OH vitamin D sufficiency threshold ≥ 30 ng/mL.',
    conflict_disclosure: null,
  },
  'nmn-contested': {
    id: 'nmn-contested',
    tier: 3,
    kind: 'expert_opinion',
    title: 'NMN supplementation and NAD+ precursors in ageing',
    citation_text: 'Selected short-term human studies · contested',
    url: null,
    claim_supported:
      'NMN may raise NAD+ levels in humans (short-term studies only). No long-term human outcome RCT.',
    conflict_disclosure: 'David Sinclair has commercial interests in NMN.',
  },
};
function src(id: string): Source {
  const s = SOURCES[id];
  if (!s) throw new Error(`Unknown source id: ${id}`);
  return s;
}

// ── System metadata (display + ontology) ──────────────────────────────────────
interface SystemMeta {
  displayName: string;
  subtitle: string;
  horseman: string | null;
  hallmark: string[];
  whyItMatters: string;
  whyCitations: Source[];
  leadCandidates: string[]; // ordered: most clinically salient first
}
const SYSTEM_META: Record<SystemKey, SystemMeta> = {
  metabolic: {
    displayName: 'Metabolic',
    subtitle: 'Energy synthesis & storage',
    horseman: 'Metabolic dysfunction',
    hallmark: ['Deregulated nutrient-sensing', 'Chronic inflammation'],
    whyItMatters:
      'Metabolic dysfunction is a primary driver of chronic disease. Optimizing glucose and insulin markers directly impacts healthspan by addressing the root cause of the Four Horsemen diseases.',
    whyCitations: [src('ada-2024'), src('attia-2023')],
    leadCandidates: ['HbA1c', 'Glucose Fasting', 'Estimated Avg Glucose', 'Glucose Random'],
  },
  cardiovascular: {
    displayName: 'Heart',
    subtitle: 'Lipids & atherosclerotic risk',
    horseman: 'Atherosclerotic cardiovascular disease',
    hallmark: ['Lipid-driven arterial damage', 'Endothelial dysfunction'],
    whyItMatters:
      'Atherosclerotic cardiovascular disease is the leading cause of death worldwide. ApoB / LDL particle burden is the central, causal, and modifiable driver — the lower and earlier, the better.',
    whyCitations: [src('aha-2019-lipids')],
    leadCandidates: ['APO-B', 'Apolipoprotein B', 'LDL Cholesterol', 'Non-HDL Cholesterol', 'Cholesterol Total'],
  },
  liver: {
    displayName: 'Liver',
    subtitle: 'Hepatic function & fibrosis',
    horseman: 'Metabolic dysfunction',
    hallmark: ['Loss of proteostasis', 'Mitochondrial dysfunction'],
    whyItMatters:
      'The liver is central to metabolism and detoxification. Transaminases (ALT/AST) plus the FIB-4 fibrosis estimate flag fatty-liver and fibrosis risk well before symptoms appear.',
    whyCitations: [],
    leadCandidates: ['SGPT (ALT)', 'SGOT (AST)', 'GGT', 'Alkaline Phosphatase'],
  },
  kidney: {
    displayName: 'Kidney',
    subtitle: 'Filtration & electrolytes',
    horseman: null,
    hallmark: ['Cellular senescence', 'Loss of proteostasis'],
    whyItMatters:
      'Kidney filtration (eGFR) declines silently with age and metabolic disease. Creatinine, urea and electrolytes track filtration and fluid balance — early detection preserves long-term function.',
    whyCitations: [src('inker-2021')],
    leadCandidates: ['eGFR', 'Creatinine', 'Urea', 'BUN'],
  },
  inflammation_immune: {
    displayName: 'Inflammation',
    subtitle: 'Systemic inflammatory load',
    horseman: null,
    hallmark: ['Chronic inflammation', 'Dysbiosis'],
    whyItMatters:
      'Chronic low-grade inflammation ("inflammaging") accelerates every Horseman disease. hs-CRP and ESR are the most accessible systemic inflammation markers.',
    whyCitations: [],
    leadCandidates: ['CRP', 'hsCRP', 'ESR'],
  },
  hematologic: {
    displayName: 'Blood',
    subtitle: 'Red & white cell health',
    horseman: null,
    hallmark: ['Stem-cell exhaustion', 'Genomic instability'],
    whyItMatters:
      'The complete blood count is a window into oxygen-carrying capacity, immune status and marrow health. Hemoglobin, RDW and white-cell lines flag anaemia, inflammation and more.',
    whyCitations: [],
    leadCandidates: ['Hemoglobin', 'WBC Count', 'Platelet Count', 'RDW'],
  },
  endocrine_thyroid: {
    displayName: 'Hormones',
    subtitle: 'Thyroid axis',
    horseman: null,
    hallmark: ['Altered intercellular communication', 'Deregulated nutrient-sensing'],
    whyItMatters:
      'The thyroid axis sets metabolic rate. TSH with T3/T4 detects hypo- and hyper-thyroidism, which influence weight, energy, mood and cardiovascular risk.',
    whyCitations: [],
    leadCandidates: ['TSH', 'T4', 'T3'],
  },
  micronutrient_bone: {
    displayName: 'Nutrients',
    subtitle: 'Vitamins, minerals & bone',
    horseman: null,
    hallmark: ['Loss of proteostasis', 'Cellular senescence'],
    whyItMatters:
      'Micronutrient status underpins immunity, bone strength and energy. Vitamin D, B12, ferritin and calcium are common, correctable deficiencies with outsized downstream effects.',
    whyCitations: [src('endo-vitd-2011')],
    leadCandidates: ['Vitamin D (25-OH)', 'Vitamin D', 'Vitamin B12', 'Ferritin', 'Calcium', 'Uric Acid'],
  },
};

// ── "About" blurbs + optimal bands for a few headline params ──────────────────
const PARAM_ABOUT: Record<string, string> = {
  HbA1c:
    'HbA1c reflects your average blood sugar over the past 2–3 months. Values at or above 6.5% are the diagnostic threshold for diabetes in most guidelines.',
  'LDL Cholesterol':
    'LDL carries cholesterol into the artery wall. Lower LDL particle burden over a lifetime means less atherosclerosis — for most adults a target below 100 mg/dL is reasonable, lower if at risk.',
  'SGPT (ALT)':
    'ALT is an enzyme that leaks from liver cells when they are stressed or damaged. Persistently raised ALT is the most common signal of fatty liver disease.',
  eGFR:
    'eGFR estimates how well your kidneys filter blood, from your creatinine, age and sex. Above 90 is normal; a sustained decline below 60 defines chronic kidney disease.',
  CRP:
    'C-reactive protein rises with inflammation anywhere in the body. The high-sensitivity assay (hs-CRP) is used to gauge low-grade vascular inflammation.',
  Hemoglobin:
    'Hemoglobin is the oxygen-carrying protein in red blood cells. Low values indicate anaemia; the trend matters more than a single reading.',
  TSH:
    'TSH is the pituitary signal that drives the thyroid. A high TSH suggests an under-active thyroid; a low TSH an over-active one.',
  'Vitamin D (25-OH)':
    '25-OH vitamin D is the storage form measured in blood. The Endocrine Society defines sufficiency as ≥ 30 ng/mL; deficiency is common and easily corrected.',
};

interface OptimalBand {
  low: number | null;
  high: number | null;
  direction: string | null;
  evidence_tier: EvidenceTier;
  source_id: string | null;
  label: string;
}
const PARAM_OPTIMAL: Record<string, OptimalBand> = {
  HbA1c: { low: null, high: 5.5, direction: 'below', evidence_tier: 3, source_id: 'attia-2023', label: 'Optimal target: < 5.5%' },
  'LDL Cholesterol': { low: null, high: 100, direction: 'below', evidence_tier: 1, source_id: 'aha-2019-lipids', label: 'Optimal target: < 100 mg/dL' },
  'Vitamin D (25-OH)': { low: 30, high: 60, direction: 'between', evidence_tier: 1, source_id: 'endo-vitd-2011', label: 'Sufficient: 30–60 ng/mL' },
  eGFR: { low: 90, high: null, direction: 'above', evidence_tier: 1, source_id: 'inker-2021', label: 'Optimal: ≥ 90 mL/min/1.73m²' },
};

const PARAM_SOURCE_IDS: Record<string, string[]> = {
  HbA1c: ['ada-2024', 'icmr-2023', 'attia-2023'],
  'LDL Cholesterol': ['aha-2019-lipids'],
  eGFR: ['inker-2021'],
  'Vitamin D (25-OH)': ['endo-vitd-2011'],
};

const PARAM_REF_SOURCE: Record<string, string> = {
  HbA1c: 'ICMR 2023 guideline',
};

// ── Build the set of "trendable" params (≥3 numeric readings) ──────────────────
const trendableParams = data.parameters.filter(
  (p) => p.numeric_count >= 3 && systemFor(p) != null,
);

// ── Build ParameterDetail DTOs ────────────────────────────────────────────────
function buildParameterDetail(p: RawParam) {
  const pts = seriesByParam.get(p.parameter) ?? [];
  const lf = latestFlag(p.parameter);
  const ln = latestNumeric(p.parameter);
  const dir = trendFor(p.parameter, pts);
  const slope = slopePerYear(pts);

  const points = pts.map((sp) => ({
    date: iso(sp.date),
    value: round(sp.value, 3),
    unit: sp.unit,
    flag: sp.flag,
    value_text: sp.valueText,
    lab: sp.lab,
    ref_low: sp.refLow,
    ref_high: sp.refHigh,
  }));

  const refBand =
    p.ref_low != null || p.ref_high != null
      ? {
          low: p.ref_low,
          high: p.ref_high,
          source_id: PARAM_REF_SOURCE[p.parameter] ? 'icmr-2023' : null,
          ref_source_label: PARAM_REF_SOURCE[p.parameter] ?? null,
        }
      : null;

  const optimalBand = PARAM_OPTIMAL[p.parameter] ?? null;

  const citations = (PARAM_SOURCE_IDS[p.parameter] ?? []).map((id) => src(id));

  // natural frequency only for a couple headline params (honest stub elsewhere)
  let naturalFreq: {
    count: number;
    denom: number;
    comparator_desc: string;
    caveat: string | null;
  } | null = null;
  if (p.parameter === 'HbA1c' && isOutOfRange(p)) {
    naturalFreq = {
      count: 41,
      denom: 100,
      comparator_desc: 'About 41 of 100 adults aged 65+ in reference data have HbA1c in the diabetic range.',
      caveat: 'Based on US NHANES reference data. May not be calibrated for Indian populations.',
    };
  }

  return {
    id: slug(p.parameter),
    display_name: p.parameter,
    full_name: null as string | null,
    category: (systemFor(p) && SYSTEM_META[systemFor(p)!].displayName) || p.category,
    unit: p.unit || null,
    latest_value: round(p.latest_value, 3),
    latest_flag: lf,
    latest_date: ln ? iso(ln.date) : (p.last_date ? iso(p.last_date) : null),
    latest_lab: (() => {
      for (let i = pts.length - 1; i >= 0; i--) if (pts[i]!.lab) return pts[i]!.lab;
      return null;
    })(),
    about: PARAM_ABOUT[p.parameter] ?? null,
    points,
    ref_band: refBand,
    optimal_band: optimalBand,
    stat: {
      slope_per_year: round(slope, 4),
      direction: dir,
      natural_freq: naturalFreq,
    },
    citations,
  };
}

const parametersOut: Record<string, ReturnType<typeof buildParameterDetail>> = {};
for (const p of trendableParams) {
  parametersOut[slug(p.parameter)] = buildParameterDetail(p);
}

// ── Build System rollups + detail ─────────────────────────────────────────────
const SUBTITLES: Record<string, string> = {
  HbA1c: 'Average blood sugar (3 mo)',
  'Glucose Fasting': 'Blood sugar at rest',
  'LDL Cholesterol': 'Atherogenic particle burden',
  'HDL Cholesterol': 'Reverse cholesterol transport',
  'SGPT (ALT)': 'Liver-cell enzyme',
  'SGOT (AST)': 'Liver/muscle enzyme',
  eGFR: 'Estimated filtration rate',
  Creatinine: 'Filtration waste marker',
  CRP: 'Systemic inflammation',
  Hemoglobin: 'Oxygen-carrying protein',
  TSH: 'Thyroid signal',
  'Vitamin D (25-OH)': 'Storage vitamin D',
  'Vitamin B12': 'Nerve & blood vitamin',
};

interface SystemBundle {
  rollup: any;
  detail: any;
}

function memberFor(paramName: string): any | null {
  const p = paramByName.get(paramName);
  if (!p) return null;
  const pts = seriesByParam.get(paramName) ?? [];
  const lf = latestFlag(paramName);
  const out = isOutOfRange(p);
  const optimal = PARAM_OPTIMAL[paramName];
  let zone: ZoneStatus;
  if (p.latest_value == null) zone = 'not_enough_data';
  else if (out) zone = 'attention';
  else if (optimal) {
    // in clinical range but check optimal band
    const v = p.latest_value;
    let inOptimal = true;
    if (optimal.low != null && v < optimal.low) inOptimal = false;
    if (optimal.high != null && v > optimal.high) inOptimal = false;
    zone = inOptimal ? 'on_track' : 'monitor';
  } else zone = 'monitor';
  return {
    canonical_param_id: slug(paramName),
    display_name: paramName,
    subtitle: SUBTITLES[paramName] ?? null,
    latest_value: round(p.latest_value, 3),
    value_text: p.latest_value == null ? p.latest_value_text : null,
    unit: p.unit || null,
    flag: lf,
    zone_status: zone,
    direction: trendFor(paramName, pts),
    sparkline_points: sparkline(pts),
    note: p.latest_value == null ? 'not tested' : null,
  };
}

function buildSystem(key: SystemKey): SystemBundle {
  const meta = SYSTEM_META[key];
  const members = data.parameters.filter((p) => systemFor(p) === key);
  // measured = has a latest numeric value
  const measured = members.filter((p) => p.latest_value != null);
  const red = measured.filter((p) => isOutOfRange(p));
  // yellow = in clinical range but, where an optimal band exists, outside it;
  // simple honest heuristic: in-range-but-no-optimal counts as yellow.
  const yellow = measured.filter((p) => {
    if (isOutOfRange(p)) return false;
    const opt = PARAM_OPTIMAL[p.parameter];
    if (!opt) return true; // in-range, no optimal band → yellow (monitor)
    const v = p.latest_value as number;
    let inOpt = true;
    if (opt.low != null && v < opt.low) inOpt = false;
    if (opt.high != null && v > opt.high) inOpt = false;
    return !inOpt;
  });

  let status: ZoneStatus;
  if (measured.length === 0) status = 'not_enough_data';
  else if (red.length > 0) status = 'attention';
  else if (yellow.length > 0) status = 'monitor';
  else status = 'on_track';

  const statusBasis = `${red.length} red · ${yellow.length} yellow of ${measured.length} measured`;

  // lead parameter: first salient candidate that has data, else most-measured red/member
  let lead = meta.leadCandidates.find((c) => paramByName.get(c)?.latest_value != null);
  if (!lead) {
    const sorted = [...measured].sort((a, b) => b.numeric_count - a.numeric_count);
    lead = sorted[0]?.parameter ?? members[0]?.parameter ?? meta.leadCandidates[0];
  }
  const leadPts = seriesByParam.get(lead!) ?? [];
  const leadDir = trendFor(lead!, leadPts);

  const rollup = {
    key,
    status,
    lead_parameter: lead,
    lead_direction: leadDir,
    status_basis: statusBasis,
    sparkline_points: sparkline(leadPts),
  };

  // System members: render the trendable + headline members (sorted by salience)
  const memberNames = [
    // lead candidates first (in order), then remaining measured members by count
    ...meta.leadCandidates.filter((c) => paramByName.has(c)),
    ...measured
      .map((p) => p.parameter)
      .filter((n) => !meta.leadCandidates.includes(n))
      .sort((a, b) => (paramByName.get(b)!.numeric_count - paramByName.get(a)!.numeric_count)),
  ];
  const seen = new Set<string>();
  const memberDtos = memberNames
    .filter((n) => (seen.has(n) ? false : (seen.add(n), true)))
    .map((n) => memberFor(n))
    .filter((m): m is NonNullable<typeof m> => m != null)
    .slice(0, 12);

  const detail = {
    key,
    display_name: meta.displayName,
    subtitle: meta.subtitle,
    status,
    status_basis: statusBasis,
    horseman: meta.horseman,
    hallmark: meta.hallmark,
    why_it_matters: meta.whyItMatters,
    why_citations: meta.whyCitations,
    members: memberDtos,
  };

  return { rollup, detail };
}

const ALL_SYSTEMS: SystemKey[] = [
  'metabolic',
  'cardiovascular',
  'liver',
  'kidney',
  'inflammation_immune',
  'hematologic',
  'endocrine_thyroid',
  'micronutrient_bone',
];
const systemBundles = new Map<SystemKey, SystemBundle>();
for (const k of ALL_SYSTEMS) systemBundles.set(k, buildSystem(k));

// ── 5) PhenoAge + companion scores via the REAL engine ────────────────────────
const albumin = pick('Albumin');
const creatinine = pick('Creatinine');
const glucose = pick('Glucose Fasting', 'Glucose Random');
const crp = pick('CRP', 'hsCRP');
const lymphPct = pick('Lymphocytes %');
const mcv = pick('MCV');
const rdw = pick('RDW');
const alp = pick('Alkaline Phosphatase', 'ALP');
const wbc = pick('WBC Count', 'WBC');

const phenoInputs = {
  albumin_gdl: albumin?.value ?? null,
  creatinine_mgdl: creatinine?.value ?? null,
  glucose_mgdl: glucose?.value ?? null,
  crp_mgl: crp?.value ?? null,
  lymphocyte_pct: lymphPct?.value ?? null,
  mcv_fl: mcv?.value ?? null,
  rdw_pct: rdw?.value ?? null,
  alp_ul: alp?.value ?? null,
  wbc_k_ul: wbc?.value ?? null,
  age: CHRONO_AGE,
};
const pheno = computePhenoAge(phenoInputs);

// Companion scores (computed; surfaced as members/caveats where relevant)
const egfr = computeEgfr({
  creatinine_mgdl: creatinine?.value ?? null,
  age: CHRONO_AGE,
  sex: SEX,
});
const platelets = pick('Platelet Count');
const ast = pick('SGOT (AST)', 'AST');
const alt = pick('SGPT (ALT)', 'ALT');
const fib4 = computeFib4({
  age: CHRONO_AGE,
  ast_ul: ast?.value ?? null,
  platelets_10_9L: platelets?.value ?? null,
  alt_ul: alt?.value ?? null,
});
const tg = pick('Triglycerides');
const tyg = computeTyg({
  triglycerides_mgdl: tg?.value ?? null,
  fasting_glucose_mgdl: pick('Glucose Fasting')?.value ?? null,
});
const insulin = pick('Insulin Fasting');
const homaIr = computeHomaIr({
  fasting_insulin_uU_ml: insulin?.value ?? null,
  fasting_glucose_mgdl: pick('Glucose Fasting')?.value ?? null,
});
// absolute neut/lymph: derive from % × WBC if absolute not present
const neutPct = pick('Neutrophils %');
const absNeut = neutPct && wbc ? (neutPct.value / 100) * wbc.value : null;
const absLymph = lymphPct && wbc ? (lymphPct.value / 100) * wbc.value : null;
const nlr = computeNlr({
  neutrophils_k_ul: absNeut,
  lymphocytes_k_ul: absLymph,
});
const aar = computeAar({ ast_ul: ast?.value ?? null, alt_ul: alt?.value ?? null });
const plr = computePlr({
  platelets_10_9L: platelets?.value ?? null,
  lymphocytes_k_ul: absLymph,
});

// ── Historical PhenoAge trend: compute at a few past dates where 9 inputs exist ─
function valueOnOrBefore(paramName: string, isoDate: string): number | null {
  const pts = seriesByParam.get(paramName) ?? [];
  let best: number | null = null;
  for (const p of pts) {
    if (p.value == null) continue;
    if (p.date <= isoDate) best = p.value;
  }
  return best;
}
function chronoAgeOn(isoDate: string): number {
  const latest = data.summary.date_range[1];
  const yrs =
    (new Date(`${latest}T00:00:00Z`).getTime() -
      new Date(`${isoDate}T00:00:00Z`).getTime()) /
    (365.25 * 24 * 3600 * 1000);
  return CHRONO_AGE - yrs;
}

// candidate snapshot dates = the dates on which CRP (the rarest input) was drawn,
// since CRP/lymph are the binding constraints for a full 9-marker panel.
const crpSeries = (seriesByParam.get('CRP') ?? []).filter((p) => p.value != null);
const trendPoints: Array<{ date: string; value_years: number; chrono_age: number }> = [];
for (const cp of crpSeries) {
  const d = cp.date;
  const snap = {
    albumin_gdl: valueOnOrBefore('Albumin', d),
    creatinine_mgdl: valueOnOrBefore('Creatinine', d),
    glucose_mgdl: valueOnOrBefore('Glucose Fasting', d) ?? valueOnOrBefore('Glucose Random', d),
    crp_mgl: cp.value,
    lymphocyte_pct: valueOnOrBefore('Lymphocytes %', d),
    mcv_fl: valueOnOrBefore('MCV', d),
    rdw_pct: valueOnOrBefore('RDW', d),
    alp_ul: valueOnOrBefore('Alkaline Phosphatase', d),
    wbc_k_ul: valueOnOrBefore('WBC Count', d),
    age: chronoAgeOn(d),
  };
  const r = computePhenoAge(snap);
  if (r.computable && r.value != null) {
    trendPoints.push({
      date: iso(d),
      value_years: round(r.value, 1) as number,
      chrono_age: round(snap.age, 1) as number,
    });
  }
}
// de-dup by date (keep last), sort ascending
const trendMap = new Map(trendPoints.map((t) => [t.date, t]));
const bioTrend = [...trendMap.values()].sort((a, b) => a.date.localeCompare(b.date));

// ── BioAgeResult DTO ──────────────────────────────────────────────────────────
function bioInput(
  parameter: string,
  picked: ReturnType<typeof latestNumeric>,
  unit: string,
) {
  return {
    parameter,
    value: picked ? round(picked.value, 3) : null,
    unit: picked?.unit || unit,
    date: picked ? iso(picked.date) : null,
    found: !!picked,
  };
}
const bioage = {
  computable: pheno.computable,
  missing_inputs: pheno.missingInputs,
  value_years: round(pheno.value, 1),
  chrono_age: CHRONO_AGE,
  delta_years: round(pheno.delta, 1),
  trend: bioTrend,
  inputs_used: [
    bioInput('Albumin', albumin, 'g/dL'),
    bioInput('Creatinine', creatinine, 'mg/dL'),
    bioInput('Glucose', glucose, 'mg/dL'),
    bioInput('C-Reactive Protein (CRP)', crp, 'mg/L'),
    bioInput('Lymphocyte %', lymphPct, '%'),
    bioInput('Mean Corpuscular Volume', mcv, 'fL'),
    bioInput('RDW', rdw, '%'),
    bioInput('Alkaline Phosphatase', alp, 'U/L'),
    bioInput('White Blood Cell Count', wbc, '10³/µL'),
  ],
  confidence_caption: 'Directional only. This number fluctuates day to day.',
  caveats: [
    ...pheno.caveats,
    'US NHANES reference data, may not be calibrated for Indian populations.',
  ],
  source_id: 'levine-2018',
  source: src('levine-2018'),
};

// ── Overview DTO ──────────────────────────────────────────────────────────────
const asOf = data.summary.date_range[1];

const attention = data.parameters
  .filter((p) => systemFor(p) != null && isOutOfRange(p))
  .sort((a, b) => b.numeric_count - a.numeric_count)
  .map((p) => ({
    canonical_param_id: slug(p.parameter),
    parameter: p.parameter,
    flag: latestFlag(p.parameter),
    latest_value: round(p.latest_value, 3),
    unit: p.unit || null,
  }));

const overview = {
  greeting_name: data.patient.split(/\s+/)[0],
  as_of: iso(asOf),
  promis: null, // no check-in data yet
  attention,
  systems: ALL_SYSTEMS.map((k) => systemBundles.get(k)!.rollup),
  bioage_available: pheno.computable,
};

// ── systems map (SystemDetail per key) ────────────────────────────────────────
const systemsOut: Record<string, any> = {};
for (const k of ALL_SYSTEMS) systemsOut[k] = systemBundles.get(k)!.detail;

// ── Ingestion jobs (real source filenames, 'committed') ───────────────────────
const realSourceFiles = Array.from(
  new Set(
    data.measurements.flatMap((m) => m.sources ?? []).filter(Boolean),
  ),
);
// count measurements per source file for the detail string
const countBySource = new Map<string, number>();
for (const m of data.measurements) {
  for (const s of m.sources ?? []) {
    countBySource.set(s, (countBySource.get(s) ?? 0) + 1);
  }
}
const topSources = [...countBySource.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 3);
const ingestionJobs = [
  {
    id: 'job-1',
    filename: topSources[0]?.[0] ?? realSourceFiles[0] ?? 'report.pdf',
    status: 'committed',
    progress: null,
    detail: `${topSources[0]?.[1] ?? 0} measurements saved`,
  },
  {
    id: 'job-2',
    filename: topSources[1]?.[0] ?? realSourceFiles[1] ?? 'report.pdf',
    status: 'committed',
    progress: null,
    detail: `${topSources[1]?.[1] ?? 0} measurements saved`,
  },
  {
    id: 'job-3',
    filename: topSources[2]?.[0] ?? realSourceFiles[2] ?? 'report.pdf',
    status: 'committed',
    progress: null,
    detail: `${topSources[2]?.[1] ?? 0} measurements saved`,
  },
];

// ── Check-in: WHO-5 instrument ────────────────────────────────────────────────
const WHO5_LABELS = [
  'All of the time',
  'Most of the time',
  'More than half the time',
  'Less than half the time',
  'Some of the time',
  'At no time',
];
const checkin = {
  instrument_id: 'who5',
  instrument_name: 'WHO-5 Well-Being Index',
  intro: 'Please indicate for each statement which is closest to how you have been feeling over the past two weeks.',
  items: [
    { key: 'who5_1', prompt: 'I have felt cheerful and in good spirits.', scale_min: 0, scale_max: 5, scale_labels: WHO5_LABELS },
    { key: 'who5_2', prompt: 'I have felt calm and relaxed.', scale_min: 0, scale_max: 5, scale_labels: WHO5_LABELS },
    { key: 'who5_3', prompt: 'I have felt active and vigorous.', scale_min: 0, scale_max: 5, scale_labels: WHO5_LABELS },
    { key: 'who5_4', prompt: 'I woke up feeling fresh and rested.', scale_min: 0, scale_max: 5, scale_labels: WHO5_LABELS },
    { key: 'who5_5', prompt: 'My daily life has been filled with things that interest me.', scale_min: 0, scale_max: 5, scale_labels: WHO5_LABELS },
  ],
};

// ── Prep sheet derived from the actual out-of-range markers ────────────────────
function fmtRef(p: RawParam): string {
  if (p.ref_low != null && p.ref_high != null) return `${p.ref_low}–${p.ref_high}`;
  if (p.ref_high != null) return `< ${p.ref_high}`;
  if (p.ref_low != null) return `> ${p.ref_low}`;
  return '—';
}
function fmtVal(p: RawParam): string {
  if (p.latest_value == null) return p.latest_value_text ?? '—';
  const v = round(p.latest_value, 2);
  return `${v}${p.unit ? ' ' + p.unit : ''}`;
}

const outOfRange = data.parameters
  .filter((p) => systemFor(p) != null && isOutOfRange(p))
  .sort((a, b) => b.numeric_count - a.numeric_count);

// raise-first: the most clinically salient out-of-range trend (LDL or HbA1c)
const ldl = paramByName.get('LDL Cholesterol');
const hba1c = paramByName.get('HbA1c');
let raiseBody: string;
let raiseCites: Source[];
if (ldl && isOutOfRange(ldl)) {
  raiseBody = `Your LDL cholesterol is ${fmtVal(ldl)} — well above the < 100 mg/dL target for cardiovascular risk reduction. Total cholesterol is also elevated. This atherogenic burden is your most important trend to discuss and act on.`;
  raiseCites = [src('aha-2019-lipids')];
} else if (hba1c && isOutOfRange(hba1c)) {
  raiseBody = `Your HbA1c is ${fmtVal(hba1c)}, at or above the diagnostic threshold for type 2 diabetes. This is your most urgent trend to discuss.`;
  raiseCites = [src('ada-2024')];
} else {
  raiseBody = 'Most markers are within their clinical reference ranges. Review the trends below with your clinician at your next visit.';
  raiseCites = [];
}

const glanceMarkers = ['HbA1c', 'LDL Cholesterol', 'APO-B', 'eGFR', 'CRP', 'Vitamin D (25-OH)'];
const glanceTable = glanceMarkers
  .map((name) => {
    const p = paramByName.get(name);
    if (!p) return null;
    const ln = latestNumeric(name);
    const stale =
      ln != null &&
      new Date(`${asOf}T00:00:00Z`).getTime() -
        new Date(`${ln.date}T00:00:00Z`).getTime() >
        365.25 * 24 * 3600 * 1000;
    return {
      marker: name,
      value: fmtVal(p),
      reference: fmtRef(p),
      flag: latestFlag(name),
      stale,
    };
  })
  .filter((r): r is NonNullable<typeof r> => r != null);

// questions grouped by the systems that have out-of-range members
const questionsBySystem = new Map<SystemKey, string[]>();
for (const p of outOfRange.slice(0, 12)) {
  const k = systemFor(p)!;
  const arr = questionsBySystem.get(k) ?? [];
  const dir = latestFlag(p.parameter) === 'high' ? 'elevated' : 'low';
  arr.push(`My ${p.parameter} is ${dir} (${fmtVal(p)}, ref ${fmtRef(p)}). What is driving this and what should we do?`);
  questionsBySystem.set(k, arr);
}
const questions = [...questionsBySystem.entries()].map(([k, qs]) => ({
  system: SYSTEM_META[k].displayName,
  questions: qs.slice(0, 3),
}));

const lifestyleSupplements = [
  {
    item: 'Vitamin D3',
    why: `Your 25-OH vitamin D is ${fmtVal(paramByName.get('Vitamin D (25-OH)') ?? paramByName.get('Vitamin D')!)}, below the 30 ng/mL sufficiency threshold.`,
    caution: 'Confirm dose and recheck in 8–12 weeks.',
    verdict: 'Reasonable to discuss',
    citations: [src('endo-vitd-2011')],
  },
  {
    item: 'High-intensity statin (clinician-prescribed)',
    why: 'LDL and total cholesterol are substantially above target; lipid-lowering therapy is guideline-indicated for this particle burden.',
    caution: 'Prescription medicine — discuss risks/benefits and monitoring with your doctor.',
    verdict: 'Check first',
    citations: [src('aha-2019-lipids')],
  },
  {
    item: 'NMN',
    why: 'Interest in NAD+ precursors for ageing.',
    caution: 'No human outcome RCT. Contested.',
    verdict: 'Unproven — discuss with clinician',
    citations: [src('nmn-contested')],
  },
];

// gaps a clinician might have missed (derived from sparse / one-off tests)
const gapsClinicianMissed: string[] = [];
if ((paramByName.get('APO-B')?.count ?? 0) <= 2)
  gapsClinicianMissed.push('ApoB tested only twice despite persistently elevated LDL — the better atherogenic marker is undersampled.');
if (
  (paramByName.get('Lipoprotein(a)')?.count ?? 0) +
    (paramByName.get('Lipoprotein (a)')?.count ?? 0) >
  0
)
  gapsClinicianMissed.push('Lp(a) measured but not trended — it is a one-time genetic test; the result should inform lifetime cardiovascular risk.');
if ((paramByName.get('eGFR')?.count ?? 0) < (paramByName.get('Creatinine')?.count ?? 0))
  gapsClinicianMissed.push('eGFR reported less often than creatinine; kidney filtration trend is under-tracked given the latest value below 90.');
if ((paramByName.get('Insulin Fasting')?.count ?? 0) < 10)
  gapsClinicianMissed.push('Fasting insulin tested only a handful of times — HOMA-IR cannot be trended, so insulin resistance relies on the TyG surrogate.');

const prep = {
  id: 'prep-1',
  generated_at: iso(asOf),
  raise_first: { body: raiseBody, citations: raiseCites },
  glance_table: glanceTable,
  questions,
  lifestyle_supplements: lifestyleSupplements,
  gaps_clinician_missed: gapsClinicianMissed,
};

// ── citations map ─────────────────────────────────────────────────────────────
const citationsOut: Record<string, Source> = {};
for (const [id, s] of Object.entries(SOURCES)) citationsOut[id] = s;

// ── Final bundle ──────────────────────────────────────────────────────────────
const bundle = {
  overview,
  systems: systemsOut,
  parameters: parametersOut,
  bioage,
  ingestion_jobs: ingestionJobs,
  checkin,
  prep,
  citations: citationsOut,
};

writeFileSync(OUT, JSON.stringify(bundle, null, 2));

// ── Report ────────────────────────────────────────────────────────────────────
const stat = readFileSync(OUT, 'utf8');
const sizeKb = (Buffer.byteLength(stat, 'utf8') / 1024).toFixed(1);
/* eslint-disable no-console */
console.log('── gen-sample-data ──────────────────────────────────────────');
console.log('Wrote:', OUT);
console.log('Size :', `${sizeKb} KB`);
console.log('Top-level keys:', Object.keys(bundle).join(', '));
console.log('Systems:', Object.keys(systemsOut).join(', '));
console.log('Parameters (count):', Object.keys(parametersOut).length);
console.log('Attention items:', attention.length, '→', attention.slice(0, 5).map((a) => `${a.parameter}=${a.latest_value}(${a.flag})`).join(', '));
console.log('PhenoAge computable:', pheno.computable, '| value_years:', round(pheno.value, 1), '| chrono_age:', CHRONO_AGE, '| delta_years:', round(pheno.delta, 1));
console.log('PhenoAge inputs (post-conversion):', JSON.stringify(phenoInputs));
console.log('eGFR:', round(egfr.value, 1), egfr.band, '| FIB-4:', round(fib4.value, 2), fib4.band, '| TyG:', round(tyg.value, 2));
console.log('NLR:', round(nlr.value, 2), '| AAR:', round(aar.value, 2), '| PLR:', round(plr.value, 1), '| HOMA-IR:', round(homaIr.value, 2), homaIr.band ?? '');
console.log('BioAge trend points:', bioTrend.length);
console.log('Ingestion jobs:', ingestionJobs.map((j) => `${j.filename} (${j.detail})`).join(' | '));
console.log('────────────────────────────────────────────────────────────');
