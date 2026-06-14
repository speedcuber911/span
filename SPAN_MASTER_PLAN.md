# Project Span — Master Implementation Plan

> A longevity-focused, privacy-by-design health app. iPhone-first (native SwiftUI). Users
> ingest lab reports over time, get organ-system trends, validated biological-age + risk
> scores, a clinician-grade doctor-visit prep sheet, and a realtime voice consultant — all
> grounded in cited evidence and framed as **educational, discuss-with-your-clinician**.

**Status of this document.** Produced from a multi-agent research + design pass: 6 sourced
research sweeps, 33 adversarial fact-check verdicts (every formula re-verified against primary
sources), and 6 component architecture designs. Every medical formula below carries its
fact-check status. Citations point to primary sources where the fact-check confirmed them.

**Locked product decisions (founder, 2026-06-14):**

| Decision | Choice | Consequence |
|---|---|---|
| Compliance | **GDPR + India DPDP**, privacy-by-design; residency-aware schema, **India-first deploy** | Region-pinning kept in code/schema; only the **India** stack (ap-south-1) is stood up at launch (matches the Tata 1mg data). EU is a later "add a second box," not a rewrite |
| First deliverable | **Research + full plan only** (this document) | No production code this round |
| Client | **Native SwiftUI iOS** (HealthKit, Sign in with Apple, realtime voice) | Existing React PWA becomes a secondary/legacy web view; Swift Charts replaces Chart.js |
| Backend stack | **TypeScript (Node)**, **plain PostgreSQL**, **app self-hosted on one cheap EC2** (ap-south-1) | Go-cheap = drop always-on managed billing (**no Aurora, no Fargate**); **keep** pay-per-use serverless (**SQS, S3, KMS, DynamoDB, Lambda** — ~$0 at rest). Cloud AI APIs kept. India-only. See §1.2 |
| Medical stance | **Educational — cite + defer** | Never diagnose, never dose; tiered citations; every claim defers to a clinician; bio-age/composite scores are never the headline |

---

### 1.2 Infrastructure profile (cheap, EC2-hosted app, India-first)

This plan was originally drafted assuming a fully managed two-region AWS estate. The founder has
fixed a **lean** profile. The cost rule is precise: **avoid always-on managed compute/DB billing
(Aurora, Fargate); keep pay-per-use serverless (SQS, Lambda, S3, KMS, DynamoDB) — those cost ~nothing
at rest.** Where a later section names a replaced service, read it as the mapping below. The
*architecture* (region pins, RLS, outbox→queue→worker, residency boundaries) is unchanged.

| Concern | Original draft | **Locked profile** | Why |
|---|---|---|---|
| Backend language | Python / FastAPI | **TypeScript (Node)** — Fastify or NestJS, one `/v1` API process | founder choice |
| Database | AWS Aurora PostgreSQL | **Plain PostgreSQL** (self-managed on the EC2, or a small single RDS-Postgres instance — **not** Aurora) | Aurora bills at rest; plain PG is cheap |
| App compute | ECS Fargate, multi-region | **One EC2** in `ap-south-1` (app + worker; Postgres can co-reside to start) | Fargate bills at rest; you own the EC2 |
| **Async queue** | SQS FIFO + DLQ | **SQS FIFO + DLQ — KEPT** | serverless, pay-per-message, ~free at rest |
| Object storage | S3 SSE-KMS | **S3 SSE-KMS — KEPT** (ap-south-1) | pay-per-use, cheapest blob |
| `apple_sub → region` directory | DynamoDB global table | **DynamoDB — KEPT** (single-region table at launch; India-only ⇒ trivially everyone `in`) | serverless, ~free at this scale |
| Inference triggers / glue | (n/a) | **Lambda OK where it fits** (e.g. S3-event → enqueue, light cron) | serverless, pay-per-invoke |
| Regions live | EU + India from day one | **India only — the entire customer base.** `region`/`storage_geo`/`inference_geo` columns stay in so a future EU box is additive, but no EU stack is built. Live driver is **DPDP** (Indian PHI stays in India), not GDPR | all customers India-targeted |
| AI inference | Vertex/Bedrock/Deepgram/Cartesia/Sarvam | **Cloud AI APIs KEPT.** Parse = Gemini + Document AI on **Vertex asia-south1**; voice = **Sarvam** (all-in-India). Only YOUR app+DB self-host | pay-per-call; residency satisfied; self-hosted OCR/VLM stays the later cost-cut fallback (§5) |

**The one-line rule:** *self-host the always-on stuff (app on EC2, plain Postgres); rent the
pay-per-use stuff (SQS, S3, KMS, DynamoDB, Lambda, the AI APIs).*

**What stays true regardless:** Postgres **Row-Level Security** on `user_id`; the **transactional
outbox** relayed to **SQS FIFO**; **append-only audit_log**; **region columns + the residency
assertion** (every PHI row `region='in'` at launch, asserted on read/write so EU adds cleanly);
**SSE-KMS at rest + TLS in transit**; the **one export/delete pipeline**. Going cheap changes the
*always-on boxes*, not the *guarantees* and not the serverless glue.

**Cost sketch (India-only, low volume):** 1× small/medium EC2 (t3.medium/large; app + worker, plus
Postgres to start) + pay-per-use S3 / SQS / DynamoDB / KMS (all ~$0 at rest) + pay-per-use Vertex
(Gemini + Document AI) + pay-per-use Sarvam voice. **No Aurora, no Fargate** line items. Scale the
single instance first; split Postgres onto its own box, then add the EU EC2, only when volume/EU
users justify it.

---

## 1. Executive summary

Span turns a person's scattered diagnostic history (PDFs, photos of paper records, lab emails)
into a longitudinal, organ-system view of their health, plus a small set of **validated,
defensible computed scores** (PhenoAge biological age, CKD-EPI eGFR, FIB-4, TyG, and soft
ratio flags), and an **Opus-generated doctor-visit prep sheet**. A realtime voice consultant
("span-consultant") lets users talk through their data, grounded strictly in their own numbers.

The system is six components over one shared, region-pinned data plane:

1. **Ingestion** — folder/multi-file upload, on-device VisionKit photo capture, and (later)
   Gmail OAuth fetch of lab attachments. Dumb, durable, idempotent; lands bytes in region-locked
   encrypted storage and enqueues one parse job per new artifact.
2. **Pre-analytics / Parsing** — multimodal OCR + LLM extraction (Document AI + Gemini in-region)
   into Span's standardized measurement schema, with deterministic unit normalization, LOINC
   canonicalization, confidence scoring, and human-in-the-loop review.
3. **Analysis** — per-parameter trends, organ-system bucketing (Attia's Four Horsemen +
   Hallmarks of Aging), and the validated scoring models. All medical math runs server-side.
4. **Presentation** — a premium-but-restrained SwiftUI experience: organ-system tiles (not one
   black-box score), Swift Charts trends with reference + optimal bands, a daily QoL check-in
   (WHO-5 / PROMIS), and the doctor-prep sheet.
5. **Span-consultant** — a modular realtime voice pipeline (LiveKit + region-split STT/LLM/TTS),
   RAG-grounded in the user's own data, with hard medical guardrails.
6. **Platform & Compliance** — a TypeScript/Node API + plain Postgres + S3 on **one cheap EC2**
   (ap-south-1, India-first), an in-process async worker, Sign in with Apple, HealthKit ingestion,
   and the GDPR+DPDP consent/export/delete/audit spine. (Region-pinning kept for a later EU box.)

### 1.1 System architecture (launch: single India EC2; residency boundaries kept for later EU)

```
                          ┌──────────────────────────────────────────────┐
                          │            iOS app (SwiftUI, iOS 17+)          │
                          │  HealthKit · VisionKit scan · Sign in w/ Apple │
                          │  Swift Charts · WebRTC voice · NO medical logic│
                          └───────────────┬──────────────────────────────┘
                                          │ HTTPS /v1 (all users India / region='in')
                                          │ presigned PUT (bytes go device→S3 direct)
                                          ▼
   ╔════════════════ ONE EC2 — ap-south-1 (Mumbai). INDIA-ONLY product ═════════════════════╗
   ║                                                                                        ║
   ║   ┌────────────────────────────────────────────────────────────────────────────┐     ║
   ║   │  Node/TypeScript /v1 API  (Fastify/Nest)  +  consent gate                    │     ║
   ║   │  sets Postgres RLS session var (app.current_user_id); region assertion='in'  │     ║
   ║   └───────────────┬───────────────────────────────────┬──────────────────────────┘     ║
   ║                   │ outbox write (same txn)            │ presign S3                      ║
   ║                   ▼                                    ▼                                 ║
   ║   ┌──────────────────────────────┐         ┌────────────────────────────┐               ║
   ║   │ PostgreSQL (plain, RLS)       │         │ S3 ap-south-1 (SSE-KMS)    │               ║
   ║   │ users/measurements/scores/... │         │ raw PDFs + photos          │               ║
   ║   │ + outbox + append-only audit  │         └────────────────────────────┘               ║
   ║   └───────────────┬──────────────┘                                                       ║
   ║                   │ outbox relay  ▼                                                       ║
   ║          ┌────────────────────┐                                                          ║
   ║          │ SQS FIFO + DLQ     │  (pay-per-msg, ~$0 at rest; group=user_id, dedup=id)     ║
   ║          └─────────┬──────────┘                                                          ║
   ║                    ▼                                                                     ║
   ║   ┌──────────────────────────────────────────────┐                                     ║
   ║   │ WORKER (Node, on the same EC2)                │  parse → analyze; idempotent; DLQ   ║
   ║   └───────────────┬──────────────────────────────┘                                     ║
   ║                   │ calls OUT to cloud AI (per-call, in-region):                        ║
   ║                   ▼                                                                     ║
   ║         Vertex AI asia-south1: Gemini + Document AI (parse/OCR)                          ║
   ║         Voice: Sarvam (all-in-India STT/TTS/LLM)                                         ║
   ╚════════════════════════════════════════════════════════════════════════════════════════╝
   Also rented (pay-per-use, ~$0 at rest): S3 · SQS · KMS · DynamoDB (apple_sub→region) · Lambda glue.
   On-device privacy tier: Apple SpeechAnalyzer / whisper.cpp STT + AVSpeechSynthesizer TTS —
   audio never leaves the phone.

   HARD RULE (enforced in code): India PHI may ONLY touch ap-south-1 / Vertex asia-south1. Claude is
   EXCLUDED from the India path (Bedrock-India = global cross-region; first-party Claude = US). The
   `region` column + residency assertion stay in so a future EU box is additive, but EU is NOT a
   current target — India is the whole customer base for now.
```

