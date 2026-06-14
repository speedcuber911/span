# Pre-Analytics / Parsing Layer (Span Ingestion-to-Standardized-Measurement pipeline)

## Overview
This layer turns any lab artifact (PDF, photo, handwritten note, Gmail attachment) from any lab (Indian Tata 1mg/Healthians/Thyrocare/Redcliffe/Metropolis-class, or international) into rows that match Span's existing standardized Measurement schema (date, parameter canonical + raw, category, value, value_text, unit, ref_low/high/text, flag, lab, sources). It is grounded in the real pepe-health/health_data.json (1,536 rows, 159 params, 21 distinct labs observed). The current dataset already encodes the hard problems by hand; this design FORMALIZES those hand rules into a deterministic, multi-region, privacy-by-design pipeline. The four hardest formalizations, all directly observed in the data: (1) Unit chaos within one canonical parameter — T3 appears as ng/mL vs ng/dL vs nmol/L (a 100x order-of-magnitude trap), Vitamin B12 as pg/mL vs ng/mL (1000x), Lipoprotein(a) as mg/dL vs nmol/L (non-linear, contested), ESR in 7 spellings, eGFR in 4. (2) Parameter canonicalization — up to 16 raw spellings collapse to one canonical (HbA1c), and a LOINC subtlety: 'Creatinine' currently conflates serum AND urine specimens, which LOINC would (correctly) split. (3) Reference-range parsing — ranges arrive as '3.5 - 5.0', '3.5-5.2', '[8.00-23.00]', 'Male > 51 Years: 56 - 119', '<200 IU/ml', 'Negative < 25, Positive > 25', and 251/1536 rows have only one bound, 202 have none. (4) Non-numeric / censored values — 'Negative', 'Trace', '> 24', '<200', '77.33' (a real misparsed outlier already dropped to value:null but kept searchable via value_text). The pipeline is: on-device VisionKit capture / folder / Gmail fetch -> presigned PUT to region-locked encrypted S3 -> Document AI OCR + Form/Layout parse -> Gemini multimodal structured extraction against a strict tool-schema -> deterministic unit-normalization + reference-range parsing + LOINC canonicalization + category bucketing + outlier guards -> per-field confidence via self-consistency multi-run agreement -> confidence-tiered human-in-the-loop -> write to Postgres (FHIR-Observation-aligned) + raw original in S3. Residency is enforced as two independent controls (inference geo + storage geo), locked per user-region: India users -> Vertex AI Gemini + Document AI in asia-south1 (Mumbai), S3 ap-south-1; EU users -> Vertex europe-west3 or Claude-on-Bedrock eu-central-1, S3 eu-central-1. Claude's first-party API is excluded from any India PHI path (US-only inference); a self-hosted PaddleOCR/Surya + local-VLM fallback is designed in from day one for air-gap/on-prem.

## Architecture
DATA FLOW (per ingested document):

[iOS SwiftUI client]
  | VisionKit VNDocumentCameraViewController (on-device de-skew/enhance/crop) OR
  | folder multi-file picker OR Gmail fetch (later phase)
  v
[App API: POST /v1/ingestions]  -> creates Ingestion row (status=UPLOADING), returns presigned PUT URL(s)
  | client uploads bytes DIRECTLY to bucket (bytes never transit app server)
  v
[Region-locked S3]  raw/{region}/{user_id}/{ingestion_id}/{sha256}.{ext}
  bucket per region: span-raw-ap-south-1 (Mumbai) | span-raw-eu-central-1 (Frankfurt)
  SSE-KMS (CMEK), Object Lock (compliance retention), versioning, lifecycle to Glacier, presigned-only access
  | S3 ObjectCreated event -> SQS (region-local) -> Worker pool (region-pinned, no cross-region)
  v
