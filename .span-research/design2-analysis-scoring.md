## Overview

The Analysis Layer is the **scientific core** that turns normalized `measurements` rows into longitudinal trends, organ-system status rollups, and validated longevity/clinical scores, then materializes them into `analysis_results` for the Presentation and Voice layers to consume read-only. It is the single place where medical logic lives — the SwiftUI client and the voice RAG agent are thin and never compute anything clinical.

**Design contract:**
- **Stateless, deterministic, versioned.** Every score and trend is a pure function of (input measurement set, formula version, optimal-band catalog version). Same inputs + same versions ⇒ byte-identical outputs. This is what makes recompute, audit, and explainability tractable.
- **Educational stance is structural, not cosmetic.** No row in `analysis_results` is emitted without (a) an `evidence_tier`, (b) a `disclaimer_key`, and (c) full input provenance (`inputs_used` listing which `measurement.id` fed it). A score the layer cannot ground in stored measurements is *not produced* — never fabricated, never imputed-and-hidden.
- **Three-zone semantics everywhere.** Red = outside clinical reference range; Yellow = inside clinical range but outside peer-reviewed optimal; Green = inside peer-reviewed/expert optimal band. Clinical range and optimal band are *different objects* from different sources with different tiers, and the layer keeps them separate end to end.
- **Region-pinned compute.** Analysis runs in the user's `inference_geo` (ap-south-1 / eu-central-1). Score math is pure CPU (NumPy/Python) and carries **no PHI to any LLM** — only the prep-sheet generation step (out of scope here, handled by Presentation/Opus layer) touches an LLM, and it consumes already-materialized `analysis_results`, not raw PHI.
- **Reuse the shared schema.** This document only *adds* `analysis_results`, `scores`, `parameter_stats`, `optimal_bands`, plus a normalization service. It never redefines `measurements`, `canonical_parameters`, `users`, `consents`, etc.

The layer answers four questions for any user, generalized (no hardcoded per-user logic):
1. **Trend** — for each parameter, is it moving and in what direction relative to range and to the user's own baseline?
2. **Bucket** — which organ system / Four-Horseman threat / Hallmark-of-Aging does each parameter inform, and what is the per-system status?
3. **Score** — what do the validated composite models say (PhenoAge, eGFR, FIB-4, NAFLD-FS, TyG, NLR/AAR/PLR)?
4. **Why** — exactly which raw measurements, units, and reference sources produced each number (for GDPR/DPDP explainability and the prep sheet).

---

## Architecture

The Analysis Layer is a worker pool plus a read API. It is triggered by ingestion completion (new `measurements` committed via the transactional outbox), by HealthKit catch-up syncs, by onboarding-fact changes (BMI, diabetes flag), and by catalog/formula version bumps. It never writes to shared tables; it writes only to its own four tables and the append-only `audit_log`.

