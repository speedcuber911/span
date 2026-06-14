## Overview

This document is the **Platform, Data & Compliance Foundation** for the longevity/health iOS app. It is the load-bearing layer beneath the ingestion, pre-analytics, presentation, and voice designs. It does not re-litigate decisions already locked elsewhere; it **consolidates** them into one coherent runtime, one physical data model, and one compliance machine.

The product is an **educational** longevity companion. A user signs in with Apple, uploads lab reports (initially Indian Tata 1mg PDFs plus a long tail of other labs), grants HealthKit access, and receives a server-computed view of their health across 8 organ-system tiles, bio-age (PhenoAge flagship), risk indices (FIB-4, CKD-EPI, NAFLD-FS, TyG…), and an Opus-generated clinician prep-sheet — plus an optional realtime voice assistant that may only speak grounded, retrieved values. The app never diagnoses and never doses.

The foundation is governed by four non-negotiables:

1. **Two-region data residency, two independent pins.** Every user carries `storage_geo` and `inference_geo`. India principals: storage in `ap-south-1` (Mumbai), inference on Vertex AI `asia-south1` (Gemini + Document AI), the only single-vendor true-India stack. EU principals: storage in `eu-central-1` (Frankfurt), inference on Vertex `europe-west3` **or** Claude on Bedrock `eu-central-1` (in-region + ZDR). Claude on Bedrock in India is **global cross-region inference** and is therefore **excluded from the India PHI path**; Claude touches Indian data only after de-identification.
2. **GDPR + India DPDP as real mechanisms, not posture.** Versioned consent records with evidence blobs; one export/delete pipeline that simultaneously satisfies GDPR erasure/portability, DPDP withdrawable consent, and App Store 5.1.1(v) in-app deletion; append-only audit of every PHI read/export/delete; per-vendor DPA/BAA register; region-routing middleware that refuses cross-region PHI movement.
3. **Server computes all medical logic.** The SwiftUI client is thin: it renders `analysis_results`/`scores` from `/v1/overview`, `/v1/systems/{key}`, `/v1/parameters/{id}`, `/v1/bioage`. No formula runs on device.
4. **Async, idempotent, recompute-friendly ingestion.** `ingest → parse → analyze` via transactional outbox + SQS FIFO, with DLQs, idempotency keys, and a recompute fan-out so a dictionary or formula change re-derives results without re-uploading.

Everything below is opinionated and concrete. Where a design is already fixed upstream, this document **reuses** it and shows how it lands physically.

---

## Architecture

Two physically independent stacks, one per region, deployed from one codebase with region as a deploy-time + request-time dimension. **No PHI crosses the boundary.** A thin global edge (CloudFront + Route 53 latency/geo routing, Cognito-less Apple-token verification at the edge is avoided — see Auth) selects the regional stack; the regional stack owns all PHI.