[STAGE 1 — OCR / Layout]  Google Document AI (regional endpoint, same region as user)
  - OCR processor (pretrained-ocr-v2.1.1) for raw text + token bounding boxes + page images
  - Form Parser for key/value pairs + TABLE reconstruction (most lab panels are tables)
  - Layout Parser for multi-column / multi-panel reports
  output: ocr_json {pages[], blocks[], tables[], tokens[] with bbox + per-token OCR confidence}
  written to S3 derived/{...}/ocr.json (region-local)
  | (fallback path, feature-flagged per deployment: PaddleOCR PP-StructureV3 / Surya + DocLayout-YOLO + Table Transformer on own GPU)
  v
[STAGE 2 — Multimodal structured extraction]  Gemini on Vertex AI (REGIONAL endpoint asia-south1 / europe-west3)
  input: page images (for handwriting/stamps/logos) + Document AI tables/text (grounding) + strict tool-schema
  the model is FORCED to emit a tool call `emit_lab_report` (function-calling / responseSchema) — never free text
  output: ExtractedReport {lab, report_date, patient_hints, rows[]} where each row carries RAW fields + per-field confidence
  RUN N=3 times (self-consistency) at temperature 0.0-0.4 with fixed seed variation; agreement -> confidence
  v
[STAGE 3 — Deterministic post-processing] (pure code, no LLM, fully testable, region-agnostic logic)
  3a parameter canonicalization: raw name -> canonical_param_id + loinc_code via Canonical Parameter Dictionary
       (alias exact-match -> normalized fuzzy -> ML mapper -> UNMAPPED tail to review queue)
  3b unit normalization: (canonical_param, raw_unit, raw_value) -> (canonical_unit, value) via Unit Rule Table
       handles spelling collapse (mEq/L==mmol/L for monovalent), scale fixes (lakhs/thousands->10^3/uL),
       and TRUE conversions (T3 ng/dL->ng/mL /100; B12 ng/mL->pg/mL x1000)  [hard-guarded, see risks]
  3c reference-range parsing: ref_text -> ref_low/ref_high (+ sex/age qualifier capture), bound-aware
  3d category bucketing: canonical_param -> category (deterministic from dictionary, LLM never picks category)
  3e flag derivation: from value vs ref bounds if lab didn't print one; else trust lab flag
  3f outlier guards: physiologic plausibility window per canonical_param -> implausible => value:null, keep value_text, raise review
  3g dedup: (user, date, canonical_param, value, canonical_unit) collapse; union sources[]
  v
[STAGE 4 — Confidence routing]  field_confidence = f(ocr_conf, self_consistency_agreement, deterministic_validators)
  HIGH (>=0.90 all core fields)   -> AUTO-ACCEPT  -> status=ACCEPTED
  MID  (0.60-0.90 / 1 weak field) -> REVIEW QUEUE -> human confirm/correct
  LOW  (<0.60 / failed validators)-> FLAG/REJECT  -> human required, never auto-written to trend
  v
[STAGE 5 — Persistence]  Postgres (region-local instance: Cloud SQL/RDS ap-south-1 or eu-central-1)
  measurements table (FHIR Observation-aligned) + ingestions + review_tasks + canonical dictionary cache
  raw original + ocr.json + extraction.json retained in S3 (lineage), measurement.sources[] points back to filenames
  v
[Analysis & Presentation layers consume measurements] (out of scope here)

RESIDENCY ENFORCEMENT (two independent controls, locked per user.region at signup):
  inference_geo: where the model physically runs   -> { IN: Vertex asia-south1 ; EU: Vertex europe-west3 OR Bedrock eu-central-1 }
  storage_geo:   where bytes rest                   -> { IN: ap-south-1 ; EU: eu-central-1 }
  A router middleware selects the per-region endpoint+bucket+DB from user.region; cross-region calls are blocked at IAM/VPC-SC.
  Claude first-party API: NEVER on India PHI (US-only inference). Claude permitted only via Bedrock eu-central-1 for EU,
  or for de-identified / non-PHI 'thinking' tasks (doctor-prep) — out of this layer.