```
                          ┌──────────────────────────── REGION PIN (ap-south-1 | eu-central-1) ─────────────────────────────┐
                          │                                                                                                  │
  ingestion_jobs ──FSM──► outbox event: measurements.committed(user_id, report_id)                                          │
  HealthKit sync ───────► outbox event: device.synced(user_id)                                                              │
  onboarding edit ──────► outbox event: facts.changed(user_id)        ┌────────────────────────────────────────────────┐  │
  catalog/formula bump ─► outbox event: catalog.version_changed(all)  │   RECOMPUTE PLANNER                             │  │
                          │                                           │  - debounce per user (SQS FIFO, MsgGroupId=user)│  │
                          ▼                                           │  - resolve affected params -> affected scores  │  │
                  ┌───────────────┐                                   │  - pick active formula_version + catalog_version│  │
                  │  SQS FIFO     │ ─────────────────────────────────►│                                                │  │
                  │ group=user_id │                                   └───────────────┬────────────────────────────────┘  │
                  └───────────────┘                                                   │                                    │
                                                                                      ▼                                    │
   ┌──────────────────────────────────── ANALYSIS WORKER (pure Python / NumPy) ───────────────────────────────────────┐   │
   │                                                                                                                   │   │
   │   1. LOAD  measurements (RLS user_id) + canonical_parameters + onboarding facts                                   │   │
   │            │                                                                                                      │   │
   │            ▼                                                                                                      │   │
   │   2. ┌──────────────────────── BIOMARKER NORMALIZATION SERVICE (shared, in-proc lib) ───────────────────────┐    │   │
   │      │  canonicalize unit -> canonical_unit | clamp plausibility | resolve clinical ref range               │    │   │
   │      │  resolve optimal_band (tiered) | emit NormalizedValue{value, unit, ref_low/high, tier, citation,      │    │   │
   │      │  provenance: measurement.id}   <-- EVERY downstream consumer calls THIS, never raw measurement        │    │   │
   │      └───────────────────────────────┬──────────────────────────────────────────────────────────────────────┘    │   │
   │            │                          │                          │                              │                  │   │
   │            ▼                          ▼                          ▼                              ▼                  │   │
   │   3a. TREND ENGINE          3b. SCORE ENGINE            3c. ORGAN BUCKETER          3d. PROVENANCE/EXPLAIN         │   │
   │      per-parameter            PhenoAge, eGFR,             params/categories ->        inputs_used[], unit_xform,   │   │
   │      slope/MA/zone-over-time  FIB-4, NAFLD-FS,            8 organ tiles + 4H +        ref source + tier per output │   │
   │      vs own baseline          TyG, NLR/AAR/PLR           Hallmarks; system rollup                                  │   │
   │            │                          │                          │                              │                  │   │
   │            └──────────────┬───────────┴──────────┬───────────────┴──────────────┬───────────────┘                  │   │
   │                           ▼                       ▼                              ▼                                  │   │
   │   4. MATERIALIZE (idempotent UPSERT, keyed by result_version)                                                      │   │
   │      parameter_stats   |   scores   |   analysis_results (denormalized read model)                                 │   │
   │            │                                                                                                       │   │
   │            └────► audit_log (append-only): {event, inputs_used[], formula_version, catalog_version, computed_at}    │   │
   └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
                                                       │                                                                  │
                                                       ▼                                                                  │
                    /v1/overview  /v1/systems/{key}  /v1/parameters/{id}  /v1/bioage  ──► Presentation (SwiftUI)         │
                    voice RAG retriever ──reads analysis_results+normalized values ONLY (no recompute, no LLM math)──►    │
                          └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

Key properties: ingestion → analysis is **eventually consistent** (async, debounced per user); the read API serves the last materialized `result_version` and never blocks on recompute; a recompute that fails leaves the prior `result_version` live (no partial writes — UPSERT is transactional per user per version).

---

## Data model

All four tables are **additive**. They reference shared tables by FK and inherit RLS on `user_id`. Region pin is implicit (these tables live in the same regional Aurora as `measurements`).

### `optimal_bands` (catalog — reference data, not per-user)

Tiered longevity/optimal bands distinct from clinical reference ranges. Versioned as a catalog so band edits trigger recompute without code deploys.

```sql
CREATE TABLE optimal_bands (
  band_id            text PRIMARY KEY,              -- e.g. 'apob_optimal_v1'
  canonical_param_id text REFERENCES canonical_parameters,  -- nullable for ratio/score bands
  score_key          text,                          -- nullable; set for score-level bands (e.g. phenoage delta)
  applies_to         text NOT NULL CHECK (applies_to IN ('parameter','score','ratio')),
  sex                text CHECK (sex IN ('M','F','any')) DEFAULT 'any',
  age_low            numeric,  age_high  numeric,    -- optional age scoping
  optimal_low        numeric,  optimal_high numeric, -- one side may be null (e.g. apoB <60 => high=60, low=null)
  unit               text NOT NULL,                  -- MUST equal canonical_unit of the param
  evidence_tier      smallint NOT NULL CHECK (evidence_tier IN (1,2,3)),
  citation           jsonb NOT NULL,                 -- {label, source, url, year, note}
  disclaimer_key     text NOT NULL,                  -- e.g. 'expert_opinion_discuss_clinician'
  catalog_version    int  NOT NULL,
  active             boolean NOT NULL DEFAULT true
);
```

Seed examples (tier-3 expert unless noted): `apoB < 60 mg/dL`, `Lp(a) < 50 nmol/L` (optimal) `/ >100` very-high one-time genetic, `HbA1c < 5.5 %`, `triglycerides < 100 mg/dL`, `uric_acid < 5.0 mg/dL`, `ALT < 20 U/L`, `omega3_index >= 8 %` (tier-1-ish). `citation.label` renders verbatim as "Attia/expert opinion — discuss with your clinician." A score-level band example: PhenoAge `delta = phenoage - chrono_age`, optimal `< 0` (biologically younger), tier-3.

### `parameter_stats` (per-user, per-parameter longitudinal state)

One row per `(user_id, canonical_param_id)`; the materialized trend object.

```sql
CREATE TABLE parameter_stats (
  user_id            uuid NOT NULL REFERENCES users(id),
  canonical_param_id text NOT NULL REFERENCES canonical_parameters,
  n_points           int  NOT NULL,
  first_date         date,  last_date date,
  latest_value       numeric, latest_unit text, latest_flag text,   -- canonical unit
  baseline_value     numeric, baseline_kind text,                   -- 'first' | 'rolling12mo_median' | 'first_in_range'
  slope_per_year     numeric,                                       -- canonical units / year (Theil-Sen)
  slope_ci_low       numeric, slope_ci_high numeric,
  ma_short           numeric, ma_long numeric,                      -- e.g. last-2 vs all-but-last-2 means
  direction          text CHECK (direction IN ('improving','worsening','stable','insufficient_data')),
  direction_conf     text CHECK (direction_conf IN ('low','moderate','high')),
  pct_in_range       numeric,                                       -- fraction of points inside clinical range
  zone_timeline      jsonb,   -- [{date, zone:'red|yellow|green', value, flag}]
  delta_vs_baseline  numeric, delta_pct numeric,
  result_version     bigint NOT NULL,
  catalog_version    int NOT NULL,
  computed_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, canonical_param_id)
);
```

### `scores` (per-user composite model outputs, one row per score per computation)

```sql
CREATE TABLE scores (
  score_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES users(id),
  score_key          text NOT NULL,    -- 'phenoage'|'egfr_ckdepi2021'|'fib4'|'nafld_fs'|'tyg'|'nlr'|'aar'|'plr'
  as_of_date         date NOT NULL,    -- date of the binding (newest) input measurement set
  value              numeric,          -- null if not computable
  value_unit         text,             -- 'years','mL/min/1.73m2','ratio','index', etc.
  band               text,             -- model-specific: 'rule_out'|'indeterminate'|'advanced' | zone | null
  interpretation_key text NOT NULL,    -- i18n key for educational text (never a diagnosis)
  evidence_tier      smallint NOT NULL,
  computable         boolean NOT NULL,
  missing_inputs     text[] ,          -- canonical_param_ids that were required but absent
  inputs_used        jsonb NOT NULL,   -- [{canonical_param_id, measurement_id, raw_value, raw_unit, norm_value, norm_unit, xform}]
  caveats            text[],           -- e.g. {'not_calibrated_india','crp_unit_assumed_mgL'}
  formula_version    text NOT NULL,    -- 'phenoage_levine2018_v1', 'ckdepi_2021_v1'
  catalog_version    int  NOT NULL,
  result_version     bigint NOT NULL,
  computed_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, score_key, result_version)
);
```

### `analysis_results` (denormalized read model — what Presentation + Voice consume)

A single JSON document per user per `result_version`, assembled from the three engines. The API serves this directly; the relational tables above are the normalized source of truth and the audit substrate.

```sql
CREATE TABLE analysis_results (
  user_id          uuid PRIMARY KEY REFERENCES users(id),   -- only the live version is kept hot; history in audit_log
  result_version   bigint NOT NULL,
  catalog_version  int NOT NULL,
  generated_at     timestamptz NOT NULL DEFAULT now(),
  overview         jsonb NOT NULL,   -- header + 8 system tiles + bioage summary
  systems          jsonb NOT NULL,   -- per-system detail (params, rollup, 4H, hallmarks)
  parameters       jsonb NOT NULL,   -- per-param latest + trend ref to parameter_stats
  bioage           jsonb NOT NULL,   -- phenoage + delta + opt-in gate
  scores           jsonb NOT NULL,   -- all computable scores w/ tiers, caveats, inputs_used refs
  disclaimers      jsonb NOT NULL    -- resolved disclaimer texts per disclaimer_key used anywhere above
);
```

`overview` shape (Presentation `/v1/overview`):

```json
{
  "header": { "promis_physical_t": null, "promis_mental_t": null, "who5_latest": null },
  "bioage": { "show": false, "phenoage": 41.2, "chrono_age": 38.0, "delta": 3.2,
              "tier": 3, "disclaimer_key": "bioage_secondary_optin", "computable": true },
  "systems": [
    { "key": "metabolic", "title": "Metabolic", "status": "attention",
      "status_basis": "1 red, 2 yellow of 9 measured", "horsemen": ["metabolic"],
      "worst_params": ["hba1c","triglycerides"], "n_red": 1, "n_yellow": 2, "n_green": 6 }
    /* ... 8 tiles ... */
  ]
}
```

Per-parameter object inside `parameters` / `/v1/parameters/{id}`:

```json
{
  "canonical_param_id": "apob",
  "display_name": "Apolipoprotein B", "loinc_code": "1884-6", "category": "Lipids",
  "latest": { "value": 92, "unit": "mg/dL", "date": "2026-04-02", "flag": "high_optimal",
              "zone": "yellow", "value_operator": null },
  "clinical_ref": { "low": null, "high": 130, "source": "lab", "tier": null },
  "optimal_band": { "low": null, "high": 60, "tier": 3,
                    "citation": { "label": "Attia/expert opinion — discuss with your clinician" } },
  "trend": { "direction": "worsening", "confidence": "moderate",
             "slope_per_year": 6.1, "pct_in_range": 1.0, "n_points": 4,
             "delta_vs_baseline": 14, "baseline_kind": "first",
             "zone_timeline": [ /* {date,zone,value,flag} */ ] },
  "disclaimer_key": "optimal_band_expert_opinion"
}
```

---

## APIs / interfaces

### Read endpoints (region-routed, `/v1`, RLS-scoped to caller)

- `GET /v1/overview` → `analysis_results.overview`. Header bands, 8 tiles, bioage summary.
- `GET /v1/systems/{key}` → `analysis_results.systems[key]`: member params with latest+zone, system rollup, Four-Horsemen + Hallmark mapping, per-param disclaimers.
- `GET /v1/parameters/{id}` → per-param object above + full `zone_timeline` for Swift Charts (RectangleMark ref+optimal bands, LineMark series, flag PointMark, null-annotated gaps).
- `GET /v1/bioage` → PhenoAge detail: value, delta, `inputs_used` (the 9 markers + ages), unit transforms applied, tier-3 disclaimer, opt-in gate state. **Never** surfaced in `/v1/overview.header`.
- `GET /v1/scores` → all `scores` rows for user with `computable`, `missing_inputs`, `caveats`.
- Internal: `POST /internal/v1/recompute` (planner enqueue), `GET /internal/v1/explain/{score_id}` → full provenance for prep-sheet + DPDP/GDPR access requests.

The voice RAG retriever reads `analysis_results` + per-parameter normalized values **only** and may speak `value + unit + ref + flag + date` verbatim; it must not invoke score math or emit any number not present in a materialized row.

### Shared biomarker-normalization service signature

In-process Python library (also exposed as `/internal/v1/normalize` for the ingestion QA path). **Every** trend/score/bucket call goes through `normalize()` — no engine reads a raw `measurements` row directly.

```python
@dataclass(frozen=True)
class Citation:
    label: str; source: str; url: str | None; year: int | None; note: str | None