```
                                  ┌───────────────────────────────────────────────┐
                                  │                 iOS APP (SwiftUI)             │
                                  │  SiwA · HealthKit (HKAnchoredObjectQuery)     │
                                  │  WebRTC voice (ephemeral token) · NavStack    │
                                  │  thin client: renders scores/results only     │
                                  └───────────────┬───────────────────────────────┘
                                                  │ HTTPS/TLS1.3, /v1 REST + WSS
                                                  │ region chosen from users.region
                                                  ▼
                         ┌─────────── GLOBAL EDGE (no PHI persisted) ───────────┐
                         │  Route 53 (latency/geo) · CloudFront · WAF · ACM     │
                         │  region-routing middleware → pins request to stack   │
                         └───────────┬───────────────────────────┬─────────────┘
                                     │                           │
        ╔════════════ EU BOUNDARY (eu-central-1, Frankfurt) ═══╗ ║ ╔═══════════ INDIA BOUNDARY (ap-south-1, Mumbai) ═══════════╗
        ║                                                      ║ ║ ║                                                          ║
        ║  ┌────────────────────────────────────────────┐     ║ ║ ║  ┌────────────────────────────────────────────┐          ║
        ║  │ FastAPI EDGE (ECS Fargate, /v1 versioned)   │     ║ ║ ║  │ FastAPI EDGE (ECS Fargate, /v1 versioned)   │          ║
        ║  │ authz · RLS session var · consent gate      │     ║ ║ ║  │ authz · RLS session var · consent gate      │          ║
        ║  └───┬───────────────┬──────────────┬──────────┘     ║ ║ ║  └───┬───────────────┬──────────────┬──────────┘          ║
        ║      │ outbox write  │ presign      │ audit          ║ ║ ║      │ outbox write  │ presign      │ audit             ║
        ║      ▼               ▼              ▼                 ║ ║ ║      ▼               ▼              ▼                    ║
        ║  ┌──────────────────────────────────────────────┐    ║ ║ ║  ┌──────────────────────────────────────────────┐       ║
        ║  │ Aurora PostgreSQL (EU)  RLS on user_id        │    ║ ║ ║  │ Aurora PostgreSQL (IN)  RLS on user_id        │       ║
        ║  │ users/profiles/consents/reports/measurements/ │    ║ ║ ║  │ users/profiles/consents/reports/measurements/ │       ║
        ║  │ analysis_results/scores/...outbox/audit_log   │    ║ ║ ║  │ analysis_results/scores/...outbox/audit_log   │       ║
        ║  └───┬───────────────────────────────────────────┘    ║ ║ ║  └───┬───────────────────────────────────────────┘       ║
        ║      │ outbox relay (poller)                          ║ ║ ║      │ outbox relay (poller)                            ║
        ║      ▼                                                ║ ║ ║      ▼                                                   ║
        ║  ┌──────────────────────────────┐   ┌─────────────┐  ║ ║ ║  ┌──────────────────────────────┐   ┌─────────────┐    ║
        ║  │ SQS FIFO: ingest→parse→analyze│   │ S3 (EU)     │  ║ ║ ║  │ SQS FIFO: ingest→parse→analyze│   │ S3 (IN)     │    ║
        ║  │ + DLQ per stage               │   │ SSE-KMS     │  ║ ║ ║  │ + DLQ per stage               │   │ SSE-KMS     │    ║
        ║  └───┬──────────────────────────┘   │ raw PDFs    │  ║ ║ ║  └───┬──────────────────────────┘   │ raw PDFs    │    ║
        ║      │                              └─────────────┘  ║ ║ ║      │                              └─────────────┘    ║
        ║      ▼ parse/analyze workers (Fargate)               ║ ║ ║      ▼ parse/analyze workers (Fargate)                  ║
        ║  ┌──────────────────────────────────────────────┐    ║ ║ ║  ┌──────────────────────────────────────────────┐       ║
        ║  │ INFERENCE (EU-resident, in-region):           │    ║ ║ ║  │ INFERENCE (India-resident, in-region):        │       ║
        ║  │  Vertex europe-west3 (Gemini + Document AI)   │    ║ ║ ║  │  Vertex asia-south1 (Gemini + Document AI)    │       ║
        ║  │  OR Claude on Bedrock eu-central-1 (ZDR)      │    ║ ║ ║  │  (Claude EXCLUDED: Bedrock-IN = global x-region)│     ║
        ║  └──────────────────────────────────────────────┘    ║ ║ ║  └──────────────────────────────────────────────┘       ║
        ║                                                      ║ ║ ║                                                          ║
        ║  VOICE (LiveKit Agents, self-host BAA EU):           ║ ║ ║  VOICE (LiveKit Agents, self-host BAA India):           ║
        ║   Deepgram Nova-3/AssemblyAI (Dublin) STT           ║ ║ ║   Sarvam AI all-in-India STT/TTS/LLM (22 langs)         ║
        ║   EU-region LLM · Cartesia Sonic-3 TTS              ║ ║ ║   VPC/on-prem                                            ║
        ╚══════════════════════════════════════════════════════╝ ║ ╚══════════════════════════════════════════════════════════╝
                                                                  ║
        On-device privacy tier (both regions): Apple SpeechAnalyzer (iOS26)/whisper.cpp + AVSpeechSynthesizer — zero egress.
        Cross-region de-identified path: ONLY a de-identified, k-anonymized export may use Claude (EU/US) for aggregate/research. Never raw PHI.
```

Key boundary rules enforced in code, not just convention:

- **Region-routing middleware** resolves the user's home region from the Apple `sub` lookup (a global, PHI-free directory keyed by `apple_sub → region`, see Auth) and **hard-fails** (`409 region_mismatch`) any request that arrives at the wrong regional stack rather than proxying it. Clients cache their region and target the correct host directly.
- **No global database.** The only global state is the PHI-free `apple_sub → region` directory (DynamoDB global table holding *only* the opaque Apple subject hash and region letter — no email, no name, no PHI).
- **Inference pin is independent of storage pin** and validated at call time: a worker in `ap-south-1` may only invoke `asia-south1` endpoints; the EU worker may invoke `europe-west3` or Bedrock `eu-central-1`. SDK clients are constructed per-region from config; there is no "default" global endpoint anywhere in the codebase (a CI lint forbids unpinned Vertex/Bedrock client construction).

---

## Data model

