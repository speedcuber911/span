-- =============================================================================
-- Project Span — Migration 0001: Full schema initialisation
-- Plain PostgreSQL (not Aurora); India-only at launch (region='in').
-- Every PHI row carries user_id + region.  RLS policies are in 0002_rls.sql.
-- Run as a superuser / migration role that bypasses RLS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";          -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";         -- uuid_generate_v4() fallback

-- ---------------------------------------------------------------------------
-- Utility: immutable region check (in is the only live region at launch; eu
-- column values are kept in DDL so a future EU box is additive, not a migration)
-- ---------------------------------------------------------------------------

-- =============================================================================
-- 1. IDENTITY, LAWFUL BASIS, AUDIT
-- =============================================================================

-- users -----------------------------------------------------------------------
CREATE TABLE users (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_sub       text        NOT NULL UNIQUE,
    email_private   bool        NOT NULL DEFAULT true,
    -- immutable residency pin — 'in' for all launch users; 'eu' reserved for future
    region          text        NOT NULL DEFAULT 'in'
                                CHECK (region IN ('in', 'eu')),
    storage_geo     text        NOT NULL DEFAULT 'ap-south-1',
    inference_geo   text        NOT NULL DEFAULT 'asia-south1',
    sex             text        CHECK (sex IN ('male', 'female', 'other', 'undisclosed')),
    dob             date,
    status          text        NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'deletion_pending', 'deleted')),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_apple_sub ON users (apple_sub);
CREATE INDEX idx_users_region    ON users (region);

-- profiles (canonical; onboarding fields folded in — see decision note below) -
-- DECISION: The plan mentions both `profiles` and `onboarding_profile` (voice §8).
-- We implement ONE canonical `profiles` table and fold all onboarding fields in.
-- The voice layer writes to this table via the server-validated write-back path.
-- `onboarding_profile` from voice §8 is NOT a separate table; the versioning /
-- confidence / field_sources for voice-captured fields live in `profiles_history`
-- (append-only audit trail of profile field changes) written alongside audit_log.
CREATE TABLE profiles (
    user_id             uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),

    -- biometrics (onboarding)
    height_cm           numeric(5,1),
    weight_kg           numeric(5,1),
    bmi                 numeric(5,2),

    -- clinical model inputs (unlock NAFLD-FS, SCORE2/ASCVD, FIB-4 age cutoff, PhenoAge)
    smoking_status      text        CHECK (smoking_status IN ('never', 'former', 'current')),
    bp_systolic         int,
    bp_diastolic        int,
    bp_treated          bool,
    diabetes_status     text        CHECK (diabetes_status IN ('none', 'ifg', 'type2', 'type1', 'gestational')),
    chronic_conditions  text[]      NOT NULL DEFAULT '{}',
    current_supplements text[]      NOT NULL DEFAULT '{}',   -- names/classes only, no doses

    -- voice onboarding provenance (folded from onboarding_profile)
    onboarding_complete bool        NOT NULL DEFAULT false,
    onboarding_source   text        CHECK (onboarding_source IN ('structured_form', 'voice', 'hybrid')),
    field_sources       jsonb,      -- { field_name: { source:'voice', confidence:0.9, turn_id:uuid } }
    field_confidence    jsonb,      -- { field_name: float 0–1 }

    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- policy_versions -------------------------------------------------------------