@dataclass(frozen=True)
class NormalizedValue:
    canonical_param_id: str
    measurement_id: str                # provenance: exact row consumed
    value: float | None                # in canonical_unit; None if value_text-only/non-numeric
    unit: str                          # canonical_unit
    value_operator: str | None         # '<','>','<=' preserved from raw
    raw_value: float | None; raw_unit: str
    unit_xform: str                    # human-readable, e.g. 'mg/dL*88.42->umol/L'
    clinical_ref: tuple[float|None, float|None]  # (low, high) — lab-provided or canonical default
    ref_source: str                    # 'lab' | 'canonical_default'
    optimal_band: OptimalBand | None   # tier + citation + (low,high)
    plausibility_clamped: bool
    flag: str                          # 'low'|'normal'|'high'|'high_optimal'|'low_optimal'|'critical'|'unknown'
    zone: str                          # 'red'|'yellow'|'green'|'gray'
    notes: list[str]                   # e.g. ['crp_unit_assumed_mgL','ref_missing_used_default']

class NormalizationService:
    def normalize(self, m: Measurement, *, sex: str, age: float,
                  catalog_version: int) -> NormalizedValue: ...

    def normalize_for_score(self, params: dict[str, Measurement], required: list[str],
                            target_units: dict[str, str], *, sex: str, age: float,
                            catalog_version: int
                           ) -> tuple[dict[str, NormalizedValue], list[str]]:
        """Returns (resolved, missing_inputs). Picks the newest measurement per required
           canonical_param_id within a configurable as_of window; coerces each to the
           target unit the formula demands (e.g. CRP->mg/dL, creatinine->umol/L)."""

    def optimal_band(self, canonical_param_id: str|None, score_key: str|None,
                     sex: str, age: float, catalog_version: int) -> OptimalBand | None: ...