The product is **India-only** for now (all customers India-targeted). `region` is modeled as a
column + two pins per user purely so a future EU deployment is additive, not a migration — but at
launch every user is `region='in'`, `storage_geo='ap-south-1'`, `inference_geo='asia-south1'`, and
the residency machinery exists to satisfy **DPDP** (keep Indian PHI in India), not to serve EU today.

---

## 2. Scientific foundation

Span separates two layers the research found are very different in evidence strength:

- **A strongly-evidenced preventive cardiometabolic + fitness core** — what Span builds on
  confidently (Tier 1).
- **A contested geroscience/supplement frontier** — surfaced only with explicit "no human
  outcome RCT / contested / discuss with your clinician" framing and disclosed conflicts (Tier 3).

### 2.1 Frameworks adopted

- **Attia (Medicine 3.0).** Top-level risk buckets = the **Four Horsemen**: ASCVD, cancer,
  neurodegeneration, metabolic dysfunction — these become Span's organ-system grouping.
  Stricter-than-clinical **optimal targets** (encoded as a *separate* band, labeled "expert
  opinion, discuss with clinician", **never** the clinical reference range): apoB < 60 mg/dL,
  Lp(a) < 50 nmol/L optimal / > 100 very-high (genetic, one-time test), HbA1c < 5.5%,
  triglycerides < 100 mg/dL, uric acid < 5.0 mg/dL, ALT < 20 U/L. Four exercise pillars
  (Stability, Strength, Zone-2, VO2max) + grip strength as non-blood levers from HealthKit +
  user input; VO2max framed (observational) as a strong modifiable mortality correlate.
- **Hallmarks of Aging (López-Otín 2023, 12 hallmarks — fact-check CONFIRMED).** Mechanistic
  ontology mapping each biomarker to *why it matters* (e.g. CRP → chronic inflammation;
  glucose/insulin → deregulated nutrient-sensing). Drives the "Why this matters" copy.
- **Three-tier evidence classification** applied to every suggestion and every voice answer:
  - **Tier 1** consensus/safe — exercise, apoB/Lp(a) management, omega-3 sufficiency
    (index ≥ 8%), vitamin D repletion, metabolic control. Shown confidently.
  - **Tier 2** promising-incomplete — fasting-mimicking / time-restricted eating, ketones.
  - **Tier 3** contested/experimental — NMN, resveratrol, metformin-for-non-diabetics,
    rapamycin. Shown ONLY with contested framing + disclosed conflicts (e.g. Sinclair/NMN).
    **Never with doses.**

### 2.2 Validated scoring models — fact-check status

> Every formula below was independently re-verified against primary sources. **Implement only
> the CONFIRMED set as core.** Unit handling is the #1 implementation bug — see §5.

| Model | Status | Implement? | Notes from fact-check |
|---|---|---|---|
| **PhenoAge** (biological age) | ✅ CONFIRMED verbatim (Levine 2018, PMC6388911) | **Core / flagship** | 9 labs + age, closed-form. Coefficients + Gompertz γ=0.0076927 + conversion constants all match. Author is Levine **ME** (not ML). Units must be exact (CRP mg/dL, creatinine µmol/L, glucose mmol/L, albumin g/L). |
| **CKD-EPI 2021** race-free eGFR | ✅ CONFIRMED (Inker NEJM 2021) | **Core** | Use 2021 exponents −0.241(F)/−0.302(M), **not** 2009 −0.329/−0.411. |
| **FIB-4** (liver fibrosis) | ✅ CONFIRMED (Sterling 2006) | **Core** | Derivation pop was HIV/HCV co-infection. **Age > 65 → use lower cutoff 2.0**, not 1.45 (AGA/AASLD). |
| **NAFLD-FS** (liver) | ✅ CONFIRMED (Angulo 2007, PMID 17393509) | **Core, gated** | Needs BMI + diabetes/IFG flag → collect at onboarding. |
| **TyG** (insulin resistance) | ✅ CONFIRMED | **Core** | No insulin needed (TG + fasting glucose). No universal cutoff → trend/relative only. |
| **HOMA-IR** | ✅ CONFIRMED | If fasting insulin present | Most Indian panels lack fasting insulin → often N/A. |
| **NLR / AAR (De Ritis) / PLR** | ✅ CONFIRMED as context-dependent | **Core, as soft flags/trends** | No single diagnostic cutoff — present as longitudinal trend + soft flag, never a threshold verdict. |
| **KDM** biological age | ✅ formula confirmed | **Phase 2** | Requires fitting on a reference cohort (NHANES via dayoonkwon/BioAge). |
| **Homeostatic Dysregulation** (Mahalanobis) | ✅ formula confirmed | **Phase 2** | Requires reference-cohort fitting; recalibrate on Indian population. |
| **Allostatic Load** | ⚠️ no canonical formula | **Partial, later** | Only a blood-only subscore (HbA1c, cholesterol, HDL, CRP) computable; dataset lacks BP/cortisol/catecholamines. Quartile cutoffs from Span's own population. |
| **SCORE2 / ASCVD** (CV risk) | ✅ formulas confirmed | **Gated, with caveat** | Need BP + smoking + BP-treatment + diabetes (collect at onboarding). **Neither is calibrated for South-Asian/Indian populations** → present as educational estimate with an explicit not-calibrated-for-India caveat. |
| **Organ-age proteomic clocks** (Oh 2023 Nature) | ⚠️ needs SomaScan/Olink proteomics | **Out of scope** | NOT computable from CBC/lipids. Aspirational framing only. (The fact-check also caught that the magnitude figures "150%/250%" were journalistic, and the cited Nature Medicine 2024 paper is a *different* OLINK clock, Argentieri et al.) |
| **Charlson Comorbidity Index** | ⚠️ needs ICD diagnoses | **Out of scope** | Driven by a diagnosis/problem list, not labs. Revisit when diagnosis data is ingested. |

### 2.3 Exact formulas (the CONFIRMED core)

**PhenoAge** (Levine 2018). Inputs: albumin, creatinine, glucose, CRP, lymphocyte %, MCV, RDW,
ALP, WBC, chronological age.

```
xb = -19.90667
   - 0.03359355 * albumin[g/L]
   + 0.009506491 * creatinine[µmol/L]
   + 0.1953192   * glucose[mmol/L]
   + 0.09536762  * ln(CRP[mg/dL])
   - 0.01199984  * lymphocyte_percent
   + 0.02676401  * MCV[fL]
   + 0.3306156   * RDW_percent
   + 0.001868778 * ALP[U/L]
   + 0.05542406  * WBC[1000 cells/µL]
   + 0.08035356  * age[years]

M        = 1 - exp( -1.51714 * exp(xb) / 0.0076927 )         # 10-yr mortality score
PhenoAge = 141.50225 + ln( -0.0055305 * ln(1 - M) ) / 0.090165   # years
```
**Unit conversions (the #1 bug — silently wrong otherwise):** CRP mg/dL = (mg/L ÷ 10);
creatinine µmol/L = (mg/dL × 88.42); glucose mmol/L = (mg/dL ÷ 18); albumin g/L = (g/dL × 10).

**CKD-EPI 2021 race-free eGFR** (mL/min/1.73m²):
```
eGFR = 142 * min(Scr/κ, 1)^α * max(Scr/κ, 1)^(-1.200) * 0.9938^age * (1.012 if female)
  Scr in mg/dL ;  κ = 0.7 (F) / 0.9 (M) ;  α = -0.241 (F) / -0.302 (M)
```

**FIB-4** (liver fibrosis):
```
FIB-4 = (age * AST[U/L]) / ( platelets[10^9/L] * sqrt(ALT[U/L]) )
  <1.45 rule-out advanced fibrosis  ;  >3.25 advanced  ;  between = indeterminate
  IF age > 65: use lower cutoff 2.0 instead of 1.45
```

**NAFLD Fibrosis Score** (needs BMI + diabetes/IFG flag):
```
NFS = -1.675 + 0.037*age + 0.094*BMI[kg/m²] + 1.13*(IFG_or_diabetes:1/0)
      + 0.99*(AST/ALT) - 0.013*platelets[10^9/L] - 0.66*albumin[g/dL]
  < -1.455 exclude advanced  ;  > 0.676 advanced  ;  between = indeterminate
```

**TyG** (insulin resistance, no insulin assay needed):
```
TyG = ln( triglycerides[mg/dL] * fasting_glucose[mg/dL] / 2 )   # trend/relative only, no fixed cutoff
```

**HOMA-IR** (only if fasting insulin available):
```
HOMA-IR = ( fasting_insulin[µU/mL] * fasting_glucose[mg/dL] ) / 405
```

**Ratio soft-flags** (trend indicators, NOT diagnostic thresholds):
`NLR = neutrophils / lymphocytes` · `AAR (De Ritis) = AST / ALT` · `PLR = platelets / lymphocytes`.

### 2.4 Medical-safety policy (encoded everywhere)

- Every factual claim and every suggestion carries a **tiered citation** and **defers to a clinician**.
- **No diagnoses, no doses.** Server-side guardrails strip any model output that names a disease
  for the user, prescribes a dose, or tells the user to start/stop a medication.
- **Composite scores / biological age are never the headline** — they are secondary, opt-in,
  bounded, with a "this fluctuates day to day / directional only" caption. (Clinician critique
  the fact-check confirmed: false precision, ~⅓ of one app's "biomarkers" were derived ratios,
  ~10 flagged "abnormals" had no clinical significance, supplement upsell.)
- **Risk is shown in natural frequencies** ("about 31 out of 100 people like you…") + icon
  arrays, never bare percentages (Gigerenzer).
- **Trends are shown against the user's own baseline first**, population second.

### 2.5 Instrument licensing (fact-check caught these — must clear before shipping)

| Instrument | Use | Licensing reality |
|---|---|---|
| **WHO-5 Well-Being** | Primary daily/weekly QoL check-in | CC-BY-NC-SA 3.0 IGO → **free non-commercial only**; a commercial app must clear WHO commercial terms. Shortening the 14-day recall for daily use **voids strict validation** (label as a product modification). Screen-positive cutoff ≤ 50% (raw < 13); sensitivity ~0.86 / specificity ~0.81 (Topp 2015 — **not** 0.87/0.76). |
| **PROMIS Global-10**, Fatigue 4a, Sleep Disturbance 4a | Whole-person T-score bands + domain check-ins | **Public domain / free.** This is the spine. |
| **EQ-5D-5L** | (excluded v1) | Licensed; commercial use ≈ €7,000. Utility can go **negative** (not 0–1). |
| **ESS (Epworth)** | (prefer PROMIS Sleep instead) | Copyrighted (Mapi Research Trust) — license needed. |
| **PAM (Patient Activation)** | Tiering UI verbosity | Proprietary (Insignia Health) → use a **"PAM-style" home-grown** 4-level model, not the licensed PAM-13. |

---

## 3. Unified data model (all components agree on this)

**Plain PostgreSQL** (self-hosted on the EC2; not Aurora), **Row-Level Security keyed on `user_id`**.
At launch every row is `region='in'` (single India box); the `region` column + assertion stay so EU
is a later second deployment, not a migration. Raw files in S3 ap-south-1 (SSE-KMS). The model
generalizes the existing single-patient `health_data.json` (Measurement/ParamCatalog) to multi-user,
and adds LOINC + provenance + the computed/consent/audit tables. **The async queue is itself a
Postgres table** (`jobs`, claimed with `SELECT … FOR UPDATE SKIP LOCKED`) — no SQS. `region` stays
`check (region in ('in','eu'))` for forward-compat even though only `in` is used now.

```
-- Identity, lawful basis, audit -------------------------------------------------
users(id uuid pk, apple_sub text unique, email_private bool,
      region text check (region in ('in','eu')),               -- immutable residency pin
      sex text, dob date, created_at timestamptz)
profiles(user_id uuid pk fk, height_cm numeric, weight_kg numeric, bmi numeric,
      smoking_status text, bp_systolic int, bp_treated bool, diabetes_status text,
      chronic_conditions text[], current_supplements text[], updated_at timestamptz)
consents(id uuid pk, user_id fk, scope text,                    -- ingestion|gmail_readonly|processing|storage|voice
      purpose text, policy_version text, granted bool, method text,
      granted_at timestamptz, withdrawn_at timestamptz, ip_at_grant inet, evidence_blob jsonb)
audit_log(id bigserial pk, user_id uuid, actor text, action text,  -- APPEND-ONLY
      entity text, entity_id uuid, region text, at timestamptz, meta jsonb)

-- Ingestion --------------------------------------------------------------------
ingestion_artifacts(id uuid pk, user_id fk, region text, source enum('folder','photo','gmail'),
      original_filename text, mime_type text, byte_size bigint, content_sha256 char(64),
      storage_bucket text, storage_key text, kms_key_id text, page_count int,
      gmail_msg_id text, gmail_attachment_id text, sender_domain text,
      captured_at timestamptz, uploaded_at timestamptz, av_scan enum('pending','clean','infected'),
      UNIQUE(user_id, content_sha256))                          -- exact-dedup
ingestion_jobs(id uuid pk, artifact_id fk unique, user_id fk, region text,
      status enum('intent_created','uploading','uploaded','enqueued','parsing',
                  'needs_review','extracted','committed','failed','duplicate','quarantined'),
      idempotency_key text, attempt int, error_code text, progress_pct int,
      UNIQUE(user_id, idempotency_key))
ingestion_outbox(id uuid pk, job_id fk, topic text, payload jsonb, published bool)
gmail_sync_state(user_id pk, history_id text, last_synced_at timestamptz, allowed_senders text[])

-- Canonical dictionary (drives parsing/normalization; versioned, mostly non-PHI) -
canonical_parameters(canonical_param_id text pk, display_name text, loinc_code text,
      loinc_status enum('mapped','candidate','unmapped'), category text,
      specimen enum('serum','plasma','whole_blood','urine','rbc',...),   -- splits creatinine serum vs urine
      canonical_unit text, plausibility_low numeric, plausibility_high numeric,
      default_ref_low numeric, default_ref_high numeric, aliases text[], alias_regexes text[],
      optimal_band jsonb,                                        -- {low,high,direction,evidence_tier,source_id}
      is_ratio bool, version int)
unit_rules(canonical_param_id fk, raw_unit_normalized text,
      conversion_kind enum('identity','alias','linear','scale','nonlinear_blocked'),
      factor numeric, offset numeric, guard_min numeric, guard_max numeric, note text,
      primary key(canonical_param_id, raw_unit_normalized))

-- The measurement (superset of the existing flat schema) ------------------------
reports(id uuid pk, user_id fk, artifact_id fk, lab text, report_date date, region text, s3_key text)
measurements(id uuid pk, user_id fk, report_id fk,
      date date, parameter text, parameter_raw text, category text,
      canonical_param_id text fk, loinc_code text,               -- canonical id + LOINC
      value numeric, value_text text, value_operator enum('=','<','>','<=','>='),  -- censored "<200"
      unit text, unit_raw text,
      ref_low numeric, ref_high numeric, ref_text text, ref_qualifier jsonb,       -- {sex,age_gt}
      flag enum('High','Low','Normal'), lab text, sources text[],
      field_confidence jsonb, extraction_status enum('auto_accepted','human_reviewed','human_corrected'),
      bbox jsonb,
      UNIQUE(user_id, report_id, parameter, date))               -- idempotent upsert key
review_tasks(id uuid pk, ingestion_id fk, measurement_draft jsonb,
      reason enum('low_conf','outlier','unmapped_param','unit_ambiguous'),
      assigned_to text, decision enum('accept','correct','reject'), corrected jsonb, resolved_at timestamptz)
parameter_catalog(user_id, parameter, category, unit, count, numeric_count,
      first_date, last_date, latest_value, latest_value_text, ref_low, ref_high)  -- per-user materialized

-- Computed analysis (consumed by Presentation + voice) --------------------------
analysis_results(...)   -- see §6 Analysis (system rollups, parameter stats)
scores(...)             -- PhenoAge/eGFR/FIB-4/TyG/NFS/ratios, versioned, with input lineage
optimal_bands(...)      -- global, tiered, cited (apoB<60 etc.) — see §6
qol_entries(...)        -- WHO-5 / PROMIS responses + computed bands — see §8 Presentation
healthkit_samples(...)  -- steps/sleep/HRV/RHR/VO2max/workouts as a 'device' lab source — see §10
voice_sessions(...)     -- realtime consultant sessions + transcripts — see §9
prep_reports(...)       -- structured Opus PrepReport JSON — see §8 Presentation

-- Citations (the cite+defer backbone; global, non-PHI) --------------------------
sources(id pk, tier int, kind enum('guideline','peer_reviewed','expert_opinion','contested'),
      title text, citation_text text, url text, claim_supported text, conflict_disclosure text)
```

S3 layout: `s3://span-phi-{region}/u/{user_id}/raw/{artifact_id}.{ext}` (+ `/pages/`, `/derived/`
for OCR/extraction lineage). SSE-KMS per object, Object Lock, lifecycle expiry on derived blobs.

FHIR alignment: each `measurement` maps to an `Observation` (code=loinc_code,
valueQuantity={value,unit}, referenceRange, interpretation=flag, effectiveDateTime=date, subject=user).

---

## 4. Component — Ingestion layer

**Purpose.** The front door for all PHI. Accepts reports via (a) bulk folder/multi-file upload,
(b) on-device VisionKit photo capture of physical records, (c) Gmail OAuth fetch of lab
attachments (later phase). It is deliberately **dumb and durable**: authenticate, capture
verifiable consent *before any byte is stored*, pin storage+inference geo to the user's region,
move bytes device→bucket via short-lived presigned PUT (bytes never transit the app server),
deduplicate by content hash, guarantee idempotency, drive a clear progress UX, and hand off
exactly one parse job per *new* artifact. It does **not** parse or interpret.

Grounded in the real corpus: ~59 source files across **21 distinct labs** (Healthians 710,
CLUMAX 103, Thyrocare 94, Tata 1mg 43, +16 others; 165 measurements with no lab attributed) —
exactly the heterogeneity ingestion must normalize into a uniform artifact stream.

**Architecture (the three paths converge on one state machine):**

```
 [Folder picker]   [VisionKit scan]   [Gmail OAuth worker]
        \               |                    /
         ▼              ▼                   ▼
   POST /v1/ingestion/intents  (consent gate → 409 if no active consent;
                                residency router → bucket/kms/inference_geo;
                                dedup → UNIQUE(user_id, content_sha256))
        │ presigned PUT (a,b)        │ internal put (c: server already holds bytes in-region)
        ▼                            ▼
   S3 (region-locked, SSE-KMS, Object Lock, lifecycle)
        │ POST /v1/ingestion/{job}/complete → verify ETag/size + MIME sniff + AV scan
        ▼
   ingestion_jobs FSM (Postgres)  ──outbox(same txn)──▶  SQS FIFO
        │   (MessageDeduplicationId = artifact_id; MessageGroupId = user_id)
        ▼
   topic ingestion.parse.requested  →  [PRE-ANALYTICS]
        ▲
   topic ingestion.parse.completed  ←  (drives app progress UX)
```

**Three idempotency/dedup layers:** (1) client `Idempotency-Key` per logical action (24h replay);
(2) content dedup `UNIQUE(user_id, content_sha256)` → re-upload resolves to existing artifact;
(3) queue dedup `MessageDeduplicationId = artifact_id` + idempotent consumers (upsert on
`(user_id, report_id, parameter, date)`). Near-duplicates (re-encoded Gmail resend, photo of an
already-uploaded PDF) bypass exact-hash → surfaced as a **merge suggestion in review**, never auto-merged.

**Key interfaces.**
```
POST   /v1/ingestion/intents            -> [{artifact_id, job_id, verdict:'new'|'duplicate',
                                            upload:{url,method:PUT,headers:{SSE-KMS...},expires_at}}]
PUT    <presigned-s3-url>               -- client → bucket direct
POST   /v1/ingestion/{job_id}/complete  -> {status:'enqueued'}  (writes status + outbox row in one txn)
GET    /v1/ingestion/jobs?status=&since= -- progress polling (+ optional SSE stream)
POST   /v1/integrations/gmail/connect    -- OAuth PKCE, scope gmail.readonly
POST   /v1/integrations/gmail/sync       -- server-side: from:(lab senders) has:attachment filename:pdf
DELETE /v1/integrations/gmail            -- revoke token + Google revocation endpoint
-- Queue contract (ingestion → pre-analytics):
ingestion.parse.requested { job_id, artifact_id, user_id, region, inference_geo:'in'|'eu',
   storage:{bucket,key,kms_key_id}, source, mime_type, page_count?, hint:{sender_domain?,lab_guess?,
   original_filename}, content_sha256 }
```

**Tech choices.** VisionKit `VNDocumentCameraViewController` (on-device de-skew/enhance → only the
cleaned doc leaves the phone); presigned S3 PUT with per-object SSE-KMS; S3 ap-south-1 (+ MinIO
on-prem as the later fallback); **plain PostgreSQL** with RLS; **SQS FIFO + transactional outbox**
(pay-per-use, kept); **TypeScript/Node API + worker** on the EC2; Sign in with Apple as primary login
(Gmail OAuth is a *data-access* grant, decoupled from identity); restricted `gmail.readonly` scope →
**Google CASA Tier 2/3 assessment (~$15k–$75k, re-passed every 12 months, weeks lead time)** →
defer Gmail past MVP.

**Risks.** Gmail CASA recurring cost/lead time (mitigate: ship folder+photo first, feature-flag
Gmail); DPDP future data-localization (India already fully pinned to ap-south-1; keep MinIO/self-host
fallback); accidental Claude/Bedrock-India routing breaking residency (inference_geo pin + hard
policy guard); presigned-URL leakage (short TTL, single-use, bound to key+SSE headers); poison/malware
uploads (MIME+AV+size caps before enqueue → quarantine); consent-before-storage ordering bug
(server-side consent gate, not client-side).

**Phased build.** P0 spine (plain Postgres + RLS, S3 ap-south-1, SiwA, consents+audit, `region='in'`
assertion) → P1 bulk folder upload end-to-end (stub parse consumer) → P2 VisionKit capture + full
progress UX → P3 real pre-analytics handoff → P4 Gmail (gated on CASA) → P5 rights/erasure +
on-prem fallback.

---

## 5. Component — Pre-analytics / Parsing layer

**Purpose.** Turn any lab artifact (PDF, photo, handwritten, any of 21+ labs, Indian or
international) into rows matching Span's standardized measurement schema, with deterministic
normalization, LOINC canonicalization, confidence scoring, and human-in-the-loop review. The
current hand-built dataset already encodes the hard problems; this layer **formalizes those hand
rules into a deterministic, multi-region pipeline.**

**The four hard problems (all observed in the real data):**
1. **Unit chaos within one canonical parameter** — T3 as ng/mL vs ng/dL vs nmol/L (100× trap);
   B12 as pg/mL vs ng/mL (1000×); Lp(a) mg/dL vs nmol/L (**non-linear, contested**); ESR in 7
   spellings; eGFR in 4. **The single highest-severity risk** — a wrong factor silently corrupts a trend.
2. **Parameter canonicalization** — up to 16 raw spellings → one canonical (HbA1c); LOINC correctly
   *splits* "Creatinine" into serum vs urine specimens (collapsing them pollutes eGFR/kidney trends).
3. **Reference-range parsing** — `3.5-5.0`, `[8.00-23.00]`, `Male > 51 Years: 56 - 119`, `<200 IU/ml`,
   `Negative < 25`. 251/1536 rows have one bound, 202 none; ranges carry sex/age conditionals.
4. **Non-numeric / censored values** — `Negative`, `Trace`, `> 24`, `<200`, and real misparsed
   outliers — preserved via `value_text` + `value_operator`, kept searchable, excluded from the line.

**Architecture.**
```
S3 raw → SQS → region-pinned worker
  STAGE 1  Document AI (regional asia-south1 / europe-west3): OCR + Form Parser (tables) + Layout
  STAGE 2  Gemini (Vertex regional): FORCED tool-call emit_lab_report (no prose); page images +
           Document AI tables as grounding; run N=3 (self-consistency) → per-field agreement
  STAGE 3  DETERMINISTIC post-proc (pure code, testable, NO LLM):
             3a canonicalization (alias → fuzzy → ML mapper → unmapped tail to review)
             3b unit normalization via unit_rules table (incl. nonlinear_blocked for Lp(a))
             3c reference-range parse → ref_low/high + ref_qualifier (sex/age)
             3d category bucketing (dictionary owns it; LLM never picks category)
             3e flag derivation (trust lab flag, else derive from bounds)
             3f outlier guards (plausibility window → value:null, keep value_text, raise review)
             3g dedup (collapse identical, union sources[])
  STAGE 4  Confidence router: HIGH ≥0.90 auto-accept · MID 0.60–0.90 review queue · LOW flag/reject
  STAGE 5  Persist → Postgres measurements (FHIR-aligned) + S3 lineage (raw + ocr.json + extraction.json)
```

**Critical rule: the LLM transcribes only; it never converts units, canonicalizes names, invents
ranges, or picks categories.** All determinism is in code with post-conversion `guard_min/guard_max`
sanity windows — any conversion landing outside the plausibility window is forced to review.

**LLM tool-schema contract** (`emit_lab_report`): per row `parameter_raw`, `value_text` (verbatim,
incl. `Negative`/`<200`/`> 24`), `value_numeric|null`, `value_operator`, `unit_raw`, `ref_text`,
`ref_low/high` (only if cleanly printed), `flag_printed`, `bbox`, `confidence`. System prompt:
*"Transcribe ONLY what is printed. Do NOT diagnose, canonicalize, convert units, or invent ranges."*

**Tech choices.** Vertex AI Gemini (regional asia-south1 / europe-west3 — the only single-vendor
stack keeping both OCR and LLM in-region, BAA-eligible, CMEK+VPC-SC); Document AI (OCR + Form +
Layout); Claude (Opus 4.8 vision) via Bedrock eu-central-1 **EU-only or de-identified** (excluded
from India PHI path); region S3; **self-hosted PaddleOCR PP-StructureV3 / Surya + local VLM fallback
designed in from day one** for air-gap/on-prem; LOINC canonical id + parameter_raw fallback;
ML/rule auto-mapper (RF ~94.5%) with human review of the unmappable tail.

**Phased build.** P0 formalize rules as data (seed canonical dictionary + unit_rules from the 159
existing params; golden-test that re-derives `health_data.json` from raw fields) → P1 folder/photo
single-region MVP (India first, HITL on by default) → P2 confidence + HITL automation (self-consistency
N=3, plausibility guards, reviewer UI with bbox highlight) → P3 EU region + Bedrock-EU + residency
hardening (VPC-SC/IAM perimeter, CI residency assertions) → P4 self-hosted fallback + handwriting
robustness + dictionary feedback loop → P5 Gmail ingestion.

---

## 6. Component — Presentation layer (SwiftUI + Opus prep sheet)

**Purpose.** Turn normalized data into a premium-but-restrained native SwiftUI experience + an
Opus-generated doctor-visit prep sheet. Governing rule everywhere: **educational, cite + defer,
never a single composite score as the headline.**

**The central decision — reject "one big number."** Per the research, single composite scores and
"biological age" draw the heaviest clinician criticism (false precision, snapshot problem). Instead
the home screen is a grid of **organ-system tiles** (Attia Four Horsemen mapping) each carrying the
same **three-zone traffic light** (Red = outside clinical reference / Yellow = clinically normal /
Green = evidence-based optimal — Green shown *only* where a peer-reviewed optimal band exists).
PhenoAge **is** computed but is secondary, opt-in, behind a tap, shown only as a trend with a
"fluctuates day to day / directional only" caption — never drives suggestions.

**Five surfaces (TabView: Today · Systems · Check-in · Prep + a floating "Ask span" mic):**
1. **Today / whole-person overview** — two PROMIS Global-10 band gauges (Global Physical/Mental
   Health T-scores, population-normed so no proprietary number needed), a calm "markers to discuss"
   rail, the 8 organ-system tiles, a collapsed "biological age trend (optional)" link, and a
   persistent "Educational only · discuss with clinician" footer. **No giant score.**
2. **System detail** — member parameters with sparklines + trend arrows + the Hallmark/Horseman
   it maps to ("Why this matters"); "Ask span about my [system]" deep-link.
3. **Parameter detail (Swift Charts centerpiece)** — `RectangleMark/AreaMark` clinical reference
   band + a second tinted **optimal band** (with tap-through citation + evidence-tier badge) +
   `LineMark` + flag-colored `PointMark`; `value==null` as annotated markers; weekly/28-day/1y/all
   windows, baseline-first; a **"how unusual is this?"** card in natural frequencies + icon array.
4. **Check-in (daily QoL)** — WHO-5 card stack (raw×4 → 0–100; soft ≤50 nudge framed as "discuss
   how you've been feeling", never "depression"); PROMIS Fatigue/Sleep rotation; a gentle,
   explicitly **non-causal** "your lower-energy days tend to follow shorter sleep" co-occurrence
   card against HealthKit data.
5. **Prep (Opus doctor-visit prep sheet)** — structured `PrepReport` JSON rendered natively, modeled
   on the existing `Doctor_Visit_Prep.docx` tone: "raise this first", a glance table, AHRQ-style
   **Question Prompt List grouped by system**, a lifestyle/supplements table (Why/Caution/Verdict,
   **dose always null**, tier + citations), a coaching note ("tick what matters; feeling a bit anxious
   writing these is normal"), and "gaps your clinician likely missed" (stale/never-tested markers).

**Opus prep-sheet contract + guardrails (enforced in code AFTER the model returns):**
- System role: *"You are Span's clinical-context summarizer. NOT a doctor. Produce an EDUCATIONAL
  prep sheet. NEVER diagnose, NEVER prescribe/suggest doses, NEVER tell the user to start/stop a
  medication. Every claim cites a provided source id and defers to the clinician. Output only valid
  PrepReport JSON."*
- Input context (assembled server-side, in-region): user_profile (age/sex/chronic conditions/
  supplements), out_of_range, precomputed trends (model does NO math), optimal_gaps,
  gaps_clinician_likely_missed, allowed_sources (model may not invent citations), locked_rules.
- Post-gen guards: schema-validate (reject any non-null dose → regenerate); every row must cite
  ≥1 allowed source (strip uncited); Tier-3/contested items must carry contested framing or are
  downgraded; banned-phrase filter ("you have [disease]", "take X mg", "stop your medication",
  "diagnosis"); disclaimer appended in code; one auto-retry then human-review queue.

**Data flow.** All medical logic (PhenoAge, slopes, system rollups, optimal-band lookups,
natural-frequency percentiles, the Opus job) runs **server-side in the TypeScript analysis layer**;
the SwiftUI client receives ready-to-render DTOs and embeds no coefficients. HealthKit is read
on-device, normalized as a "device" lab source, POSTed to the backend so QoL/longevity scoring
sees lab + wearable uniformly.

**Key endpoints.** `GET /v1/overview` · `/v1/systems/{key}` · `/v1/parameters/{id}` (+`/trend`) ·
`/v1/bioage` · `/v1/citations/{id}` · `GET /v1/checkin/next` + `POST /v1/checkin/responses` ·
`GET /v1/promis/global` · `POST /v1/prep/generate` → `GET /v1/prep/reports/{id}` (+`/pdf`) ·
`POST /v1/voice/session`.

**Phased build.** M1 port Parameter Detail (Swift Charts) to SwiftUI → M2 whole-person overview
(8 system tiles + attention rail) → M3 two-range-layer optimal bands + tiered citations +
natural-frequency card → M4 WHO-5 + PROMIS check-in + non-causal HealthKit co-occurrence → M5
Opus prep sheet + full guardrail stack → M6 PhenoAge opt-in + PAM-style activation tiering →
M7 span-consultant entry point + context-bundle handoff.


---

## 7. Component — Analysis layer (scientific core)

**Purpose.** Turn normalized `measurements` into longitudinal trends, organ-system status rollups,
and the validated scores, materialized into `analysis_results` for Presentation + Voice to consume
read-only. **This is the only place medical logic lives** — the SwiftUI client and the voice RAG
agent are thin and never compute anything clinical.

**Design contract.**
- **Stateless, deterministic, versioned.** Every score/trend is a pure function of (input
  measurement set, `formula_version`, `catalog_version`). Same inputs + versions → byte-identical
  output. Makes recompute, audit, and explainability tractable.
- **Educational stance is structural.** No `analysis_results` row is emitted without an
  `evidence_tier`, a `disclaimer_key`, and full input provenance (`inputs_used` listing which
  `measurement.id` fed it). A score that cannot be grounded in stored measurements is **not
  produced** — never fabricated, never imputed-and-hidden.
- **Three-zone semantics everywhere.** Red = outside clinical reference; Yellow = inside clinical
  but outside peer-reviewed optimal; Green = inside optimal. Clinical range and optimal band are
  *different objects, different sources, different tiers*, kept separate end-to-end.

**Architecture.** A worker pool + read API, triggered via the transactional outbox / SQS FIFO
(`MessageGroupId = user_id` → per-user ordering + debounce). Every engine calls the **shared
biomarker normalization service** — no engine reads a raw `measurements` row directly:

```
 measurements.committed / device.synced / facts.changed / catalog.version_changed
        → SQS FIFO (group=user_id, debounced) → RECOMPUTE PLANNER (minimal affected set)
        → ANALYSIS WORKER (TypeScript/Node, deterministic numeric code, NO PHI to any LLM):
            1. LOAD measurements (RLS) + canonical_parameters + onboarding facts
            2. NORMALIZE → NormalizedValue{value, canonical_unit, clinical_ref, optimal_band,
                           tier, citation, provenance: measurement_id, unit_xform}
            3a TREND ENGINE   3b SCORE ENGINE   3c ORGAN BUCKETER   3d PROVENANCE/EXPLAIN
            4. MATERIALIZE (idempotent UPSERT keyed by result_version) →
               parameter_stats | scores | analysis_results  + audit_log(inputs_used, versions)
        → /v1/overview · /v1/systems/{key} · /v1/parameters/{id} · /v1/bioage  (read-only)
```

Ingestion→analysis is **eventually consistent**; the read API serves the last materialized
`result_version` and never blocks on recompute; a failed recompute leaves the prior version live
(transactional per-user-per-version UPSERT, no partial writes).

**Trend algorithm (per parameter, any user).** Baseline = first-in-range point (configurable);
**slope via Theil–Sen estimator** (median of pairwise slopes — robust to lab outliers and tiny n)
+ bootstrap CI; skip if `n < 3` (`insufficient_data`). Direction uses **parameter polarity** (is
"down" good? LDL down = improving, eGFR down = worsening) mapped through the signed slope;
confidence high/moderate/low from CI + n. `pct_in_range` + a per-point `zone_timeline` drive the
Swift Charts band overlay. Educational guardrail: language is "trending toward/away from your
optimal range," never "improving disease."

**Organ-system rollup (false-precision-avoiding).** A static catalog-versioned map
`canonical_param_id | category → organ_system_key`, each system tagged to Four Horsemen + Hallmarks
(why-it-matters ontology, not a score). **Discrete 3-level status, never a numeric organ score:**
`attention` (≥1 member outside clinical range) / `monitor` (0 red, ≥1 outside optimal) / `on_track`
(all inside optimal) / `not_enough_data`. Each tile shows `status_basis` = a *count* ("1 red, 2
yellow of 9 measured"), not a fake percentage. Composite scores (FIB-4, eGFR) contribute via their
band → so a normal-LFT panel with high FIB-4 still flags `liver = attention`.

The 8 tiles: `metabolic`, `cardiovascular`, `liver`, `kidney`, `inflammation_immune`,
`hematologic`, `endocrine_thyroid`, `micronutrient_bone`.

**Score engine.** Implements the §2.3 confirmed formulas, each consuming `normalize_for_score(...)`
with mandatory `target_units`, persisting `inputs_used` with `unit_xform` for explainability. Each
score row carries `formula_version`, `evidence_tier`, `computable`, `missing_inputs`, `caveats`
(e.g. `not_calibrated_india`, `crp_unit_assumed_mgL`, `trained_nhanes3`). **All 9 PhenoAge inputs
required — no imputation;** missing → `computable=false` + `missing_inputs` surfaced as an "add to
unlock" prompt. Ratios (NLR/AAR/PLR) are `band=null` trend-only soft flags that can nudge a tile to
`monitor` but never alone to `attention`.

**Shared normalization service** (in-proc TypeScript module, also `/internal/v1/normalize`):
`normalize(m, sex, age, catalog_version) → NormalizedValue` and
`normalize_for_score(params, required, target_units, …) → (resolved, missing_inputs)`. Three jobs:
unit canonicalization + plausibility clamp (out-of-bounds → excluded from scores, flagged
`unknown`); clinical reference resolution (lab-provided, else `canonical_parameters` default,
`ref_source` recorded); optimal-band resolution from the tiered `optimal_bands` catalog. The
persisted `{measurement_id, raw→norm value, unit_xform, ref_source, tier}` **is** the GDPR/DPDP
`/internal/v1/explain/{score_id}` substrate and what the Opus prep-sheet cites.

**Recompute triggers + versioning.** Triggers: `measurements.committed`, `device.synced`,
`facts.changed` (BMI/diabetes/sex/DOB → recompute NAFLD-FS/eGFR/PhenoAge/age-dependent FIB-4 cutoff),
`catalog.version_changed` (fan-out all users, batched low-priority), `consent.changed` (re-materialize
minus withdrawn scope). Three independent version axes stamped on every output: `formula_version`
(per score), `catalog_version` (optimal_bands + org map + dictionary), `result_version` (per-user
monotonic; prior versions reconstructable from append-only `audit_log`).

**Data model (additive).** `optimal_bands` (catalog: tiered, cited, sex/age-scoped optimal targets
like apoB<60), `parameter_stats` (per-user trend object), `scores` (per-user composite outputs +
`inputs_used` lineage), `analysis_results` (denormalized JSON read model: overview/systems/
parameters/bioage/scores/disclaimers).

**Phased build.** P1 normalization service + optimal_bands seed + trend engine + organ rollup +
**eGFR/FIB-4/PhenoAge/TyG/NLR-AAR-PLR** + `/v1/*` + `/explain` → P2 NAFLD-FS + HOMA-IR (need
onboarding facts) + richer trend + consent-withdrawal re-materialization → P3 cohort-fitting (KDM +
Homeostatic Dysregulation on NHANES then **recalibrated on Indian population**, partial Allostatic
Load, optional SCORE2/ASCVD behind not-calibrated-India caveat) → P4 aspirational (proteomic clocks
if Olink/SomaScan ever ingested).

---

## 8. Component — Span-consultant (realtime voice)

**Purpose.** A spoken interface over the user's already-extracted data (grounded read-aloud Q&A)
and a structured onboarding interviewer (captures the missing model inputs — BMI, smoking, BP,
diabetes/IFG — that unlock SCORE2/NAFLD-FS). Educational-only: speaks **only** retrieved
`value + unit + ref_low + ref_high + flag + date + lab`, never computes a diagnosis, never doses.

**Decision: MODULAR pipeline (LiveKit Agents, self-hosted) over an integrated realtime API.** The
integrated APIs (gpt-realtime / Gemini Live) win only on latency (~300–500 ms vs ~0.9–1.5 s); they
lose on every axis that matters here:

| Dimension | Integrated realtime API | **Modular (LiveKit) — chosen** |
|---|---|---|
| PHI residency | audio+transcript leave to one vendor's US/global region → **fails India DPDP / inference_geo pin** | every hop independently region-pinned + BAA/DPA |
| LLM swap / safety | LLM fused to audio model, can't substitute region-legal/medical LLM | LLM is one swappable step (India→Gemini asia-south1; EU→Vertex/Claude-Bedrock) |
| Inter-step guardrails | no insertion point between hearing and speaking | guardrails sit **between** steps — refuse an ungrounded number before it's spoken |
| Auditability | opaque | each hop logs; transcripts + cited sources persisted |

**Audio/data path & triple guardrail gate.** The number a user hears is gated three times — **intent**
(is this a safe ask? emergency/symptomatic → hard-escalate *before* the LLM, speak fixed safety
script, end turn), **grounding** (RAG fetch from Postgres; does a persisted source exist?), **output**
(Llama Guard / Guardrails byte-traces every spoken number to `grounded_sources`; refuse + log if
untraceable; enforce "discuss with your clinician" closing). **No single model both decides and speaks.**

```
iOS (AVAudioSession .voiceChat → HW AEC; PTT default; WebRTC Opus; live captions)
  → POST /v1/voice/sessions (server mints EPHEMERAL LiveKit token, TTL ≤60s — key NEVER on device)
  → LiveKit SFU + Agents (self-host, BAA infra, in-region):
       Silero VAD + SmolLM-v2 turn-end (barge-in) → STT → INTENT ROUTER (emergency hard-escalate)
       → RAG GATE (measurements + analysis_results, RLS) → LLM (refuses ungrounded numbers)
       → OUTPUT GUARDRAIL (trace every number; no dx/dose) → TTS → playout
       side-effects: voice_sessions / transcripts / onboarding writes → Postgres; audit_log
```

**Vendor topology** (every box is a PHI processor needing a DPDP processor agreement + no-train):
- **India (the live stack):** **Sarvam AI** all-in-India STT/TTS/LLM (22 langs, Indian medical terms,
  VPC/on-prem, no cross-border) — the single-vendor India voice stack. **Claude excluded** (Bedrock-India
  = global cross-region). LLM can also be Gemini on Vertex asia-south1 if Sarvam's reasoning is insufficient.
- **On-device privacy tier:** Apple SpeechAnalyzer (iOS 26) / whisper.cpp + AVSpeechSynthesizer —
  **zero egress.**
- **EU (future, if ever):** Deepgram/AssemblyAI (Dublin) STT + Vertex europe-west3 / Claude-on-Bedrock
  eu-central-1 LLM + Cartesia Sonic-3 TTS — documented so a later EU box reuses the same pipeline shape;
  **not built while India-only.**

**iOS audio (locked).** `.playAndRecord` + `.voiceChat` mode → HW AEC/NS/AGC for clean barge-in;
**push-to-talk default**, open-mic opt-in; observe `interruptionNotification` + `routeChangeNotification`
and **re-install the input tap** (works around the installTap-drops-after-call bug); end with
`route_lost` if route drops mid-turn. Live caption view = accessibility + the text-chat fallback surface.

**Onboarding write-back.** The LLM never writes profile fields directly — it emits a
`write_onboarding_field(field, value, unit, confidence, evidence_turn)` tool call; the **server
validates against plausibility bounds, reads the value back verbally for confirmation, then persists**
with `field_sources` provenance + audit. Once `bmi` + `diabetes_status` exist, the analysis layer can
compute NAFLD-FS; `smoking_status` + `sbp` + `bp_treated` + `diabetes_status` unlock the SCORE2/ASCVD
educational estimate (with the not-calibrated-for-India caveat).

**EU AI Act = treat as HIGH-RISK** regardless of the educational label: spoken + visual AI disclosure
gated in the session API (403 without ack), documented intended-use/limitations, **standalone DPDP
consent before any voice session.**

**Latency budget** (cloud tier, first-audio ≤ ~1.3 s): turn-end ~150–250 ms · STT ~150–300 ms ·
router+RAG ~100–200 ms · LLM first token ~300–500 ms · guardrail ~50–120 ms · TTS TTFA ~40–150 ms ·
WebRTC ~40–100 ms. Mitigations: stream every stage, prefetch `GROUNDED_CONTEXT` at session start,
in-region SFU, speculative filler ("let me check that…"). **Cost ~$0.08–0.18/min** self-hosted;
**text-chat fallback** (same router+RAG+guardrail, no STT/TTS) is the cheapest + accessibility +
no-mic-permission backstop.

**Data model.** `voice_sessions` (region, inference_geo, privacy_tier, consent_id, ai_disclosure_ack,
escalation_flag, model_versions, audio_retained=false by default), `transcripts` (turn-level,
append-only, `grounded_sources` = proof every spoken number traces to a source row),
`onboarding_profile` (versioned, consented, sourced, confidence-scored fields).

**Phased build.** P0 legal gates (DPA/BAA + no-train signed with every processor; AI-Act disclosure
scripts; standalone DPDP voice consent scope; tables + RLS) → P1 **text-chat fallback first**
(proves the grounding+guardrail spine before audio) → P2 voice EU stack → P3 voice India stack
(Sarvam, Hindi-English code-switch) → P4 structured onboarding conversation → P5 on-device privacy
tier + open-mic opt-in + audio-retention opt-in (default off).

---

## 9. Component — Platform, data & compliance foundation

**Purpose.** The load-bearing layer beneath all others: one India runtime, one physical data model,
one compliance machine. **India-only** at launch — a single stack in ap-south-1; the region machinery
is kept so a future EU stack is additive, but it is not built. **No PHI leaves India.**

**Architecture.** Launch = **one EC2 in ap-south-1** running the **TypeScript/Node `/v1` API +
worker** (behind CloudFront + WAF + ACM for TLS), owning all PHI. The box holds: **plain PostgreSQL**
(RLS on `user_id`) + **S3** (SSE-KMS, region CMK) + **SQS FIFO** (ingest→parse→analyze, DLQ per stage,
pay-per-use) → in-region inference (Vertex asia-south1 Gemini + Document AI; **Claude excluded from
India PHI**) + voice (Sarvam / LiveKit self-host). Boundary rules enforced **in code, not convention:**
- **Region assertion** — every PHI row is `region='in'`; the app asserts `region == 'in'` on read/write
  (the same check generalizes to multi-region if an EU box is ever added). A future EU deployment would
  add a `apple_sub → region` directory (DynamoDB, PHI-free); at launch, with one region, everyone is
  `in` and no directory lookup is needed.
- **No global database.** The only global state is that PHI-free directory + non-PHI catalogs
  (`canonical_parameters`, `policy_versions`, `vendor_register`), replicated per region.
- **Inference pin is independent of storage pin, validated at call time;** a CI lint forbids
  constructing an unpinned Vertex/Bedrock client (no "default" global endpoint anywhere).

**Consolidated schema.** One Postgres schema (the same DDL would deploy to a future EU box unchanged).
Every PHI table carries `user_id` + `region` (always `'in'` at launch) and is protected by RLS
`USING (user_id = current_setting('app.current_user_id'))`.
Tables (who writes → who reads): `users`/`profiles` (edge → workers+edge), `consents` + `policy_versions`
(edge → consent-gate middleware), `ingestion_artifacts`/`ingestion_jobs`/`reports`/`measurements`
(edge+workers → workers+edge), `canonical_parameters`/`parameter_catalog` (ops → workers; version bump
→ recompute), `analysis_results`/`scores` (analyze workers → edge), `qol_entries` (edge → edge),
`healthkit_samples` + `healthkit_anchors` (edge → analyze workers), `voice_sessions`/`transcripts`
(voice orchestrator → edge), `prep_reports` (prep workers → edge), `outbox` (system, ids only, no PHI),
`audit_log` (**append-only**, `REVOKE UPDATE/DELETE`, no PHI values), `vendor_register` (gate: a vendor
is invokable only if an active register row permits it for the region). App role is **subject to RLS**
(no BYPASSRLS); workers set `app.current_user_id` from the job payload.

**Auth (Sign in with Apple).** `POST /v1/auth/apple` verifies the Apple JWT against Apple's JWKS
(`iss`/`aud`/`exp`/`nonce`), extracts the stable `sub`, resolves/creates the `apple_sub → region`
directory entry (region from device locale/storefront + IP geo at signup, then **immutable**), creates
`users`/`profiles`. Returns **our own** access token (~15 min, KMS-signed) + rotating refresh token
(theft detection → revoke family on reuse). Apple's token is consumed once for bootstrap; the
`authorization_code` is exchanged to detect Apple account revocation + power SiwA-driven deletion.

**HealthKit ingestion** into the same data plane as a **"device" lab source**: `HKAnchoredObjectQuery`
with persisted `HKQueryAnchor` (`healthkit_anchors`) for incremental backfill; `HKObserverQuery` +
`enableBackgroundDelivery` as **best-effort** (unreliable on watchOS 26) + a **foreground catch-up sync**
on launch. Reads steps, `.sleepAnalysis`, `heartRateVariabilitySDNN`, `restingHeartRate`, `vo2Max`,
workouts, respiratoryRate, SpO2. **Cannot detect denied READ → tolerate empty results;** never claim a
sensor-based vital-sign diagnosis (App Store 1.4.1). Device data feeds trends only (no clinical score
consumes it).

**GDPR + DPDP as real mechanisms.**
- **One export pipeline** (`POST /v1/account/export`): single machine-readable archive (JSON + original
  PDFs) of all `user_id` rows **in-region only**, via short-lived presigned S3 URL → satisfies GDPR
  Art. 20 + DPDP access. Audited `phi.export`.
- **One delete pipeline** (`DELETE /v1/account`): satisfies GDPR Art. 17 + DPDP withdrawal +
  **App Store 5.1.1(v)**. `status='deletion_pending'` → cascade-delete PHI rows → delete region S3
  objects → Apple token revoke → tombstone directory entry → `status='deleted'`. Append-only PHI-free
  `audit_log` retained as proof; idempotent, resumable (SQS-driven, DLQ).
- **Consent** (`consents` + `policy_versions`): versioned, withdrawable, with `evidence_blob`
  (ip/ua/screen/copy_hash). Withdrawal flips the gate immediately and may trigger scoped deletion
  (withdraw voice → delete transcripts).
- **Encryption:** S3 SSE-KMS with region CMK (key policy denies cross-region grants), TLS 1.3 in
  transit. **Audit:** append-only, hashed IP (never raw), ids/counts only (no PHI values), periodic
  hash-chain export to WORM S3. **Vendor register** as the BAA/DPA source of truth.

**Tech choices.** **Plain PostgreSQL** (self-managed on the EC2, or one small RDS-Postgres — not
Aurora) + RLS; **TypeScript/Node `/v1` API + worker on one EC2** (ap-south-1) — long-lived process,
warm DB pool, long-lived Vertex/Sarvam clients; **SQS FIFO + transactional outbox** (pay-per-use,
kept); **S3 SSE-KMS** region CMK; **Secrets Manager + KMS**; DynamoDB reserved for a future
`apple_sub → region` directory (not needed while India-only). Cost discipline: drop always-on managed
billing (Aurora, Fargate); keep serverless pay-per-use (SQS/S3/KMS/DynamoDB/Lambda).

**Phased build.** P0 foundations (one India EC2: Node API+worker, plain Postgres + RLS + audit grants,
S3/SQS/KMS, SiwA auth + session/refresh, consent-gate middleware + `region='in'` assertion, the one
export/delete pipeline, PHI-free observability) → P1 ingestion→analysis (presign/commit, outbox→SQS,
parse+analyze workers, `/v1/*`,
recompute fan-out) → P2 device + QoL + bio-age depth → P3 voice + prep-sheet → P4 de-identified
research path (k-anonymized export enabling Claude EU/US aggregate analysis).

---

## 10. Consolidated roadmap (dependency-ordered)

The components share one data plane and one async spine, so build order is driven by dependencies,
not by component. Each milestone is shippable and has acceptance criteria.

### M0 — Foundation spine (India, one EC2)
**Deliverables.** One EC2 in ap-south-1 running the **TypeScript/Node `/v1` API + worker**; **plain
PostgreSQL** + RLS; pay-per-use **S3 SSE-KMS / SQS FIFO + DLQ / KMS / Secrets Manager**; the
consolidated Postgres schema + RLS policies + append-only audit grants; **Sign in with Apple** + our
own access/refresh tokens; consent-gate middleware + `region='in'` assertion; `policy_versions` /
`consents` / `vendor_register`; the **one export/delete pipeline** (DPDP + App Store 5.1.1; GDPR-ready
for a future EU box); PHI-free observability.
**Acceptance.** A user can sign in with Apple, grant/withdraw consent, export and delete their account;
every PHI row is `region='in'` and a non-`in` row is rejected; no Vertex/Bedrock client can be
constructed unpinned-to-asia-south1 (CI lint passes); audit_log is append-only by grant.

### M1 — Ingestion + parsing (the core loop, India)
**Deliverables.** Bulk folder upload + VisionKit photo capture → presigned PUT → S3 ap-south-1;
ingestion FSM + outbox → SQS; Document AI + Gemini (asia-south1) extraction with the transcribe-only tool schema;
the canonical dictionary + unit_rules seeded from the 159 existing params (with the golden test that
re-derives `health_data.json`); deterministic normalization (units, LOINC, ref ranges, outlier guards);
self-consistency N=3 + confidence-tiered HITL review; idempotent upsert into `measurements`.
**Acceptance.** A photographed Tata 1mg report becomes correctly-normalized, LOINC-coded, deduplicated
measurements; the T3/B12/Lp(a) unit traps are caught by guard windows; low-confidence rows route to
review, never auto-commit; re-uploading the same file creates no duplicate measurements.

### M2 — Analysis (trends + scores + organ systems)
**Deliverables.** Shared normalization service + tiered `optimal_bands` catalog; Theil–Sen trend engine
+ zone timelines; organ-system bucketing + 3-level rollup; the confirmed scores **PhenoAge, CKD-EPI
2021 eGFR, FIB-4 (with age>65 cutoff), TyG, NLR/AAR/PLR**; `analysis_results` materialization;
recompute fan-out; `/internal/v1/explain` provenance.
**Acceptance.** Golden-vector unit tests pass for every formula (PhenoAge reproduces published
reference values; CKD-EPI uses 2021 exponents); a high FIB-4 with normal LFTs still flags
`liver = attention`; every score row carries `inputs_used` + tier + caveats; a missing PhenoAge input
yields `computable=false` (no imputation), not a wrong number.

### M3 — Presentation (the premium SwiftUI experience)
**Deliverables.** SwiftUI TabView + NavigationStack; Parameter Detail with Swift Charts (clinical +
optimal bands, flag-colored points, null annotations, CSV export); whole-person overview (8 system
tiles + attention rail, **no score headline**); two-range optimal bands + tiered citation chips +
natural-frequency "how unusual" card; PROMIS Global-10 two-band header.
**Acceptance.** Searching a parameter charts its full history with reference + optimal bands and
correct flag colors; the home screen leads with system tiles, not a number; every optimal band shows
its tier + a tap-through citation; risk is shown as natural frequencies, never bare %.

### M4 — QoL check-in + HealthKit
**Deliverables.** HealthKit ingestion (`HKAnchoredObjectQuery` + anchors + foreground catch-up) as a
device lab source; WHO-5 daily check-in (raw×4 → 0–100, soft ≤50 nudge) + PROMIS Fatigue/Sleep
rotation; gentle, explicitly non-causal QoL↔HealthKit co-occurrence card.
**Acceptance.** Steps/sleep/HRV/VO2max flow into the same pipeline and appear as trends; WHO-5
produces a well-being trend (not a verdict); the soft nudge never names a condition; co-occurrence
copy is non-causal; empty HealthKit results never break the UI. **(WHO-5 commercial licensing cleared
before ship — see §12.)**

### M5 — Doctor-visit prep sheet (Opus)
**Deliverables.** Server-side Opus job on the `PrepReport` JSON contract; full post-gen guardrail stack
(schema, citation-from-allowed-sources-only, no-dose, banned-phrase, disclaimer-appended-in-code, one
auto-retry then human-review); native SwiftUI rendering modeled on `Doctor_Visit_Prep.docx`; AHRQ-style
QPL grouped by system + coaching note; PDF/share export. EU/de-identified path only for Claude.
**Acceptance.** A generated prep sheet cites a source on every row, contains zero doses, frames
contested items with contested language, includes the coaching note, and any guardrail failure blocks
publish (goes to review). Output is structured JSON rendered natively, not free HTML.

### M6 — Span-consultant (voice)
**Deliverables.** P0 legal gates (DPA/BAA + no-train with every processor; AI-Act disclosure scripts;
standalone DPDP voice consent) → text-chat fallback (proves grounding+guardrails) → voice EU stack
(LiveKit + Deepgram + Cartesia) → voice India stack (Sarvam) → structured onboarding conversation
(captures BMI/smoking/BP/diabetes → unlocks NAFLD-FS + SCORE2 estimate).
**Acceptance.** The bot speaks only numbers traceable to `grounded_sources`; an emergency/symptomatic
query hard-escalates before the LLM; AI disclosure + standalone consent gate every session (403
without); India sessions never touch a cross-region endpoint; onboarding writes are plausibility-checked
+ verbally confirmed before commit.

### M7 — Depth & expansion
Cohort-fitted KDM + Homeostatic Dysregulation (recalibrated on Indian population); partial Allostatic
Load; optional SCORE2/ASCVD (behind not-calibrated-India caveat); PhenoAge opt-in bio-age screen +
PAM-style activation tiering; Gmail OAuth ingestion (gated on Google CASA); on-device voice privacy
tier; de-identified research path.

---

## 11. Decisions still needed from the founder

**All 12 founder decisions RESOLVED (2026-06-14).** Recorded here so the plan is self-contained.

1. **Region / residency** → **India-only.** Every user `region='in'`; no EU stack, no relocation flow,
   no `apple_sub→region` directory at launch. Region columns stay in the schema purely so a future EU
   box is additive. Live compliance driver = **DPDP** (Indian PHI stays in ap-south-1), not GDPR.
2. **Gmail / CASA** → **deferred entirely.** Ship folder upload + photo capture only; no CASA cost/lead
   time. Add Gmail later if users want it.
3. **Review queue** → **user self-confirms in-app.** Low-confidence extractions are confirmed by the
   user ("we read this as HbA1c 6.7 — correct?"); guardrail-failed prep sheets regenerate or are
   withheld. No ops/clinical staff at MVP.
4. **Optimal bands** → **ship a conservative, well-cited seed table** (apoB, HbA1c, ALT, uric acid,
   omega-3, vitamin D), each labeled "expert opinion — discuss with clinician" + citation. Bring in a
   clinical reviewer **before expanding** the table.
5. **Trend baseline** → **first in-range reading.** "Trending away from your healthy baseline";
   robust to a bad first test.
6. **Lp(a) / creatinine** → **never auto-convert, split by specimen.** Lp(a) mg/dL and nmol/L are two
   separate tracked parameters (non-linear, contested); creatinine split serum vs urine (LOINC) so
   eGFR/kidney trends stay clean. Re-split the existing single-'Creatinine' rows on migration.
7. **Population norms** → **use NHANES now, caption the caveat.** PhenoAge + percentiles ship on NHANES
   norms with a visible "based on US reference data, may not be calibrated for Indian populations"
   caption; recalibrate on Span's own Indian user data once enough accrues.
8. **Instruments** → **WHO-5 + PROMIS Global-10 only.** Clear WHO-5's CC-BY-NC-SA commercial terms;
   PROMIS is public-domain. **Exclude** EQ-5D (~€7k) and ESS (licensed); use a home-grown "PAM-style"
   activation model, not licensed PAM-13. (Decide daily-shortened vs weekly-validated WHO-5 recall at
   build time — lean weekly to keep validation.)
9. **Voice audio** → **transcript-only, no raw audio retained.** Keep the text transcript (grounding
   proof + history); discard raw audio after each turn. Minimizes breach surface + erasure burden.
10. **India voice LLM** → **Sarvam for everything** (STT + TTS + LLM, one all-in-India vendor, one DPDP
    agreement). Keep the LLM step swappable to Gemini (Vertex asia-south1) if reasoning falls short.
    (EU voice vendors are future-only.)
11. **Profile capture** → **structured at onboarding.** Collect chronic conditions + current
    meds/supplements (names/classes only, no dosing) **and** the model inputs BMI/diabetes/smoking/BP
    (unlocks NAFLD-FS + the CV-risk estimate). Stored as PHI under consent; powers the prep sheet
    ("B12 already high — don't add more").
12. **React PWA** → **keep as an internal/dev tool only.** Not shipped to users; a quick web view for
    eyeballing data during development. iOS is the only user-facing client. No extra compliance surface.

**Net effect on scope:** the MVP gets simpler and cheaper — no Gmail/CASA, no review staff, no EU
stack, no licensed instruments, one voice vendor, PWA not a product surface. The only remaining
external dependency to line up early is **clearing WHO-5 commercial-use terms** (decision 8) and a
**clinical reviewer before the optimal-band table expands** (decision 4) — neither blocks M0–M2.

---

## 12. Risk & compliance register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | **Unit-conversion order-of-magnitude error** (T3 100×, B12 1000×, PhenoAge CRP/creatinine/glucose/albumin) | **Critical** | LLM never converts units; deterministic `unit_rules` with post-conversion guard windows → out-of-window forces review; canonical units enforced at the measurement layer; `scores.inputs_used` persists exact converted values; golden-vector CI tests per formula |
| 2 | **Cross-region PHI / wrong inference endpoint** (esp. Claude-on-Bedrock-India = global) | **Critical** | `region` on every row + stack-local assertion; CI lint forbids unpinned Vertex/Bedrock clients; `vendor_register` gate; Claude-India exclusion as hard config; per-call inference_geo pin |
| 3 | **Voice speaks an ungrounded number** (hallucinated lab value) | **Critical** | Triple gate (RAG-only context, tools return null not guesses, output guardrail byte-traces every number to `grounded_sources`); refuse + log if untraceable |
| 4 | **Emergency/symptomatic turn answered as Q&A** | **High** | Intent router hard-escalates *before* the LLM; fixed safety script; `flag_symptom`; end turn; never advise |
| 5 | **False precision / over-flagging** (composite scores, derived ratios as "abnormal") | **High** | No numeric organ score (3-level status + count basis); PhenoAge opt-in/secondary/never headline; ratios are trend-only soft flags; natural-frequency framing |
| 6 | **Opus prep-sheet hallucinates** a citation/dose/diagnosis | **High** | Cite-from-allowed-sources-only; post-gen schema + no-dose + banned-phrase guards; disclaimer in code; auto-retry then human review |
| 7 | **EU AI Act high-risk non-compliance** (voice) | **High** | Spoken+visual AI disclosure gated (403 without ack); documented intended-use/limitations; standalone DPDP consent pre-session; append-only audit |
| 8 | **App Store rejection** (SiwA 4.8, sensor vital-sign claims 1.4.1, PHI in iCloud 5.1.3, in-app deletion 5.1.1(v)) | **High** | SiwA mandatory; "see your doctor" copy, no sensor-diagnosis claims; PHI never in CloudKit; single in-app delete pipeline |
| 9 | **DPDP future data-localization** notification for health data | **Medium** | India already fully pinned to ap-south-1 + Vertex asia-south1; MinIO + self-hosted OCR/VLM fallback designed in for full in-country/air-gap |
| 10 | **Gmail CASA recurring cost / lapse** | **Medium** | Defer Gmail; feature-flag; calendar re-assessment; minimize scope (server-side sender+PDF filter) |
| 11 | **Indian-population miscalibration** (PhenoAge/SCORE2/KDM trained on Western cohorts) | **Medium** | Explicit `not_calibrated_india` caveats; KDM/HD deferred to Indian-cohort fitting; SCORE2 educational-estimate framing |
| 12 | **Instrument licensing** (WHO-5 CC-BY-NC-SA, ESS/EQ-5D/PAM proprietary) | **Medium** | Spine = WHO-5 (clear commercial terms) + PROMIS (public domain); PAM-style not PAM-13; ESS/EQ-5D excluded v1 |
| 13 | **HealthKit unreliability** (watchOS 26 background delivery; can't detect denied READ) | **Medium** | Best-effort background + foreground catch-up via anchors; tolerate empty results; never block UI |
| 14 | **Near-duplicate re-ingestion** bypasses hash dedup | **Low** | Soft-dedup signal (lab+date+param-set) → merge suggestion in review, never auto-merge |
| 15 | **Audit-log tampering** | **Low** | `REVOKE UPDATE/DELETE`; no app role with mutate rights; periodic hash-chain export to WORM S3 |

---

## 13. Appendix — research provenance

This plan was produced by a multi-agent pass; the raw research, fact-check verdicts, and the six
per-component designs are saved under `.span-research/` in this repo:
- `recovered.json` — 6 research sweeps + 33 fact-check verdicts (full text)
- `design-ingestion-layer.md`, `design-pre-analytics---parsing-layer.md`, `design-presentation-layer-…md`
- `design2-analysis-scoring.md`, `design2-span-consultant.md`, `design2-platform-compliance.md`

Every medical formula and claim in §2 carries its fact-check status. Where the fact-check found a
citation error or licensing constraint (PhenoAge author byline, FIB-4 age>65 cutoff, WHO-5/EQ-5D/ESS/PAM
licensing, the proteomic-clock magnitude figures), the correction is reflected inline above.