One consolidated PostgreSQL schema, **identical DDL in both regions**, deployed independently per region. The schema reuses the tables already fixed by the ingestion/pre-analytics/presentation designs and adds the foundation tables (`profiles`, `parameter_catalog`, `analysis_results`, `scores`, `qol_entries`, `healthkit_samples`, `voice_sessions`, `prep_reports`, `outbox`). Every PHI table carries `user_id` and is protected by **Row-Level Security** keyed on a per-request session variable `app.current_user_id`, set by the FastAPI edge after authz. `region` is denormalized onto user-scoped rows for defense-in-depth assertions (a row whose `region` ≠ the stack's region is a hard error).

### Conventions

- All PKs are `uuid` (`gen_random_uuid()`), except dictionary tables which use stable text/semantic ids.
- All PHI tables: `created_at timestamptz default now()`, `updated_at timestamptz`, and **RLS** `USING (user_id = current_setting('app.current_user_id')::uuid)`.
- `region` is `text check (region in ('in','eu'))` and is set from the connection's region, never from client input.
- Writers run as the application role (which is **subject to RLS** — no `BYPASSRLS`); the outbox relay and workers use a distinct role that sets `app.current_user_id` from the job payload before any row access. Only migration/break-glass roles bypass RLS, and their use is audited.

### Tables

```sql
-- ============ IDENTITY ============
CREATE TABLE users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_sub    text NOT NULL UNIQUE,              -- stable Apple subject; never email
  region       text NOT NULL CHECK (region IN ('in','eu')),
  storage_geo  text NOT NULL CHECK (storage_geo IN ('ap-south-1','eu-central-1')),
  inference_geo text NOT NULL CHECK (inference_geo IN ('asia-south1','europe-west3','eu-central-1')),
  status       text NOT NULL DEFAULT 'active' CHECK (status IN ('active','deletion_pending','deleted')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz
);
-- WRITES: edge (signup/region assign). READS: edge (every authz). RLS: self-row only via app.current_user_id.

CREATE TABLE profiles (
  user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  date_of_birth date,                              -- for age in PhenoAge/CKD-EPI/FIB-4
  sex_at_birth text CHECK (sex_at_birth IN ('F','M','unspecified')),
  height_cm    numeric,
  weight_kg    numeric,                            -- for BMI (NAFLD-FS); from onboarding/HealthKit
  diabetes_flag boolean,                           -- onboarding self-report for NAFLD-FS IFG/diabetes term
  smoking_status text, systolic_bp numeric, bp_treated boolean,  -- onboarding for SCORE2/ASCVD educational est.
  display_name text,
  updated_at   timestamptz NOT NULL DEFAULT now()
);
-- WRITES: edge (onboarding, HealthKit body metrics). READS: analyze workers (score inputs), edge (UI). RLS on user_id.

-- ============ CONSENT (DPDP + GDPR) ============
CREATE TABLE consents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  scope         text NOT NULL,        -- e.g. 'lab_ingest','healthkit','voice_session','de_identified_research'
  purpose       text NOT NULL,        -- DPDP specific-purpose string (versioned with policy)
  policy_version text NOT NULL,       -- FK-ish to policy_versions.version
  granted       boolean NOT NULL,
  granted_at    timestamptz,
  withdrawn_at  timestamptz,          -- DPDP withdrawable; presence => consent inactive
  evidence_blob jsonb NOT NULL,       -- {ip, ua, screen_id, copy_hash, locale, ts} proof of informed consent
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON consents (user_id, scope) WHERE withdrawn_at IS NULL;
-- WRITES: edge (consent screens, withdrawal). READS: edge consent-gate middleware before every PHI op. RLS on user_id.

CREATE TABLE policy_versions (              -- GLOBAL, non-PHI, replicated per region
  version       text PRIMARY KEY,           -- e.g. '2026-06-01'
  doc_kind      text NOT NULL,              -- 'privacy','dpdp_notice','voice_disclosure','terms'
  effective_at  timestamptz NOT NULL,
  body_hash     text NOT NULL,              -- sha256 of rendered policy text
  url           text NOT NULL
);
-- No RLS (no PHI). WRITES: ops/migration. READS: edge (to bind current consent copy).

-- ============ INGESTION (already fixed) ============
CREATE TABLE ingestion_artifacts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  s3_key       text NOT NULL,                  -- region S3, SSE-KMS
  sha256       text NOT NULL,                  -- content hash => upload idempotency
  mime_type    text, byte_size bigint, source text,  -- 'upload'|'share_extension'
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, sha256)
);
-- WRITES: edge (presign+commit). READS: parse workers. RLS on user_id.

CREATE TABLE ingestion_jobs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  artifact_id  uuid REFERENCES ingestion_artifacts(id) ON DELETE CASCADE,
  status       text NOT NULL CHECK (status IN              -- FSM
                ('queued','parsing','parsed','analyzing','done','failed','dead_letter')),
  stage        text NOT NULL DEFAULT 'parse' CHECK (stage IN ('parse','analyze')),
  attempts     int NOT NULL DEFAULT 0,
  idempotency_key text NOT NULL,                 -- dedupe across retries / outbox replays
  last_error   text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);
-- WRITES: workers (FSM transitions) + edge (enqueue). READS: edge (status polling), workers. RLS on user_id.

CREATE TABLE reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  artifact_id  uuid REFERENCES ingestion_artifacts(id) ON DELETE SET NULL,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  lab          text, report_date date, s3_key text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
-- WRITES: parse workers. READS: edge, analyze workers. RLS on user_id.

CREATE TABLE measurements (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id       uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  region          text NOT NULL CHECK (region IN ('in','eu')),
  date            date NOT NULL,
  parameter       text NOT NULL, parameter_raw text,
  category        text,
  canonical_param_id text REFERENCES canonical_parameters(canonical_param_id),
  loinc_code      text,
  value           numeric, value_text text, value_operator text,   -- '<','>','='
  unit            text, unit_raw text,
  ref_low numeric, ref_high numeric, ref_text text, ref_qualifier jsonb,
  flag            text,                          -- H/L/normal/critical
  lab             text,
  sources         text[],                        -- includes 'device' for HealthKit
  field_confidence jsonb, extraction_status text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, report_id, parameter, date)
);
CREATE INDEX ON measurements (user_id, canonical_param_id, date);
-- WRITES: parse workers, HealthKit ingester. READS: analyze workers, edge. RLS on user_id.

-- ============ DICTIONARIES (GLOBAL, non-PHI, replicated) ============
CREATE TABLE canonical_parameters (
  canonical_param_id text PRIMARY KEY,
  display_name text, loinc_code text, category text, specimen text,
  canonical_unit text, plausibility_low numeric, plausibility_high numeric,
  default_ref_low numeric, default_ref_high numeric,
  aliases text[], optimal_band jsonb, is_ratio boolean,
  catalog_version text NOT NULL                  -- bumping this drives recompute fan-out
);
CREATE TABLE parameter_catalog (                 -- versioned snapshot registry of the dictionary
  catalog_version text PRIMARY KEY,
  effective_at timestamptz NOT NULL, notes text, param_count int
);
-- No RLS. WRITES: ops/migration. READS: parse + analyze workers, edge. Version bump => recompute.

-- ============ DERIVED MEDICAL LOGIC (server-computed) ============
CREATE TABLE analysis_results (                  -- per-parameter zoning/flags for tiles & charts
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  measurement_id uuid REFERENCES measurements(id) ON DELETE CASCADE,
  canonical_param_id text REFERENCES canonical_parameters(canonical_param_id),
  system_key    text,                            -- one of the 8 organ-system tiles
  zone          text CHECK (zone IN ('red','yellow','green')),  -- three-zone traffic light
  zone_basis    text,                            -- 'clinical_range'|'optimal_band'
  evidence_tier text CHECK (evidence_tier IN ('t1','t2','t3')),
  message       text,                            -- educational copy; "discuss with your clinician"
  engine_version text NOT NULL, catalog_version text NOT NULL,
  computed_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON analysis_results (user_id, system_key, computed_at DESC);
-- WRITES: analyze workers. READS: edge (/v1/overview,/systems,/parameters). RLS on user_id.

CREATE TABLE scores (                            -- bio-age + risk indices
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  kind          text NOT NULL,    -- 'phenoage','ckd_epi_egfr','fib4','nafld_fs','tyg','homa_ir','nlr','aar','plr',...
  value         numeric, unit text,
  band          text,                            -- 'rule_out'|'indeterminate'|'advanced' etc.
  inputs        jsonb NOT NULL,                  -- exact unit-corrected inputs used (audit of unit bugs)
  caveats       text[],                          -- 'not_calibrated_india','trend_only','opt_in'
  evidence_tier text, is_headline boolean DEFAULT false,  -- PhenoAge never headline => false
  engine_version text NOT NULL, computed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind, computed_at)
);
-- WRITES: analyze workers. READS: edge (/v1/bioage,/overview). RLS on user_id.

-- ============ QUALITY OF LIFE / CHECK-INS ============
CREATE TABLE qol_entries (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  instrument   text NOT NULL CHECK (instrument IN ('promis_global10','who5')),
  entry_date   date NOT NULL,
  raw_responses jsonb NOT NULL,
  t_score_physical numeric, t_score_mental numeric,  -- PROMIS Global-10 two bands
  who5_index   numeric,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, instrument, entry_date)
);
-- WRITES: edge (check-in). READS: edge (header/overview). RLS on user_id.

-- ============ HEALTHKIT AS A "DEVICE" LAB SOURCE ============
CREATE TABLE healthkit_samples (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  hk_type       text NOT NULL,            -- 'HKQuantityTypeIdentifierVO2Max', '.sleepAnalysis', 'hrvSDNN', ...
  start_at      timestamptz NOT NULL, end_at timestamptz,
  value         numeric, unit text, value_text text,   -- categorical (sleep stages) -> value_text
  source_bundle text,                     -- originating app/device
  hk_uuid       text NOT NULL,            -- HealthKit sample UUID => dedupe
  ingested_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, hk_uuid)
);
CREATE INDEX ON healthkit_samples (user_id, hk_type, start_at);
-- WRITES: edge (HK sync endpoint). READS: analyze workers (HRV/RHR/VO2max trends), edge. RLS on user_id.

CREATE TABLE healthkit_anchors (          -- one per (user,hk_type): HKQueryAnchor persistence
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region       text NOT NULL CHECK (region IN ('in','eu')),
  hk_type      text NOT NULL,
  anchor_blob  bytea NOT NULL,            -- opaque NSKeyedArchiver HKQueryAnchor
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, hk_type)
);
-- WRITES+READS: edge (anchor round-trip). RLS on user_id. (See HealthKit ingestion below.)

-- ============ VOICE ============
CREATE TABLE voice_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  consent_id    uuid NOT NULL REFERENCES consents(id),   -- standalone voice consent required
  disclosure_policy_version text NOT NULL,                -- EU AI Act spoken+visual disclosure shown
  started_at    timestamptz NOT NULL DEFAULT now(), ended_at timestamptz,
  stt_vendor text, tts_vendor text, llm_vendor text,      -- region-correct vendors only
  turn_count int, escalation_triggered boolean DEFAULT false,  -- symptomatic/emergency router fired
  retrieved_measurement_ids uuid[],                       -- provenance of every spoken value
  transcript_s3_key text,                                 -- optional, SSE-KMS, retention-bound
  created_at    timestamptz NOT NULL DEFAULT now()
);
-- WRITES: voice orchestrator (LiveKit agent backend). READS: edge (history), audit. RLS on user_id.

-- ============ PREP SHEET (Opus, EU/de-identified only for that path) ============
CREATE TABLE prep_reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  prep_json     jsonb NOT NULL,           -- PrepReport JSON contract
  guardrail_status text NOT NULL,         -- 'passed'|'blocked' post-gen guardrails
  model_vendor  text NOT NULL,            -- region-correct; India => Gemini asia-south1, never Claude-on-Bedrock-IN
  engine_version text NOT NULL,
  generated_at  timestamptz NOT NULL DEFAULT now()
);
-- WRITES: analyze/prep workers. READS: edge. RLS on user_id.

-- ============ OUTBOX + AUDIT ============
CREATE TABLE outbox (                     -- transactional outbox; relayed to SQS FIFO
  id            bigserial PRIMARY KEY,
  user_id       uuid NOT NULL,
  region        text NOT NULL CHECK (region IN ('in','eu')),
  topic         text NOT NULL,            -- 'parse.requested','analyze.requested','recompute.requested'
  payload       jsonb NOT NULL,           -- ids only; NO PHI values
  dedup_id      text NOT NULL,            -- SQS FIFO MessageDeduplicationId
  group_id      text NOT NULL,            -- SQS FIFO MessageGroupId (= user_id => per-user ordering)
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')),
  created_at    timestamptz NOT NULL DEFAULT now(), sent_at timestamptz
);
CREATE INDEX ON outbox (status, id) WHERE status = 'pending';
-- WRITES: edge + workers (same txn as state change). READS+UPDATES: outbox relay. (No RLS: system table, ids only.)

CREATE TABLE audit_log (                  -- APPEND-ONLY; every PHI access/export/delete
  id            bigserial PRIMARY KEY,
  user_id       uuid,                     -- subject
  actor         text NOT NULL,            -- 'user:<id>'|'worker:parse'|'ops:<id>'|'system'
  action        text NOT NULL,            -- 'phi.read','phi.export','phi.delete','consent.grant','consent.withdraw','inference.call'
  resource      text NOT NULL,            -- 'measurements','scores','voice_session',...
  resource_id   text, region text NOT NULL,
  request_id    text, ip_hash text,       -- hashed, never raw IP in audit
  detail        jsonb,                    -- ids/counts only; NO PHI values
  created_at    timestamptz NOT NULL DEFAULT now()
);
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC;   -- append-only enforced by grants + trigger
-- WRITES: edge + workers (insert only). READS: compliance/ops (out-of-band). No row deletes ever (except legal-hold lift).

-- ============ VENDOR REGISTER (GLOBAL, non-PHI) ============
CREATE TABLE vendor_register (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor        text NOT NULL,            -- 'Deepgram','Cartesia','Sarvam','Google Vertex','AWS Bedrock'
  service       text NOT NULL,            -- 'STT','TTS','LLM','DocAI'
  region_scope  text NOT NULL,            -- 'eu'|'in'|'both'
  agreement_type text NOT NULL,           -- 'DPA','BAA','DPA+SCC'
  no_train      boolean NOT NULL, zdr boolean,
  residency_attested text, signed_at date, doc_url text
);
-- No PHI. READS: vendor-gate (a vendor may be invoked only if an active register row permits it for the region).
```

**Region pinning recap:** every PHI row carries `region`; RLS scopes by `user_id`; the stack asserts `region == local_region` on read/write; storage and inference geos live on `users` and are honored by workers when constructing region-pinned SDK clients.

---

## APIs / interfaces

All endpoints are versioned `/v1`, region-routed, JSON, TLS 1.3. Bearer access token in `Authorization`; RLS session var set from token `sub → user_id`. Every PHI-returning endpoint passes the **consent gate** (active `consents` row for the relevant scope) and writes an `audit_log` `phi.read`.

### Auth / session (Sign in with Apple)

- `POST /v1/auth/apple` — body: Apple `identity_token` (JWT) + `authorization_code`. Server **verifies the JWT** against Apple's public keys (`appleid.apple.com` JWKS), validates `iss`, `aud` (our bundle/services id), `exp`, and `nonce` (bound to a client-generated nonce hashed into the SiwA request). Extracts the stable `sub` (Apple subject). On first sign-in, resolves/creates the `apple_sub → region` directory entry (region chosen by device locale/store front + IP geo at signup, then **immutable**), creates `users`/`profiles` in that region. Returns our own `access_token` (short-lived JWT, ~15 min, signed by our KMS-backed key) + opaque `refresh_token` (rotating, ~30–90 day, stored hashed server-side). We do **not** reuse Apple's token as our session token — Apple's `identity_token` is consumed once for identity bootstrap; the `authorization_code` is exchanged with Apple to obtain a `refresh_token` we keep solely to detect Apple account revocation (App Store requirement) and to power SiwA-driven account deletion.
- `POST /v1/auth/refresh` — rotating refresh: old refresh token invalidated, new access+refresh returned. Reuse of a rotated token => revoke the whole token family (theft detection).
- `POST /v1/auth/revoke` / `DELETE /v1/account` — sign-out / account deletion (see below). On Apple `server_to_server` revocation webhook, we mark the session family revoked.
- **Why not Apple token as session:** Apple `identity_token` is short-lived and not designed as a bearer for our API; we need our own claims (region, consent state, RLS subject), our own rotation/theft-detection, and independence from Apple key rotation per request.

### Data-subject rights (one pipeline)

- `POST /v1/account/export` — enqueues a portability job; produces a single machine-readable archive (JSON + original PDFs) of all `user_id` rows across every PHI table **in the user's region only**, delivered via a short-lived presigned S3 URL. Satisfies **GDPR Art. 20 portability** and **DPDP access**. Writes `audit_log phi.export`.
- `DELETE /v1/account` — single delete pipeline that satisfies **GDPR Art. 17 erasure**, **DPDP withdrawal/erasure**, **App Store 5.1.1(v) in-app deletion**. Flow: set `users.status='deletion_pending'` → cascade-delete all PHI rows (`ON DELETE CASCADE` from `users`) → delete region S3 objects (`ingestion_artifacts`, `reports`, transcripts) → call Apple token `revoke` → tombstone the `apple_sub → region` directory entry → set `status='deleted'`, `deleted_at`. `audit_log` rows are retained (append-only, PHI-free) as proof of deletion; a `phi.delete` audit row records counts. Idempotent and resumable (it is itself an SQS-driven job with a DLQ).
- `POST /v1/consents` / `DELETE /v1/consents/{scope}` — grant/withdraw; writes versioned `consents` row with `evidence_blob`. Withdrawal flips the consent gate immediately and may trigger scoped deletion (e.g. withdrawing `voice_session` deletes transcripts).

### Health endpoints (thin client reads server-computed logic)

- `POST /v1/ingest/presign` → `{upload_url, artifact_id}` (S3 presigned PUT, SSE-KMS). `POST /v1/ingest/commit` (with `sha256`) → creates `ingestion_artifacts` + `ingestion_jobs(queued)` + `outbox(parse.requested)` in one txn.
- `GET /v1/ingest/jobs/{id}` → FSM status for upload progress UI.
- `POST /v1/healthkit/sync` → batched samples + per-type anchor round-trip (see below).
- `GET /v1/overview` → 8 organ-system tiles (zones from `analysis_results`), PROMIS two-band header, WHO-5 streak; PhenoAge present but never headline.
- `GET /v1/systems/{key}` → one tile's parameters + zones + trends.
- `GET /v1/parameters/{id}` → single-parameter history for Swift Charts (value/ref/optimal bands, flags, null annotations).
- `GET /v1/bioage` → PhenoAge (opt-in, secondary) + caveats; KDM/HD return `not_available` until Phase 2.
- `POST /v1/voice/session` → returns LiveKit ephemeral token + ICE config + spoken/visual disclosure copy; requires active `voice_session` consent and writes `voice_sessions` row. **No API key ever embedded in client.**
- `GET /v1/prep-report/{id}` → PrepReport JSON (post-guardrail).
- `GET /v1/qol` / `POST /v1/qol` → PROMIS Global-10, WHO-5 daily check-in.

---

## Tech choices

- **AWS Aurora PostgreSQL, region-pinned, RLS** — already locked. Postgres RLS gives per-user isolation at the data layer (defense even against an app bug), `jsonb` covers consent evidence / score inputs / extraction confidence, and Aurora's per-region clusters cleanly realize residency. Supabase rejected (no India region, blocked in India Feb 2026).
- **FastAPI on ECS Fargate** — async-native (matches SQS/outbox and Vertex/Bedrock SDK calls), trivial `/v1` versioning, per-region task definitions. Fargate over Lambda for warm DB pools + long-lived Vertex/Bedrock clients and to avoid VPC-Lambda cold-start tax on the inference path.
- **SQS FIFO + transactional outbox** — exactly-once-ish per `MessageGroupId = user_id` ordering; outbox guarantees we never enqueue without committing state (and never commit state without an enqueue intent). DLQ per stage isolates poison messages.
- **S3 SSE-KMS (CMK per region)** — raw PDFs and transcripts encrypted with region-scoped customer-managed keys; key policy denies cross-region grants. TLS 1.3 everywhere in transit.
- **Inference**: Vertex `asia-south1` (Gemini + Document AI) for India — the only single-vendor true-India BAA-eligible stack; EU uses Vertex `europe-west3` or Claude on Bedrock `eu-central-1` (in-region + ZDR). **Claude on Bedrock in India is global cross-region inference and is excluded from the India PHI path.** Claude (EU/US first-party) is reserved for EU-resident or de-identified data — notably the Opus prep-sheet in EU and any aggregate/research path after de-identification.
- **Voice: LiveKit Agents, self-hosted modular pipeline** on BAA EU/India infra — chosen over an integrated realtime API for PHI residency, medical-safe LLM swap, and inter-step guardrails (RAG-over-measurements, intent router hard-escalation, Llama Guard/Guardrails output filter). EU = Deepgram Nova-3/AssemblyAI (Dublin) + Cartesia Sonic-3; India = Sarvam AI all-in-India (22 langs). On-device tier (Apple SpeechAnalyzer / whisper.cpp + AVSpeechSynthesizer) for zero-egress privacy mode.
- **SwiftUI iOS 17+ (target 18/26), Observation framework**, thin client — server owns all medical logic. WebRTC + ephemeral tokens for voice; `AVAudioSession .voiceChat` for AEC; HealthKit via `HKAnchoredObjectQuery`.
- **Secrets**: AWS Secrets Manager + KMS; ephemeral voice tokens minted server-side; the `apple_sub → region` directory is a DynamoDB global table holding only opaque subject hash + region letter (no PHI).

---

## Risks

1. **Unit-conversion bugs in scores (#1 medical risk).** PhenoAge demands CRP mg/dL, creatinine µmol/L, glucose mmol/L, albumin g/L; CKD-EPI must use 2021 race-free coefficients (−0.241F/−0.302M), not 2009. *Mitigation:* canonical units enforced at the `measurements` layer; `scores.inputs` jsonb persists the exact unit-corrected values used so every computation is auditable and reproducible; golden-vector unit tests per formula in CI; reject scores when an input is out of `plausibility_low/high`.
2. **Accidental cross-region PHI movement / wrong inference endpoint.** *Mitigation:* `region` on every row + stack-local assertion; CI lint forbidding unpinned Vertex/Bedrock clients; `vendor_register` gate; the Claude-on-Bedrock-India exclusion encoded as a hard config rule.
3. **HealthKit background delivery unreliable (esp. watchOS 26); cannot detect denied READ.** *Mitigation:* treat background delivery as best-effort; foreground catch-up via persisted anchors; tolerate empty results (never block UI; never claim a vital-sign diagnosis — App Store 1.4.1).
4. **Educational stance vs. EU AI Act high-risk classification of voice.** *Mitigation:* spoken + visual AI disclosure at voice session start, documented intended-use/limitations, standalone DPDP consent before any voice session, hard-escalation router for symptomatic/emergency, refusal of ungrounded numbers.
5. **Consent drift / stale policy version.** *Mitigation:* `policy_versions` + per-consent `policy_version`; consent gate checks the binding; re-consent flow when a new version is effective.
6. **Append-only audit integrity.** *Mitigation:* grant-level `REVOKE UPDATE/DELETE`, no app role with mutate rights, periodic hash-chain export to WORM S3.
7. **App Store rejection** (SiwA-if-Google 4.8; no sensor vital-sign claims 1.4.1; no PHI in iCloud/CloudKit 5.1.3; in-app deletion 5.1.1(v)). *Mitigation:* SiwA mandatory, "see your doctor" copy, PHI never in CloudKit, single in-app delete pipeline.
8. **Indian-population miscalibration** of SCORE2/ASCVD/KDM/HD. *Mitigation:* educational-estimate + not-calibrated caveat in `scores.caveats`; KDM/HD deferred to Phase 2 with Indian recalibration.

---

## Phased build

- **Phase 0 — Foundations.** Two-region infra (Aurora, S3 SSE-KMS, ECS, SQS+DLQ, KMS, Secrets, `apple_sub→region` directory). Schema + RLS + audit grants. SiwA auth + session/refresh. Region-routing + consent-gate middleware. `policy_versions`/`consents`/`vendor_register`. One export/delete pipeline (GDPR/DPDP/5.1.1). Observability with PHI-free logging.
- **Phase 1 — Ingestion → analysis.** Presign/commit, outbox→SQS FIFO, parse workers (Document AI region-pinned) → `reports`/`measurements` with LOINC mapping + `parameter_raw` fallback. Analyze workers: PhenoAge, CKD-EPI 2021, FIB-4, NAFLD-FS, TyG, HOMA-IR, NLR/AAR/PLR → `analysis_results`/`scores`. `/v1/overview|systems|parameters|bioage`. Recompute fan-out on `catalog_version`/`engine_version` bump.
- **Phase 2 — Device + QoL + bio-age depth.** HealthKit `HKAnchoredObjectQuery` ingestion as "device" source; anchors; foreground catch-up. PROMIS Global-10 + WHO-5. KDM + Homeostatic Dysregulation fitted on NHANES then recalibrated on Indian pop.
- **Phase 3 — Voice + prep-sheet.** LiveKit modular pipeline both regions; ephemeral tokens; RAG-over-measurements grounding; intent router + output guardrails; EU AI Act disclosures; standalone voice consent. Opus prep-sheet (EU/de-identified path) with PrepReport JSON + post-gen guardrails.
- **Phase 4 — De-identified research path.** k-anonymized export pipeline enabling Claude (EU/US) aggregate analysis; vendor DPAs/SCCs finalized.

---

## Open questions

1. **Region immutability vs. relocation.** Region is set once and immutable. Do we support a user physically relocating EU↔India (requires a supervised, audited data-migration + re-consent), or is region permanent for the account's life?
2. **HealthKit residency framing.** HealthKit data is health data under both regimes; is on-device-derived HRV/VO2max treated identically to lab PHI for export/delete and inference pinning? (Assumed yes here.)
3. **Voice transcript retention.** Default retention for `voice_sessions.transcript_s3_key` — keep for continuity, or ephemeral-by-default with explicit opt-in to retain? DPDP/GDPR minimization argues ephemeral.
4. **De-identification standard** for the Claude research path — what k and which quasi-identifiers (age band, region, sex) satisfy our DPA + DPDP for "no longer personal data"?
5. **Apple data-deletion webhook coverage.** When Apple sends `account-delete`, do we hard-delete immediately or enter the same `deletion_pending` grace window we offer in-app?
6. **PhenoAge missing-input policy.** If a required analyte (e.g. CRP) is absent, do we suppress the score, impute from prior reports, or surface a partial bio-age with explicit caveat? (Leaning suppress.)
7. **Cross-region family accounts / clinician sharing** — out of scope for v1, but does any future sharing break the strict one-user-one-region model?
8. **Existing React PWA relationship.** The current React PWA is treated as a **legacy/secondary surface**: the iOS-native app is primary; the PWA, if retained, must consume the *same* region-routed `/v1` API and obey the same consent gate and residency rules (no direct DB access, no separate data plane). Confirm whether the PWA is sunset post-iOS-GA or maintained as a web companion — and if maintained, it does **not** get HealthKit or native voice, and must show the same educational/AI disclosures.