```

**Unit canonicalization** uses `canonical_parameters.canonical_unit` + a static conversion table; **plausibility clamp** uses `plausibility_low/high` (out-of-bounds ⇒ `plausibility_clamped=True`, value excluded from scores, flagged `unknown`); **zone resolution**: outside `clinical_ref` ⇒ red; inside clinical but outside `optimal_band` ⇒ yellow; inside optimal ⇒ green; no numeric value ⇒ gray. The returned `unit_xform` + `measurement_id` are persisted into every `scores.inputs_used` / `parameter_stats` row — this is the GDPR/DPDP explainability + prep-sheet substrate.

---

### (1) Per-parameter trend computation (generalized, any user)

Operates on the per-user series `S = [(date_i, NormalizedValue_i)]` for one `canonical_param_id`, ascending by date, numeric points only (gray points excluded from math but kept in `zone_timeline`).

**Algorithm:**
1. **Baseline** = configurable: default `first` in-range point if one exists else first point; alternative `rolling12mo_median`. Stored as `baseline_kind`.
2. **Slope** via **Theil–Sen estimator** (median of pairwise slopes) over (years_since_first, value) — robust to outliers and tiny n; report `slope_per_year` + bootstrap CI. Skip if `n_points < 3` (`direction='insufficient_data'`).
3. **Moving averages**: `ma_short` = mean of last `k=2` points; `ma_long` = mean of remaining. (Adaptive k for dense HealthKit-derived series.)
4. **Direction** uses **parameter polarity** from `canonical_parameters` (is "down" good or bad — e.g. LDL down = improving, eGFR down = worsening). Map signed slope through polarity:
   - `|slope| < ε·typical_within_person_CV` and CI straddles 0 ⇒ `stable`.
   - signed slope toward optimal ⇒ `improving`; away ⇒ `worsening`.
   - Confidence: `high` if CI excludes 0 and `n>=4`; `moderate` if `n>=3`; else `low`.
5. **In/out-of-range-over-time**: `pct_in_range` = fraction of points inside clinical range; `zone_timeline` = per-point `{date,zone,value,flag}` (drives the Swift Charts band overlay).
6. **Compare-to-own-baseline**: `delta_vs_baseline = latest - baseline`, `delta_pct`.

**Output** = one `parameter_stats` row (shape above) + the `trend` sub-object in `analysis_results.parameters`. Educational guardrail: direction language is **"trending toward/away from your optimal range,"** never "improving disease."

---

### (2) Organ-system bucketing + rollup

A static mapping table (catalog-versioned) `canonical_param_id | category → organ_system_key`, with each system tagged to **Attia Four Horsemen** threats and relevant **Hallmarks of Aging (Lopez-Otín 2023, 12)** as a *why-this-matters* ontology — not a computed score.

8 organ-system tiles (home):

| System key | Example params/categories | Four Horsemen | Hallmark examples (why) |
|---|---|---|---|
| `metabolic` | glucose, HbA1c, insulin, TyG, uric_acid (Diabetes) | Metabolic | deregulated nutrient sensing, mitochondrial dysfunction |
| `cardiovascular` | apoB, LDL, HDL, TG, Lp(a) (Lipids) | ASCVD | chronic inflammation, cellular senescence |
| `liver` | ALT, AST, ALP, albumin, bilirubin, FIB-4, NAFLD-FS (Liver) | Metabolic | loss of proteostasis, altered intercellular comm. |
| `kidney` | creatinine, eGFR, urea, electrolytes, urine (Kidney/Electrolytes/Urine) | Metabolic/ASCVD | cellular senescence, stem-cell exhaustion |
| `inflammation_immune` | CRP, WBC, NLR, PLR (Inflammation/CBC) | cancer/ASCVD | chronic inflammation, dysbiosis |
| `hematologic` | Hgb, Hct, MCV, RDW, platelets (CBC) | — | stem-cell exhaustion, genomic instability |
| `endocrine_thyroid` | TSH, T3/T4 (Thyroid) | metabolic | deregulated nutrient sensing |
| `micronutrient_bone` | vit-D, B12, ferritin, Ca, Mg, P (Vitamins/Minerals) | neurodegeneration | epigenetic alterations, mitochondrial dysfunction |

**Per-system status rollup (false-precision-avoiding):** a **discrete 3-level status**, never a numeric "organ score":
- `attention` (Red): ≥1 member param outside clinical range.
- `monitor` (Yellow): 0 red and ≥1 param inside clinical but outside optimal.
- `on_track` (Green): all measured members inside optimal.
- `not_enough_data`: 0 numeric members.

Each tile carries `status_basis` (e.g. `"1 red, 2 yellow of 9 measured"`) so the UI shows the *count*, not a fake percentage. `worst_params` lists the red-then-yellow members for the tile subtitle. Composite scores (FIB-4, eGFR) contribute to their system's status with their own band → zone, so a normal-LFT panel with high FIB-4 still flags `liver = attention`.

---

### (3) Confirmed models — exact implementation

For each: required canonical inputs, unit normalization (the #1 bug class), formula, missing-input policy, output meaning, evidence tier. All consume `normalize_for_score(...)`; all persist `inputs_used` with `unit_xform`.

**PhenoAge** — `formula_version='phenoage_levine2018_v1'`, **tier 2** (validated mortality predictor, presented as bio-age, secondary/opt-in, never headline).
Required (9 markers + chrono age): albumin, creatinine, glucose, CRP, lymphocyte_pct, MCV, RDW, ALP, WBC, age.
Unit normalization (enforced, each recorded as `unit_xform`):
- albumin → **g/L** (g/dL × 10)
- creatinine → **µmol/L** (mg/dL × 88.42)
- glucose → **mmol/L** (mg/dL ÷ 18)
- CRP → **mg/dL** (mg/L ÷ 10) — `caveat 'crp_unit_assumed_mgL'` if raw unit ambiguous
- lymphocyte_pct → **%**, MCV → **fL**, RDW → **%**, ALP → **U/L**, WBC → **1000/µL**
Formula:
```
xb = -19.90667 - 0.03359355*alb + 0.009506491*creat + 0.1953192*gluc
     + 0.09536762*ln(CRP) - 0.01199984*lymph + 0.02676401*MCV
     + 0.3306156*RDW + 0.001868778*ALP + 0.05542406*WBC + 0.08035356*age