ASCII:
  iOS(VisionKit) --presigned PUT--> [S3 raw region-locked] --event--> SQS --> Worker
                                                                          |
                       +--------------------------+---------------------+
                       v                          v                     v
                 DocumentAI(OCR/Form)       Gemini x3 (Vertex)     (fallback: PaddleOCR+VLM)
                       |                          |
                       +-----------> Deterministic post-proc (canon/unit/ref/flag/outlier/dedup)
                                                  |
                                          Confidence router
                                       /          |           \
                                  AUTO-ACCEPT   REVIEW Q     FLAG/REJECT
                                       \          |           /
                                        v         v          v
                                   [Postgres measurements + S3 lineage]

## Data model
CANONICAL PARAMETER DICTIONARY (the heart of canonicalization) — one row per canonical test, versioned, seeded from the 159 existing params:
canonical_parameters {
  canonical_param_id   TEXT PK   -- stable slug, e.g. "hba1c", "creatinine_serum", "creatinine_urine", "t3_total"
  display_name         TEXT      -- "HbA1c"
  loinc_code           TEXT NULL -- "4548-4" (HbA1c); NULL allowed for the 6-19% unmappable tail
  loinc_status         ENUM(mapped, candidate, unmapped)
  category             TEXT      -- one of the 12 Span categories (deterministic owner of bucketing)
  specimen             ENUM(serum, plasma, whole_blood, urine, rbc, ...)  -- THIS is what splits Creatinine serum vs urine
  canonical_unit       TEXT      -- the single target scale, e.g. "%", "10^3/uL", "ng/mL"
  plausibility_low     NUMERIC NULL  -- outlier guard window (physiologic), e.g. creatinine 0.1..20 mg/dL
  plausibility_high    NUMERIC NULL
  default_ref_low      NUMERIC NULL  -- fallback range when report omits one
  default_ref_high     NUMERIC NULL
  aliases              TEXT[]    -- normalized raw spellings seen (16 for HbA1c, 13 TSH, 11 ESR...)
  alias_regexes        TEXT[]    -- compiled matchers for new spellings
  optimal_band         JSONB NULL -- e.g. Attia "optimal" overlay {low,high,source} kept SEPARATE from ref range
  is_ratio             BOOL      -- A/G, De Ritis etc. (unitless "Ratio")
  version              INT
}
unit_rules { -- drives Stage 3b; pure deterministic
  canonical_param_id   TEXT FK
  raw_unit_normalized  TEXT      -- after casefold + strip (µ->u, superscripts normalized)
  conversion_kind      ENUM(identity, alias, linear, scale, nonlinear_blocked)
  factor               NUMERIC NULL  -- value_canonical = value_raw * factor (+offset) for linear/scale
  offset               NUMERIC NULL
  guard_min, guard_max NUMERIC NULL  -- post-conversion sanity window; violation => flag for review
  note                 TEXT      -- e.g. "T3 ng/dL->ng/mL factor 0.01"; "B12 ng/mL->pg/mL factor 1000";
                                 --      "Lp(a) mg/dL<->nmol/L NONLINEAR -> do NOT auto-convert, keep both, flag"
  PRIMARY KEY (canonical_param_id, raw_unit_normalized)
}