CREATE TABLE policy_versions (
    version         text        PRIMARY KEY,   -- e.g. '2026-06-01'
    kind            text        NOT NULL CHECK (kind IN ('privacy', 'terms', 'voice_consent')),
    effective_at    timestamptz NOT NULL,
    copy_hash       text        NOT NULL,      -- SHA-256 of the rendered policy text
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- consents --------------------------------------------------------------------
CREATE TABLE consents (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    scope           text        NOT NULL
                                CHECK (scope IN ('ingestion', 'gmail_readonly', 'processing',
                                                 'storage', 'voice', 'research_deidentified')),
    purpose         text        NOT NULL,
    policy_version  text        NOT NULL REFERENCES policy_versions (version),
    granted         bool        NOT NULL,
    method          text        NOT NULL CHECK (method IN ('tap', 'voice_confirmed', 'api')),
    granted_at      timestamptz NOT NULL DEFAULT now(),
    withdrawn_at    timestamptz,
    ip_at_grant     inet,
    evidence_blob   jsonb       -- {ua, screen_copy_hash, nonce}
);

CREATE INDEX idx_consents_user_scope ON consents (user_id, scope, granted);

-- audit_log (append-only; REVOKE UPDATE/DELETE granted in 0002_rls.sql) -------
-- Contains NO PHI values — only ids, counts, action codes, region.
CREATE TABLE audit_log (
    id          bigserial   PRIMARY KEY,
    user_id     uuid,                           -- nullable for system actions
    actor       text        NOT NULL,           -- 'user', 'worker', 'system', 'ops'
    action      text        NOT NULL,           -- 'phi.export', 'phi.delete', 'consent.granted', etc.
    entity      text,                           -- table name
    entity_id   uuid,
    region      text        NOT NULL DEFAULT 'in',
    at          timestamptz NOT NULL DEFAULT now(),
    meta        jsonb                           -- counts/keys only, never PHI values
);

CREATE INDEX idx_audit_log_user_at ON audit_log (user_id, at DESC);
CREATE INDEX idx_audit_log_action  ON audit_log (action, at DESC);

-- =============================================================================
-- 2. INGESTION
-- =============================================================================

-- ingestion_artifacts ---------------------------------------------------------
CREATE TABLE ingestion_artifacts (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    source              text        NOT NULL CHECK (source IN ('folder', 'photo', 'gmail')),
    original_filename   text,
    mime_type           text,
    byte_size           bigint,
    content_sha256      char(64)    NOT NULL,
    storage_bucket      text,
    storage_key         text,
    kms_key_id          text,
    page_count          int,
    gmail_msg_id        text,
    gmail_attachment_id text,
    sender_domain       text,
    av_scan             text        NOT NULL DEFAULT 'pending'
                                    CHECK (av_scan IN ('pending', 'clean', 'infected', 'error')),
    captured_at         timestamptz,
    uploaded_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, content_sha256)   -- exact-dedup
);

CREATE INDEX idx_artifacts_user    ON ingestion_artifacts (user_id, uploaded_at DESC);
CREATE INDEX idx_artifacts_sha256  ON ingestion_artifacts (content_sha256);

-- ingestion_jobs (FSM) --------------------------------------------------------
CREATE TABLE ingestion_jobs (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    artifact_id         uuid        NOT NULL UNIQUE REFERENCES ingestion_artifacts (id) ON DELETE CASCADE,
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    status              text        NOT NULL DEFAULT 'intent_created'
                                    CHECK (status IN (
                                        'intent_created', 'uploading', 'uploaded', 'enqueued',
                                        'parsing', 'needs_review', 'extracted', 'committed',
                                        'failed', 'duplicate', 'quarantined'
                                    )),
    idempotency_key     text        NOT NULL,
    attempt             int         NOT NULL DEFAULT 0,
    error_code          text,
    progress_pct        int         CHECK (progress_pct BETWEEN 0 AND 100),
    sqs_message_id      text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, idempotency_key)
);

CREATE INDEX idx_jobs_user_status ON ingestion_jobs (user_id, status);
CREATE INDEX idx_jobs_status      ON ingestion_jobs (status, updated_at);

-- outbox (transactional relay to SQS; minimal footprint — ids only, no PHI) ---
CREATE TABLE outbox (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id      uuid        NOT NULL REFERENCES ingestion_jobs (id) ON DELETE CASCADE,
    topic       text        NOT NULL,   -- 'ingestion.parse.requested', 'ingestion.parse.completed'
    payload     jsonb       NOT NULL,   -- job_id, artifact_id, user_id, region, inference_geo, storage refs
    published   bool        NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz
);

CREATE INDEX idx_outbox_unpublished ON outbox (published, created_at) WHERE NOT published;

-- gmail_sync_state ------------------------------------------------------------
CREATE TABLE gmail_sync_state (
    user_id             uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    history_id          text,
    last_synced_at      timestamptz,
    allowed_senders     text[]      NOT NULL DEFAULT '{}'
);