M = 1 - exp(-1.51714 * exp(xb) / 0.0076927)
PhenoAge = 141.50225 + ln(-0.0055305 * ln(1 - M)) / 0.090165
```
Guards: CRP must be > 0 before `ln` (if 0/undetectable, substitute assay LoD, note `'crp_below_lod'`). Plausibility-clamped inputs ⇒ score not computed.
Missing-input policy: **all 9 required**; any missing ⇒ `computable=false`, `missing_inputs=[...]`, no imputation. Output: `value` (years), `delta = phenoage - chrono_age`, band from score-level `optimal_bands` (delta<0 green). NHANES-III-trained — `caveat 'trained_nhanes3_not_india_calibrated'`.

**CKD-EPI 2021 eGFR (race-free)** — `formula_version='ckdepi_2021_v1'`, **tier 1**.
Required: creatinine (→ **mg/dL**, canonical; if stored µmol/L ÷ 88.42), age, sex.
```
k = 0.7 (F) | 0.9 (M);   a = -0.241 (F) | -0.302 (M)        # 2021 coeffs, NOT 2009
eGFR = 142 * min(Scr/k,1)^a * max(Scr/k,1)^-1.200 * 0.9938^age * (1.012 if F else 1)
```
Output: mL/min/1.73m². Band → zone via KDIGO G-stages for system rollup; interpretation educational ("estimated filtration; discuss with clinician"). Missing sex ⇒ not computable (no default-sex guess). 

**FIB-4** — `formula_version='fib4_v1'`, **tier 1** (rule-out NPV strong).
Required: age, AST (U/L), ALT (U/L), platelets (**10⁹/L**; if stored 10³/µL same numeric).
```
FIB4 = (age * AST) / (platelets * sqrt(ALT))
```
Bands: `<1.45 → rule_out`; `>3.25 → advanced`; between → `indeterminate`. **Age > 65 ⇒ lower rule-out cutoff 2.0** (not 1.45) — store which cutoff set used in `caveats`. Output: ratio + band; interpretation = "low/indeterminate/higher likelihood of advanced fibrosis — not a diagnosis."

**NAFLD-FS** — `formula_version='nafld_fs_v1'`, **tier 2**.
Required: age, **BMI** (onboarding fact), **IFG/diabetes flag** (onboarding/HbA1c-derived), AST, ALT, platelets (10⁹/L), albumin (**g/dL**).
```
NFS = -1.675 + 0.037*age + 0.094*BMI + 1.13*(diab_or_IFG?1:0)
      + 0.99*(AST/ALT) - 0.013*platelets - 0.66*albumin