MEASUREMENT (output; superset of existing schema + multi-user + FHIR/LOINC additions) — unchanged keys keep current names so the existing app/SCHEMA.md keeps working:
measurements {
  id              UUID PK
  user_id         UUID FK            -- NEW (multi-user)
  date            DATE               -- existing
  parameter       TEXT               -- existing CANONICAL display name ("HbA1c")
  parameter_raw   TEXT               -- existing, as printed
  canonical_param_id TEXT FK         -- NEW, joins dictionary
  loinc_code      TEXT NULL          -- NEW (FHIR Observation.code)
  category        TEXT               -- existing (one of 12)
  value           NUMERIC NULL       -- existing (null if non-numeric/censored/outlier)
  value_text      TEXT               -- existing (holds "Negative","> 24","<200","Trace", raw outlier)
  value_operator  ENUM(=,<,>,<=,>=) DEFAULT '='  -- NEW: captures censored "<200" / "> 24" without losing it
  unit            TEXT               -- existing, NORMALIZED canonical unit
  unit_raw        TEXT               -- NEW, exact printed unit (audit/repro)
  ref_low         NUMERIC NULL       -- existing
  ref_high        NUMERIC NULL       -- existing
  ref_text        TEXT               -- existing raw range string
  ref_qualifier   JSONB NULL         -- NEW: {sex:"male", age_gt:51} parsed from "Male > 51 Years: 56-119"
  flag            ENUM(High,Low,Normal) NULL  -- existing
  lab             TEXT NULL          -- existing (Healthians, Thyrocare, Tata 1mg, ...)
  sources         TEXT[]             -- existing (union after dedup; 94 rows already have >1)
  -- provenance / trust:
  ingestion_id    UUID FK
  field_confidence JSONB             -- {value:0.97, unit:0.93, ref:0.71, param_map:0.99}
  extraction_status ENUM(auto_accepted, human_reviewed, human_corrected)
  bbox            JSONB NULL         -- page+rect for the source cell (review UI highlight)
  created_at, updated_at
  UNIQUE (user_id, date, canonical_param_id, value, unit)  -- dedup key
}
ingestions { id, user_id, region, source_type(scan|folder|gmail), s3_raw_key, sha256, lab_detected,
             report_date, page_count, status(uploading|ocr|extracting|review|done|failed),
             ocr_s3_key, extraction_s3_key, model_versions JSONB, created_at }
review_tasks { id, ingestion_id, measurement_draft JSONB, reason(low_conf|outlier|unmapped_param|unit_ambiguous),
               assigned_to, decision(accept|correct|reject), corrected JSONB, resolved_at }

FHIR alignment: measurement maps to Observation{ code=loinc_code, valueQuantity={value,unit}, referenceRange=[{low,high}], interpretation=flag, effectiveDateTime=date, subject=user, identifier=id }.

## APIs / interfaces
LLM TOOL-SCHEMA CONTRACT (Gemini function-calling / Vertex responseSchema; the model MUST call this, no prose):
emit_lab_report(report: {
  lab_name: string|null,                 // printed lab/provider; null if not visible
  report_date: string|null,              // ISO YYYY-MM-DD; the collection/report date
  date_confidence: number,               // 0..1
  patient_name_hint: string|null,        // for matching only; de-identified before storage
  rows: array<{
    parameter_raw: string,               // EXACTLY as printed (do not normalize)
    value_text: string,                  // EXACTLY as printed incl "Negative","<200","> 24","Trace"
    value_numeric: number|null,          // parsed number if unambiguous, else null
    value_operator: "="|"<"|">"|"<="|">=", // captures censored results
    unit_raw: string|null,               // exactly as printed ("ng/ml","mEq/L","10^3/uL","mm/1st hr")
    ref_text: string|null,               // exact printed range
    ref_low: number|null, ref_high: number|null, // ONLY if cleanly printed; else null, leave to deterministic parser
    flag_printed: "High"|"Low"|"Normal"|null,    // only if the lab printed/marked it
    bbox: {page:int,x:number,y:number,w:number,h:number}|null, // for review highlight
    confidence: number                    // model's own 0..1 per row
  }>
})
PROMPT CONTRACT (system): "You are a clinical lab-report transcriber. Transcribe ONLY what is printed. Do NOT diagnose, do NOT canonicalize names, do NOT convert units, do NOT invent reference ranges. If a cell is illegible, set the field null and lower confidence. Preserve qualitative results verbatim. Call emit_lab_report exactly once." Grounding: Document AI tables/text passed as context; page images attached for handwriting/stamps. Determinism (canon/unit/ref/category/flag-fallback) is done OUTSIDE the model in code so it is testable and the model cannot hallucinate a unit conversion.
RETRIES & SELF-CONSISTENCY: run emit_lab_report N=3 (temp 0.0/0.2/0.4). Per-field agreement across runs => self_consistency in [0,1]. Disagreement on value/unit => field_confidence capped, row routed to REVIEW. Transient errors: exponential backoff (3 attempts, jitter), then dead-letter SQS -> ops alert. Hard JSON-schema validation on every run; schema-invalid output is discarded and retried, never persisted.