-- review_tasks (human-in-the-loop; §3 / §5) -----------------------------------
CREATE TABLE review_tasks (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    ingestion_job_id    uuid        REFERENCES ingestion_jobs (id) ON DELETE SET NULL,
    measurement_draft   jsonb       NOT NULL,
    reason              text        NOT NULL
                                    CHECK (reason IN ('low_conf', 'outlier', 'unmapped_param', 'unit_ambiguous')),
    assigned_to         text,       -- 'user' (self-review) or ops email
    decision            text        CHECK (decision IN ('accept', 'correct', 'reject')),
    corrected           jsonb,      -- corrected measurement fields
    resolved_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_review_tasks_user ON review_tasks (user_id, resolved_at NULLS FIRST);

-- =============================================================================
-- 3. CANONICAL DICTIONARY  (drives parsing/normalisation; mostly non-PHI)
-- =============================================================================

-- canonical_parameters --------------------------------------------------------
-- The shared reference dictionary.  Not PHI; not RLS-protected.
-- specimen column splits creatinine (serum vs urine) and other specimen-specific params.
CREATE TABLE canonical_parameters (
    canonical_param_id      text        PRIMARY KEY,   -- e.g. 'hba1c', 'creatinine_serum'
    display_name            text        NOT NULL,
    loinc_code              text,
    loinc_status            text        NOT NULL DEFAULT 'unmapped'
                                        CHECK (loinc_status IN ('mapped', 'candidate', 'unmapped')),
    category                text        NOT NULL,      -- matches categories in SCHEMA.md
    specimen                text,                      -- 'serum','plasma','whole_blood','urine','rbc',null
    canonical_unit          text        NOT NULL,
    plausibility_low        numeric,
    plausibility_high       numeric,
    default_ref_low         numeric,
    default_ref_high        numeric,
    aliases                 text[]      NOT NULL DEFAULT '{}',
    alias_regexes           text[]      NOT NULL DEFAULT '{}',
    optimal_band            jsonb,      -- {low, high, direction, evidence_tier, source_id}
    is_ratio                bool        NOT NULL DEFAULT false,
    is_derived              bool        NOT NULL DEFAULT false,  -- computed by analysis layer
    polarity                text        CHECK (polarity IN ('higher_better', 'lower_better', 'range_optimal')),
    hallmark_tags           text[]      NOT NULL DEFAULT '{}',  -- Hallmarks of Aging ontology
    horseman_tags           text[]      NOT NULL DEFAULT '{}',  -- Four Horsemen: ascvd,cancer,neuro,metabolic
    organ_system            text,       -- metabolic|cardiovascular|liver|kidney|inflammation_immune|hematologic|endocrine_thyroid|micronutrient_bone
    version                 int         NOT NULL DEFAULT 1,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_canon_param_category ON canonical_parameters (category);
CREATE INDEX idx_canon_param_loinc    ON canonical_parameters (loinc_code) WHERE loinc_code IS NOT NULL;
CREATE INDEX idx_canon_param_aliases  ON canonical_parameters USING GIN (aliases);

-- unit_rules ------------------------------------------------------------------
CREATE TABLE unit_rules (
    canonical_param_id      text        NOT NULL REFERENCES canonical_parameters (canonical_param_id),
    raw_unit_normalized     text        NOT NULL,      -- lowercase-trimmed raw unit string
    conversion_kind         text        NOT NULL
                                        CHECK (conversion_kind IN (
                                            'identity', 'alias', 'linear', 'scale', 'nonlinear_blocked'
                                        )),
    factor                  numeric,    -- for linear/scale: canonical = raw * factor + offset
    offset                  numeric     DEFAULT 0,
    guard_min               numeric,    -- post-conversion sanity clamp (plausibility_low override)
    guard_max               numeric,
    note                    text,
    PRIMARY KEY (canonical_param_id, raw_unit_normalized)
);

-- optimal_bands (tiered, cited, global catalog; not per-user) -----------------
-- Kept separate from canonical_parameters so a parameter can have multiple
-- evidence-tiered bands (e.g. different sex/age strata) and citations can be
-- updated without touching the core dictionary.
CREATE TABLE optimal_bands (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_param_id  text        NOT NULL REFERENCES canonical_parameters (canonical_param_id),
    label               text        NOT NULL,           -- e.g. 'optimal_attia', 'optimal_clinical'
    low                 numeric,
    high                numeric,
    direction           text        CHECK (direction IN ('lower_better', 'higher_better', 'range')),
    sex_scope           text        CHECK (sex_scope IN ('all', 'male', 'female')),
    age_min             numeric,
    age_max             numeric,
    evidence_tier       int         NOT NULL CHECK (evidence_tier BETWEEN 1 AND 3),
    -- tier 1 = consensus/safe; 2 = promising-incomplete; 3 = expert opinion/contested
    citation            jsonb,      -- {label, url, pmid, source_id}
    disclaimer_key      text        NOT NULL,           -- maps to i18n disclaimer copy
    active              bool        NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_optimal_bands_param ON optimal_bands (canonical_param_id, active);

-- =============================================================================
-- 4. REPORTS + MEASUREMENTS (PHI — RLS protected)
-- =============================================================================

-- reports ---------------------------------------------------------------------
CREATE TABLE reports (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region      text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    artifact_id uuid        REFERENCES ingestion_artifacts (id) ON DELETE SET NULL,
    lab         text,
    report_date date,
    s3_key      text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_reports_user      ON reports (user_id, report_date DESC);
CREATE INDEX idx_reports_artifact  ON reports (artifact_id);

-- measurements ----------------------------------------------------------------
CREATE TABLE measurements (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    report_id           uuid        NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    date                date        NOT NULL,
    parameter           text        NOT NULL,           -- canonical name (drive search)
    parameter_raw       text,                           -- as printed in the report
    category            text,
    canonical_param_id  text        REFERENCES canonical_parameters (canonical_param_id),
    loinc_code          text,
    value               numeric,
    value_text          text,       -- verbatim printed value; holds 'Negative','<200','>24' etc.
    value_operator      text        CHECK (value_operator IN ('=', '<', '>', '<=', '>=')),
    unit                text,       -- normalised unit
    unit_raw            text,       -- as printed
    ref_low             numeric,
    ref_high            numeric,
    ref_text            text,
    ref_qualifier       jsonb,      -- {sex:'male', age_gt:51}
    flag                text        CHECK (flag IN ('High', 'Low', 'Normal')),
    lab                 text,
    sources             text[]      NOT NULL DEFAULT '{}',
    field_confidence    jsonb,
    extraction_status   text        NOT NULL DEFAULT 'auto_accepted'
                                    CHECK (extraction_status IN ('auto_accepted', 'human_reviewed', 'human_corrected')),
    bbox                jsonb,      -- {page, x, y, w, h} from Document AI
    created_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, report_id, parameter, date)   -- idempotent upsert key
);

CREATE INDEX idx_measurements_user_param ON measurements (user_id, parameter, date DESC);
CREATE INDEX idx_measurements_user_canon ON measurements (user_id, canonical_param_id, date DESC);
CREATE INDEX idx_measurements_report     ON measurements (report_id);
CREATE INDEX idx_measurements_loinc      ON measurements (loinc_code) WHERE loinc_code IS NOT NULL;

-- parameter_catalog (per-user materialised view; rebuilt by analysis worker) --
CREATE TABLE parameter_catalog (
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    parameter       text        NOT NULL,
    canonical_param_id text     REFERENCES canonical_parameters (canonical_param_id),
    category        text,
    unit            text,
    count           int         NOT NULL DEFAULT 0,
    numeric_count   int         NOT NULL DEFAULT 0,
    first_date      date,
    last_date       date,
    latest_value    numeric,
    latest_value_text text,
    ref_low         numeric,
    ref_high        numeric,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, parameter)
);

CREATE INDEX idx_param_catalog_user ON parameter_catalog (user_id, numeric_count DESC);

-- =============================================================================
-- 5. COMPUTED ANALYSIS (consumed read-only by Presentation + Voice)
-- =============================================================================

-- parameter_stats (per-user trend objects, keyed by formula+catalog version) --
CREATE TABLE parameter_stats (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    canonical_param_id  text        NOT NULL REFERENCES canonical_parameters (canonical_param_id),
    result_version      int         NOT NULL,
    catalog_version     int         NOT NULL,
    n_points            int,
    first_date          date,
    last_date           date,
    slope_theilsen      numeric,    -- Theil–Sen estimator
    slope_ci_low        numeric,
    slope_ci_high       numeric,
    trend_direction     text        CHECK (trend_direction IN ('improving', 'worsening', 'stable', 'insufficient_data')),
    trend_confidence    text        CHECK (trend_confidence IN ('high', 'moderate', 'low', 'insufficient_data')),
    pct_in_range        numeric,
    zone_timeline       jsonb,      -- [{date, zone: 'red'|'yellow'|'green'}]
    baseline_value      numeric,    -- first-in-range reading (decision §11 #5)
    baseline_date       date,
    computed_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, canonical_param_id, result_version)
);

CREATE INDEX idx_param_stats_user ON parameter_stats (user_id, canonical_param_id);

-- scores (PhenoAge / eGFR / FIB-4 / TyG / NFS / ratios, versioned) -----------
CREATE TABLE scores (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    score_key       text        NOT NULL,  -- 'phenoage', 'ckd_epi_egfr', 'fib4', 'tyg', 'nafld_nfs',
                                           -- 'homa_ir', 'nlr', 'aar', 'plr', 'score2', 'ascvd'
    value           numeric,
    unit            text,
    computable      bool        NOT NULL DEFAULT false,
    missing_inputs  text[]      NOT NULL DEFAULT '{}',
    formula_version text        NOT NULL,
    catalog_version int         NOT NULL,
    result_version  int         NOT NULL,
    inputs_used     jsonb       NOT NULL DEFAULT '{}',  -- {measurement_id, raw_value, canonical_value, unit_xform}
    evidence_tier   int         NOT NULL CHECK (evidence_tier BETWEEN 1 AND 3),
    caveats         text[]      NOT NULL DEFAULT '{}',  -- 'not_calibrated_india', 'trained_nhanes3', etc.
    disclaimer_key  text,
    band            text        CHECK (band IN ('optimal', 'normal', 'attention')),
    computed_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, score_key, result_version)
);

CREATE INDEX idx_scores_user_key ON scores (user_id, score_key, computed_at DESC);

-- analysis_results (denormalised JSON read model per user; consumed by /v1/*) -
CREATE TABLE analysis_results (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    result_key      text        NOT NULL,  -- 'overview', 'systems', 'parameters', 'bioage'
    result_version  int         NOT NULL,
    catalog_version int         NOT NULL,
    payload         jsonb       NOT NULL,
    computed_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, result_key, result_version)
);

CREATE INDEX idx_analysis_results_user ON analysis_results (user_id, result_key, computed_at DESC);

-- =============================================================================
-- 6. QoL (WHO-5 + PROMIS check-ins)
-- =============================================================================

CREATE TABLE qol_entries (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    instrument      text        NOT NULL
                                CHECK (instrument IN ('who5', 'promis_global10',
                                                      'promis_fatigue4a', 'promis_sleep4a')),
    responses       jsonb       NOT NULL,  -- {q1:4, q2:3, ...}
    raw_score       numeric,
    scaled_score    numeric,               -- 0–100 for WHO-5; T-score for PROMIS
    band            text,                  -- 'optimal'|'monitor'|'attention' for WHO-5
    recorded_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_qol_user ON qol_entries (user_id, instrument, recorded_at DESC);

-- =============================================================================
-- 7. HEALTHKIT
-- =============================================================================

CREATE TABLE healthkit_samples (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    hk_type         text        NOT NULL,  -- 'steps', 'sleep_analysis', 'hrv_sdnn', 'resting_hr',
                                           -- 'vo2max', 'workout', 'respiratory_rate', 'spo2'
    value           numeric,
    unit            text,
    start_at        timestamptz NOT NULL,
    end_at          timestamptz,
    source_device   text,
    hk_uuid         text,       -- HKObject.uuid (dedup)
    metadata        jsonb,
    synced_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, hk_uuid)   -- prevents re-sync duplicates
);

CREATE INDEX idx_hk_samples_user ON healthkit_samples (user_id, hk_type, start_at DESC);

CREATE TABLE healthkit_anchors (
    user_id         uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    region          text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    -- JSON-encoded HKQueryAnchor per type key (incremental backfill)
    anchors         jsonb       NOT NULL DEFAULT '{}',
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 8. VOICE SESSIONS + TRANSCRIPTS
-- =============================================================================

CREATE TABLE voice_sessions (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    inference_geo       text        NOT NULL DEFAULT 'asia-south1',
    privacy_tier        text        NOT NULL DEFAULT 'cloud'
                                    CHECK (privacy_tier IN ('on_device', 'cloud')),
    consent_id          uuid        NOT NULL REFERENCES consents (id),
    ai_disclosure_ack   bool        NOT NULL DEFAULT false,
    escalation_flag     bool        NOT NULL DEFAULT false,  -- true if emergency/symptomatic
    model_versions      jsonb,      -- {stt:'sarvam-1', llm:'sarvam-m', tts:'sarvam-tts-1'}
    audio_retained      bool        NOT NULL DEFAULT false,  -- default off (§11 decision 9)
    started_at          timestamptz NOT NULL DEFAULT now(),
    ended_at            timestamptz,
    turn_count          int         NOT NULL DEFAULT 0
);

CREATE INDEX idx_voice_sessions_user ON voice_sessions (user_id, started_at DESC);

CREATE TABLE transcripts (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          uuid        NOT NULL REFERENCES voice_sessions (id) ON DELETE CASCADE,
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    turn_index          int         NOT NULL,
    role                text        NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    text                text        NOT NULL,
    grounded_sources    jsonb,      -- [{measurement_id, parameter, value, date}] — proof of grounding
    intent_class        text,       -- 'lab_query', 'onboarding', 'general', 'emergency'
    guardrail_passed    bool,
    created_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, turn_index)
);

CREATE INDEX idx_transcripts_session ON transcripts (session_id, turn_index);
CREATE INDEX idx_transcripts_user    ON transcripts (user_id, created_at DESC);

-- =============================================================================
-- 9. PREP REPORTS (Opus doctor-visit prep sheet)
-- =============================================================================

CREATE TABLE prep_reports (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    region              text        NOT NULL DEFAULT 'in' CHECK (region IN ('in', 'eu')),
    status              text        NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'generating', 'review', 'published', 'failed')),
    payload             jsonb,      -- PrepReport JSON (schema-validated)
    model_version       text,
    catalog_version     int,
    guardrail_log       jsonb,      -- log of post-gen guard results
    generated_at        timestamptz,
    published_at        timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_prep_reports_user ON prep_reports (user_id, created_at DESC);

-- =============================================================================
-- 10. PLATFORM / COMPLIANCE / GLOBAL (non-PHI)
-- =============================================================================

-- vendor_register (gate: a vendor is invokable only if active for the region) -
CREATE TABLE vendor_register (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_key      text        NOT NULL,   -- 'vertex_gemini', 'vertex_docai', 'sarvam', 'livekit'
    region          text        NOT NULL    CHECK (region IN ('in', 'eu')),
    endpoint        text,
    geo_constraint  text,       -- e.g. 'asia-south1', 'europe-west3'
    dpa_signed      bool        NOT NULL DEFAULT false,
    baa_signed      bool        NOT NULL DEFAULT false,
    no_train_agreed bool        NOT NULL DEFAULT false,
    active          bool        NOT NULL DEFAULT false,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (vendor_key, region)
);

-- sources / citations (non-PHI, global; drives the cite+defer backbone) -------
CREATE TABLE sources (
    id                  text        PRIMARY KEY,  -- e.g. 'levine_2018_phenoage', 'attia_apob_60'
    tier                int         NOT NULL CHECK (tier BETWEEN 1 AND 3),
    kind                text        NOT NULL
                                    CHECK (kind IN ('guideline', 'peer_reviewed', 'expert_opinion', 'contested')),
    title               text        NOT NULL,
    citation_text       text,
    url                 text,
    pmid                text,
    claim_supported     text,
    conflict_disclosure text,
    created_at          timestamptz NOT NULL DEFAULT now()
);