```
Bands: `< -1.455 → exclude`; `> 0.676 → advanced`; between → `indeterminate`. Missing BMI or diabetes flag ⇒ `computable=false`, `missing_inputs` includes `bmi`/`diabetes_flag` (drives a UI "add to onboarding to unlock" prompt).

**TyG** — `formula_version='tyg_v1'`, **tier 2, trend-only**.
Required: fasting triglycerides (mg/dL), fasting glucose (mg/dL).
```
TyG = ln( triglycerides * fasting_glucose / 2 )
```
**No universal cutoff** ⇒ `band=null`, surfaced only as a trend in `parameter_stats`-style series; `caveat 'no_cutoff_trend_only'`. Requires fasting; if fasting status unknown, `caveat 'fasting_unconfirmed'`.

**HOMA-IR** (opportunistic) — `formula_version='homair_v1'`, tier 2. Required fasting insulin (µU/mL) + fasting glucose (mg/dL): `(insulin*glucose)/405`. Computed only when insulin present; else silently absent (not listed as missing on the metabolic tile unless insulin exists historically).

**Soft-flag ratios — NLR / AAR (De Ritis) / PLR** — `formula_version='ratios_v1'`, **tier 3, context-dependent, NOT diagnostic**.
```
NLR = neutrophils / lymphocytes          # absolute counts, same unit
AAR = AST / ALT                          # De Ritis
PLR = platelets / lymphocytes
```
Output: ratio value + **trend** only; `band=null`; `interpretation_key` is explicitly non-diagnostic ("context-dependent inflammatory/liver-pattern indicator — not a standalone finding"). Used as **soft inputs to system rollups** (can nudge a tile to `monitor`) but never alone push a tile to `attention`.

**Phased to cohort-fitting (NOT in v1 compute):** KDM bio-age + Homeostatic Dysregulation (Mahalanobis) — formulas confirmed but require reference-cohort fitting (start `dayoonkwon/BioAge` NHANES, recalibrate on Indian population); Allostatic Load (no canonical formula; only partial blood subscore, cutoffs from own population). SCORE2/ASCVD — need BP/smoking/BP-tx from onboarding and are **not India-calibrated** ⇒ if ever shown, hard `caveat 'not_calibrated_india_educational_estimate'`. Organ-age proteomic clocks (SomaScan/Olink), Charlson (needs ICD dx) — excluded.

---

### (4) Shared normalization + reference-range + optimal-band service

Covered in **APIs / interfaces** above. Three responsibilities, one library, called by every engine:
1. **Normalize** raw `measurements` → `NormalizedValue` in canonical units, with plausibility clamp and preserved `value_operator`.
2. **Reference range** resolution: prefer lab-provided `ref_low/high` from the measurement row; fall back to `canonical_parameters.default_ref_low/high` (`ref_source` recorded). This is the **clinical** range (Red boundary).
3. **Optimal band** resolution from the `optimal_bands` catalog (tier + citation; the Yellow/Green boundary), e.g. apoB<60, ALT<20. Sex/age-scoped lookup.
**Explainability substrate:** every consumer persists `{measurement_id, raw_value, raw_unit, norm_value, norm_unit, unit_xform, ref_source, tier}` into `inputs_used` — this is exactly what `/internal/v1/explain/{score_id}` returns for a DPDP/GDPR data-access request and what the Opus prep-sheet cites ("this PhenoAge used your 2026-04-02 CRP of 1.2 mg/L → 0.12 mg/dL").

---

### (5) `analysis_results` model — Presentation + Voice consumption

Defined under **Data model**. It is a single denormalized JSON document per user (`overview/systems/parameters/bioage/scores/disclaimers`) keyed by `result_version`, served read-only by `/v1/*`. Voice reads the same document plus per-param normalized values and may speak only stored numbers. Every leaf that carries a clinical/optimal claim also carries a `disclaimer_key` resolved in the `disclaimers` block, so no client renders a number without its educational caveat and its tier.

---

### (6) Recompute triggers + score versioning

**Triggers** (all flow through the transactional outbox → SQS FIFO, `MessageGroupId=user_id` for per-user ordering + debounce):
- `measurements.committed` (ingestion finished for a report) — recompute affected params + any score whose required inputs intersect the new params.
- `device.synced` (HealthKit catch-up) — recompute trend for device-sourced params (HRV, RHR, VO2max, SpO2, etc.) only; these don't feed clinical scores.
- `facts.changed` (BMI / diabetes flag / sex / DOB edited in onboarding) — recompute NAFLD-FS, eGFR, PhenoAge, age-dependent FIB-4 cutoff.
- `catalog.version_changed` (new `optimal_bands` or organ-mapping or formula version) — **fan-out recompute for all users** in region (batched, low-priority queue).
- `consent.changed` — if a purpose/scope is withdrawn, recompute may need to *exclude* a source (e.g. device data); withdrawal triggers re-materialization minus the withdrawn scope.

The **planner** computes the minimal affected set (param → dependent scores via a static dependency map) to avoid full recompute on every new measurement.

**Versioning** (three independent version axes, all stamped on every output row):
- `formula_version` (per score, string, e.g. `phenoage_levine2018_v1`) — bump when math/coefficients/cutoffs change; old `scores` rows retain their version (audit-stable).
- `catalog_version` (int, monotonic) — covers `optimal_bands` + organ-mapping + canonical-parameter dictionary changes.
- `result_version` (per-user, monotonic bigint) — incremented on each successful materialization; `analysis_results` keeps only the live version hot, prior versions are reconstructable from `audit_log` (`inputs_used` + versions are append-only) for full explainability and reproducibility. UPSERT keyed by `result_version` is idempotent and transactional per user — a failed recompute never leaves a partial read model.

---

## Tech choices

- **Pure-Python/NumPy score engine** (no LLM in the math path) — deterministic, unit-testable against published reference vectors, region-portable. PHI never leaves Aurora/the worker; the only LLM touchpoint (prep-sheet) consumes materialized results downstream.
- **Theil–Sen slope** over OLS — robust to lab-to-lab outliers and small n, no distributional assumptions; bootstrap CI for confidence labeling.
- **Catalog-versioned reference data** (`optimal_bands`, organ map) so band/mapping edits are data deploys (recompute fan-out) not code deploys.
- **Denormalized `analysis_results` JSON read model** — single round-trip for the thin SwiftUI client and the voice retriever; normalized `scores`/`parameter_stats` remain the audit source of truth.
- **SQS FIFO per-user grouping** — ordering + natural debounce; reuses the existing ingestion outbox infra, no new broker.
- **Aurora-local, RLS-inherited** — no cross-region read; analysis tables sit beside `measurements` in the same regional cluster, honoring the two-pin residency model.

## Risks

- **Unit bugs = #1 risk** (esp. PhenoAge: CRP mg/L↔mg/dL, creatinine mg/dL↔µmol/L, glucose, albumin). Mitigation: single normalization service, mandatory `target_units` per score, golden reference-vector tests, `unit_xform` persisted and shown in `/explain`.
- **False precision** in organ rollups / bio-age. Mitigation: discrete 3-level system status with `status_basis` counts (no numeric organ score); PhenoAge gated opt-in, never headline, tier+caveat attached.
- **Sparse series / single data point** → meaningless slope. Mitigation: `n>=3` gate, `insufficient_data` direction, CI-based confidence.
- **Missing onboarding facts** silently disabling scores (NAFLD-FS, age-cutoff). Mitigation: explicit `missing_inputs` surfaced as "unlock" prompts, never imputed.
- **Catalog/formula bump fan-out** thundering-herd recompute. Mitigation: low-priority batched queue, off-peak, idempotent UPSERT.
- **India non-calibration** of NHANES/Western-trained models (PhenoAge, future SCORE2). Mitigation: explicit `not_india_calibrated` caveats; KDM/HD deferred to Indian-cohort fitting.
- **CRP below LoD / zero** breaking `ln`. Mitigation: LoD substitution + `crp_below_lod` note, or mark non-computable.
- **Educational-stance leakage** — a score band reading as a diagnosis. Mitigation: `interpretation_key` strings vetted to non-diagnostic language; tier + `disclaimer_key` mandatory on every emitted claim.

## Phased build

- **Phase 1 (MVP scientific core):** normalization service + `optimal_bands` catalog seed; trend engine (Theil–Sen, zones, baseline); organ bucketing + 3-level rollup; tier-1/2 scores **eGFR, FIB-4, PhenoAge, TyG, NLR/AAR/PLR**; `analysis_results` materialization; `/v1/overview|systems|parameters|bioage|scores`; recompute via existing outbox; `/explain` provenance.
- **Phase 2:** NAFLD-FS + HOMA-IR (depend on onboarding facts pipeline); richer trend (seasonality, within-person CV per param); consent-withdrawal re-materialization; prep-sheet `inputs_used` enrichment.
- **Phase 3 (cohort-fitting):** KDM bio-age + Homeostatic Dysregulation (Mahalanobis) fitted on NHANES then **recalibrated on Indian population**; partial Allostatic-Load blood subscore with own-population cutoffs; optional SCORE2/ASCVD **only** behind `not_calibrated_india` caveat + onboarding BP/smoking capture.
- **Phase 4 (aspirational):** organ-age proteomic clocks if SomaScan/Olink data ever ingested; peer-percentile bands once a consented Indian cohort exists.

## Open questions

1. **Baseline definition default** — `first` vs `first-in-range` vs `rolling-12-month median`? Affects every `delta_vs_baseline`/direction. Needs a clinical-advisor decision; currently configurable, default `first-in-range`.
2. **Parameter polarity + within-person CV** source — is `canonical_parameters` extended with `polarity` and `typical_cv`, or a new analysis-side catalog? Needed for `improving/worsening` and `stable` thresholds.
3. **Fasting status** — do `measurements` reliably carry fasting flag for TyG/HOMA-IR/glucose, or is it inferred? Drives `fasting_unconfirmed` caveat frequency.
4. **Diabetes/IFG flag provenance** for NAFLD-FS — onboarding self-report vs HbA1c-derived (≥5.7 IFG / ≥6.5 diabetes)? Define precedence.
5. **CRP units in the wild** — how often is raw CRP unit ambiguous (mg/L vs mg/dL) in Tata 1mg corpus? Determines PhenoAge caveat rate; may need a per-lab unit prior.
6. **Score-level optimal bands** — beyond PhenoAge delta<0, do we publish optimal targets for eGFR/FIB-4, or leave those clinical-range-only to avoid implying a "longevity target" on a diagnostic test?
7. **History retention** of superseded `result_version` — full JSON snapshots in `audit_log` vs reconstruct-on-demand from `inputs_used`. Storage vs reproducibility-latency trade-off for access requests.
8. **HealthKit device params in scores** — do any device-sourced signals (VO2max, RHR, HRV) ever feed a composite, or remain trend-only? Currently trend-only (no clinical score consumes device data).