APP / SERVICE ENDPOINTS:
  POST /v1/ingestions {source_type, files[meta]} -> {ingestion_id, presigned_puts[], region}
  PUT  <presigned S3 url> (client->bucket direct)
  POST /v1/ingestions/{id}/finalize -> enqueues processing
  GET  /v1/ingestions/{id} -> {status, counts{accepted,review,rejected}}
  GET  /v1/review-tasks?status=open -> [task] ; POST /v1/review-tasks/{id} {decision, corrected}
  GET  /v1/measurements?user_id=&parameter= -> existing-shape rows (back-compatible with current app)
  Internal: DictionaryService.resolve(parameter_raw)->{canonical_param_id,loinc,category,confidence};
            UnitService.normalize(canonical_param_id,value,unit_raw)->{value,unit,flagged?}
WRITE-PATH to DB+S3: on AUTO-ACCEPT, deterministic post-proc result is upserted into measurements (dedup key), raw+ocr+extraction JSON already in region-local S3; measurement.sources[] = original filenames; on human correction the corrected row supersedes the draft and field_confidence/extraction_status updated.

## Tech choices
- Vertex AI Gemini (multimodal extraction), REGIONAL endpoint asia-south1 (Mumbai) for India, europe-west3 (Frankfurt) for EU — the only single-vendor stack that keeps BOTH OCR and LLM inference physically in-region; HIPAA/BAA-eligible, CMEK + VPC-SC, custom retention. Residency: true India + EU residency confirmed for regional (not global) endpoints.
- Google Document AI (OCR pretrained-ocr-v2.1.1 + Form Parser + Layout Parser), single-region asia-south1 / europe-west3 — best in-India lab-report table/KV extraction; CMEK, VPC-SC, Data Residency. Residency: single-region keeps OCR inside India (some healthcare processors need the Single Region Request Form).
- Claude (Opus 4.8 vision) via AWS Bedrock eu-central-1 (Frankfurt) ONLY for EU users with In-Region routing + Zero-Data-Retention, OR for de-identified non-PHI 'thinking' tasks. EXCLUDED from any India PHI path: Anthropic first-party API is US-only inference (inference_geo us/global) and Claude-in-India-on-Bedrock runs via GLOBAL cross-region inference, so it is NOT India-resident. Residency/compliance: Anthropic Art.28 DPA + SCCs on Bedrock EU.
- Region-locked S3 (ap-south-1 Mumbai / eu-central-1 Frankfurt) with SSE-KMS CMEK, Object Lock, versioning, presigned PUT (bytes never transit app server), lifecycle to Glacier. MinIO as the on-prem S3-compatible drop-in for air-gapped/INR-billed deployments. Residency: storage geo locked per user-region, independent of inference geo.
- Self-hosted fallback OCR+VLM stack designed in from day one: PaddleOCR PP-StructureV3 (or Surya + DocLayout-YOLO + Table Transformer) + a local VLM on own GPU — invoked when a BAA/region constraint tightens or for on-prem/air-gap. Residency/compliance: zero external model-vendor dependency, fully inside EU/India infra.
- LOINC as canonical parameter identifier (Observation.code), with parameter_raw + internal canonical_param_id fallback for the 6-19% unmappable tail; FHIR Observation alignment for interoperability. ML/rule auto-mapper (RF ~94.5% up to ensemble ~99%) with human review of the unmapped tail. Compliance: standards-based, audit-friendly.
- Postgres (Cloud SQL or RDS, region-local instance) for measurements/ingestions/review/dictionary; FHIR-Observation-aligned columns. Residency: DB instance pinned to user region.
- VisionKit VNDocumentCameraViewController on iOS for on-device de-skew/perspective-correct/enhance before upload — data minimization (less raw imagery leaves device), Notes-app quality, zero config.
- Gmail ingestion DEFERRED to a later phase: needs restricted gmail.readonly (metadata scope can't read attachments) -> mandatory Google CASA assessment (Tier 2/3, ~$15k-$75k, re-passed every 12 months, weeks lead time). Start with folder/photo upload; when added, server-side filter to known Indian lab senders + PDF MIME before download to minimize footprint.

## Risks
- UNIT-CONVERSION ORDER-OF-MAGNITUDE ERROR is the single highest-severity risk: real data shows T3 in ng/mL vs ng/dL (100x) and B12 in ng/mL vs pg/mL (1000x). A wrong factor silently corrupts a trend and could mislead a health decision. Mitigation: never let the LLM convert units; do it in the deterministic Unit Rule Table with post-conversion guard_min/guard_max sanity windows per canonical param; any conversion that lands outside the plausibility window is forced to REVIEW, never auto-accepted.
- Lipoprotein(a) mg/dL<->nmol/L is NON-LINEAR and clinically contested (no single valid factor). Auto-converting would fabricate data. Mitigation: mark conversion_kind=nonlinear_blocked; store both native units as separate canonical sub-parameters, never coerce to one scale, surface a caveat in the UI.
- Creatinine currently conflates serum and urine specimens under one canonical (and units mg/dL vs urine scales differ). LOINC correctly splits these; collapsing them pollutes eGFR/kidney trends. Mitigation: dictionary has specimen field and distinct canonical_param_ids (creatinine_serum vs creatinine_urine); migration must re-split the existing 'Creatinine' rows.
- Reference-range parsing is lossy: 251/1536 rows have only one bound, 202 none, and ranges carry sex/age conditionals ('Male > 51 Years: 56-119'). Picking the wrong conditional band flips a flag. Mitigation: parse qualifier into ref_qualifier JSONB, only apply a conditional band when user sex/age is known, else fall back to dictionary default and lower flag confidence.
- Multimodal-LLM hallucination on handwritten/low-quality Indian reports (open-source parsers ~75-83% on hard docs; even strong VLMs invent plausible numbers). Mitigation: self-consistency N=3 agreement, Document AI table grounding, transcribe-only prompt, confidence-tiered HITL — low-agreement rows never auto-written.
- Residency mis-route: accidentally calling Claude first-party API or a Vertex GLOBAL endpoint on Indian PHI breaks DPDP. Mitigation: region router + VPC-SC/IAM perimeter that blocks cross-region/global inference; CI test asserts India path resolves only to asia-south1 regional endpoints; Claude path IAM-denied for India tenants.
- Gmail CASA recurring cost + weeks of lead time and annual re-assessment can stall the roadmap and add $15k-$75k/yr. Mitigation: defer Gmail to a later phase, ship folder/photo first; when added, minimize scope footprint (sender+MIME server-side filter).
- PHI in OCR/extraction lineage JSON in S3 expands the breach surface. Mitigation: same region-lock + SSE-KMS + Object Lock + lifecycle expiry as raw; de-identify patient_name_hint before storage; short retention/ZDR on model side.
- Dictionary drift / new lab spellings (a 17th HbA1c spelling appears). Mitigation: unmapped/low-confidence param names auto-route to review queue, reviewer confirmation appends the alias and (optionally) trains the mapper — closed feedback loop, versioned dictionary.
- Censored values ('<200', '> 24') lost if coerced to a number. Mitigation: value_operator column + value_text verbatim; trends plot the bound but the operator is preserved for correctness.

## Phased build
- Phase 0 — Formalize the rules as data (no new ingestion yet): seed the Canonical Parameter Dictionary and Unit Rule Table from the existing 159 params / observed aliases; encode the unit conversions explicitly (T3, B12, ESR spellings, eGFR spellings, mEq/L==mmol/L for monovalent, lakhs/thousands->10^3/uL); split Creatinine serum/urine; assign LOINC where mappable, mark the unmappable tail. Ship a deterministic post-processor library + golden-test suite that re-derives the existing health_data.json from raw fields (regression harness). Shippable: a tested normalization/canonicalization service.
- Phase 1 — Folder/photo single-region MVP (India first): VisionKit capture + multi-file folder upload -> presigned PUT to ap-south-1 S3 -> Document AI OCR/Form -> Gemini emit_lab_report (single run) -> deterministic post-proc -> write measurements (existing app keeps working, now multi-user). Manual review of everything (HITL on by default). Shippable: end-to-end parse of new Indian lab PDFs into the standardized schema for one region.
- Phase 2 — Confidence + HITL automation: add self-consistency N=3, per-field confidence scoring, outlier guards with plausibility windows, and the confidence-tiered router (auto-accept HIGH, queue MID, flag LOW) + a reviewer UI with bbox highlight and one-click correct. Shippable: most reports auto-accept; only the genuinely ambiguous tail needs a human.
- Phase 3 — EU region + Claude-on-Bedrock-EU + residency hardening: stand up europe-west3 Vertex + eu-central-1 S3/DB, region router middleware, VPC-SC/IAM perimeter, CMEK, Object Lock; Claude via Bedrock eu-central-1 (ZDR) for EU-only or de-identified tasks. CI residency assertions. Shippable: GDPR-grade EU tenancy alongside DPDP-grade India tenancy.
- Phase 4 — Self-hosted fallback + handwriting robustness: integrate PaddleOCR PP-StructureV3 / Surya + local VLM behind a feature flag for air-gap/on-prem and as a degraded-mode backstop; tune for handwritten and noisy Indian reports; close the dictionary feedback loop (reviewer corrections append aliases / retrain mapper). Shippable: vendor-independent extraction path + improving accuracy over time.
- Phase 5 — Gmail OAuth ingestion: request gmail.readonly, budget+run Google CASA (Tier 2/3), server-side filter to known Indian lab senders + PDF MIME, reuse the entire downstream pipeline. Shippable: hands-free fetch of lab PDFs from email once the assessment clears.

## Open questions
- LOINC specimen granularity vs product simplicity: do we expose creatinine_serum and creatinine_urine as distinct trends to users, or keep one display name with an internal split? Affects the existing single-'Creatinine' UX.
- Lipoprotein(a) mg/dL vs nmol/L — confirm we never auto-convert and instead keep two native sub-parameters; need a clinician sign-off on the chosen display convention.
- Sex/age-conditional reference ranges require knowing user sex/DOB at parse time. Is that captured at onboarding (HealthKit / Sign in with Apple gives limited demographics), or must we prompt? Until known, do we suppress conditional flags?
- Which review-queue staffing model — in-house clinical reviewers vs trained ops vs the user self-confirming low-confidence rows in-app? This changes the HITL UI and the DPDP processor/role classification.
- Confidence thresholds (0.90 / 0.60) are placeholders; need to calibrate on a labeled set of real Indian + international reports (incl. handwritten) before locking auto-accept.
- Gemini vs a self-hosted VLM as the DEFAULT for India: do we lead with Vertex Gemini (fastest path, true asia-south1 residency, BAA) and keep self-host as fallback, or lead self-host for maximum residency control and INR billing? Affects Phase 1 vs Phase 4 ordering.
- Document AI healthcare/limited-access processors may require the Single Region Request Form with lead time — confirm which processors we need are approved for asia-south1 before committing Phase 1 timeline.
- Retention policy specifics: how long do we keep raw images + OCR/extraction lineage JSON (breach surface) vs the minimum needed for re-processing and audit, and does DPDP/GDPR data-minimization push us to expire raw originals after successful extraction?
- Patient identity matching across multi-lab reports for one user (patient_name_hint varies by lab) — do we rely on the authenticated user binding only, or also fuzzy-match printed names as a safety check against mis-filed uploads?
