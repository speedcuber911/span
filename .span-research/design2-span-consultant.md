# SPAN-CONSULTANT — Realtime Voice Health Bot Design

> First deliverable: research + plan only. No code. All formulas, residency pins, vendor topology, and the shared data model are LOCKED per the SPAN ingestion/pre-analytics/presentation designs and are REUSED, not redefined, here.

---

## Overview

**SPAN-CONSULTANT** is the realtime, low-latency voice agent of the SPAN longevity app. It is a *spoken interface over the user's already-extracted lab data and analysis results* plus a *structured onboarding interviewer*. It does two jobs, both grounded and both educational-only:

1. **Grounded read-aloud Q&A** — the user asks "how's my cholesterol?" / "what was my last HbA1c?" / "explain my kidney tile". The bot answers by retrieving the exact persisted `measurements` / `analysis_results` rows for that user and speaking **only** the retrieved `value + unit + ref_low + ref_high + flag + report_date + lab`, plus a tier-labelled educational framing ("clinically normal but above the longevity-optimal band Attia/expert opinion — discuss with your clinician"). It never computes a new diagnosis, never proposes a dose, never invents a number.

2. **Structured onboarding interview** — a conversational elicitation that captures the *missing model inputs* the lab PDFs cannot give us (BMI/height/weight, smoking status, blood pressure, diabetes/IFG status, family history) that unlock SCORE2 / NAFLD-FS / PhenoAge BMI-dependent paths, plus lifestyle, goals, current symptoms, and chronic conditions — and writes them back as **structured, versioned, consented** profile rows, not free text.

**Hard product boundaries (inherited, non-negotiable):**

- **Medical stance = EDUCATIONAL.** Cite reference ranges, say "discuss with your clinician," never diagnose, never dose. App Store guideline 1.4.1 (educational-not-diagnostic), no sensor-derived vital-sign claims.
- **Residency = two independent pins per user** (`storage_geo`, `inference_geo`). India principals never leave ap-south-1 for storage and never use a global cross-region inference path. **Claude is excluded from the India PHI path** (Claude-on-Bedrock in India = global cross-region inference; Claude first-party = US inference). Claude is allowed only for EU-resident or de-identified data.
- **EU AI Act = treat as HIGH-RISK** regardless of the "educational" label: spoken + visual AI disclosure at session start, documented intended-use/limitations, standalone DPDP consent before any voice session.
- **PHI never in iCloud/CloudKit; never PHI for ads** (App Store 5.1.3). One delete/export pipeline already serves App Store + GDPR + DPDP.

The architectural thesis of this document: **a modular, self-hosted LiveKit Agents pipeline beats an integrated realtime API**, because the only way to satisfy (a) per-region PHI residency across *every* processor, (b) a medical-safe, swappable LLM with (c) inter-step guardrails that can refuse ungrounded numbers — is to own and instrument each hop (STT → router/guardrail → grounded LLM → output filter → TTS). The integrated realtime APIs collapse those hops into one opaque US/global model call we cannot pin, swap, or inspect.

---

## Architecture

### Why MODULAR (LiveKit Agents) over an integrated realtime API

| Dimension | Integrated realtime API (single multimodal model, audio-in/audio-out) | **Modular pipeline (LiveKit Agents, self-hosted)** — CHOSEN |
|---|---|---|
| **PHI residency** | Audio + transcript leave to a single vendor's region (US/global for the frontier realtime APIs). Cannot pin India-resident, cannot guarantee EU-in-region. **Fails India DPDP and the inference_geo pin outright.** | Every hop (STT, LLM, TTS) is an independently chosen, regionally-pinned, BAA/DPA-covered processor on our BAA EU/India infra. India = all-in-India (Sarvam). EU = Dublin/Frankfurt processors. |
| **LLM swap / medical safety** | LLM is fused to the audio model; cannot substitute a medically-tuned or region-legal LLM, cannot route India→Vertex asia-south1 vs EU→Vertex europe-west3/Claude-Bedrock. | LLM is one swappable step. India→Gemini on Vertex asia-south1; EU→Vertex europe-west3 **or** Claude on Bedrock eu-central-1 (in-region + ZDR). De-identified → Claude allowed. |
| **Inter-step guardrails** | No insertion point between hearing and speaking — the model decides and vocalizes atomically. Cannot deterministically block an ungrounded number. | Guardrails sit **between** steps: intent router pre-LLM (emergency hard-escalate), RAG grounding gate, Llama Guard / output filter post-LLM and pre-TTS. A number with no retrieved source is refused before it is ever spoken. |
| **Auditability** | Opaque. Hard to produce the append-only evidence trail DPDP/GDPR/EU-AI-Act expect. | Each step logs to `audit_log`; transcripts + retrieved-source citations are persisted; intended-use/limitations documentable. |
| **Latency** | Lower (single round trip, ~300–500 ms). **This is the only axis the integrated API wins.** | Higher but bounded — budget below targets ~1.0–1.5 s first-audio. We trade ~0.5 s for residency + safety + swappability. For an educational health bot, **correct-and-legal beats fastest.** |
| **Cost** | Premium per-minute, opaque. | ~$0.08–0.18/min self-hosted, line-item controllable. |

**Decision: MODULAR.** The integrated realtime API's single advantage (latency) is the one we can most afford to lose; its disadvantages (residency, swappability, guardrail insertion, auditability) are each independently disqualifying for a multi-region medical-educational product.

### Audio / data path (ASCII)

```
                                   ┌──────────────────────── iOS CLIENT (thin SwiftUI) ────────────────────────┐
                                   │  AVAudioSession(.playAndRecord, mode: .voiceChat)  → HW AEC / NS / AGC     │
                                   │  Push-to-talk (default)  |  Open-mic (opt-in)                              │
                                   │  WebRTC mic publish (Opus) ▲▼ TTS subscribe (Opus) → AVAudioEngine playout │
                                   │  Live caption view (partial+final transcripts)  |  Interruption/route obs  │
                                   └───────────────┬──────────────────────────────────────────────▲────────────┘
                                                   │ 1) POST /v1/voice/sessions (Bearer = Apple JWT)│
                                                   │    server mints EPHEMERAL LiveKit token        │ region-routed
                                                   ▼    (TTL ≤60s, room+identity+grants scoped)      │ by user.region
   ┌───────────────────────────── SPAN BACKEND (FastAPI, region-routed) ──────────────────────────────────────┐
   │  Session API → consent gate (DPDP standalone + AI-Act disclosure ack) → mint token → audit_log            │
   │  Reads user.region → selects REGION STACK (in: ap-south-1 / eu: eu-central-1). NO cross-region.            │
   └───────────────────────────────────────────────┬──────────────────────────────────────────────────────────┘
                                                    │ WebRTC media (SRTP/DTLS) + data channel (events)
                                                    ▼
   ┌──────────────────── LiveKit SFU + Agents worker (self-hosted, BAA infra, IN-REGION) ─────────────────────┐
   │                                                                                                            │
   │   mic audio ─► [VAD: Silero] ─► [turn-end: SmolLM-v2 semantic] ─► utterance boundary                       │
   │                       │ barge-in: user speech detected during TTS → cancel TTS, flush playout              │
   │                       ▼                                                                                     │
   │                  ┌─[STT]──────────────────────────────────────────────────────────────────┐               │
   │   EU  ───────────►  Deepgram Nova-3 / AssemblyAI (Dublin, HIPAA BAA, no-train)              │               │
   │   IN  ───────────►  Sarvam STT (in-India, 22 langs, Indian medical terms)                   │               │
   │   on-device tier ─►  Apple SpeechAnalyzer (iOS26) / whisper.cpp (zero egress, never leaves)  │              │
   │                  └────────────────────────────┬───────────────────────────────────────────┘               │
   │                                               ▼ final transcript text                                      │
   │              ┌─[INTENT ROUTER]──────────────────────────────────────────────────────────────┐             │
   │              │  classify: data-lookup | onboarding | smalltalk | SYMPTOMATIC/EMERGENCY        │             │
   │              │  EMERGENCY/symptomatic → HARD ESCALATE: stop, speak safety script, end turn    │             │
   │              └───────────────┬──────────────────────────────────────────────────────────────┘             │
   │                              ▼ (safe intents only)                                                         │
   │              ┌─[RAG / STRUCTURED CONTEXT GATE]──────────────────────────────────────────────┐             │
   │              │  fetch from Aurora (RLS user_id): measurements + analysis_results + profile    │             │
   │              │  build grounded context block: {value,unit,ref_low,ref_high,flag,date,lab,...} │             │
   │              └───────────────┬──────────────────────────────────────────────────────────────┘             │
   │                              ▼ grounded context + system prompt + tool schema                              │
   │              ┌─[LLM]────────────────────────────────────────────────────────────────────────┐             │
   │   IN  ───────►  Gemini on Vertex AI asia-south1  (single-vendor true-India stack, BAA)        │            │
   │   EU  ───────►  Vertex europe-west3  OR  Claude on Bedrock eu-central-1 (in-region + ZDR)     │             │
   │              │  tools: get_measurement / list_trend / get_score / write_onboarding_field      │             │
   │              │  REFUSES any number not present in grounded context (retrieval-grounding rule)  │             │
   │              └───────────────┬──────────────────────────────────────────────────────────────┘             │
   │                              ▼ proposed spoken text (+ any tool calls)                                      │
   │              ┌─[OUTPUT GUARDRAIL]───────────────────────────────────────────────────────────┐             │
   │              │  Llama Guard / Guardrails: block dx/dose/ungrounded-number; verify every spoken │            │
   │              │  number is byte-traceable to a retrieved source; enforce clinician closing      │            │
   │              └───────────────┬──────────────────────────────────────────────────────────────┘             │
   │                              ▼ approved text                                                                │
   │                  ┌─[TTS]──────────────────────────────────────────────────────────────────┐               │
   │   EU  ───────────►  Cartesia Sonic-3 (40 ms TTFA, HIPAA+GDPR+ZDR)                           │               │
   │   IN  ───────────►  Sarvam TTS (in-India, Indian-language prosody)                          │               │
   │   on-device tier ─►  AVSpeechSynthesizer (zero egress)                                       │              │
   │                  └────────────────────────────┬───────────────────────────────────────────┘               │
   │                                               ▼ Opus frames → SFU → client playout                         │
   │   side-effects: persist voice_sessions / transcripts / extracted profile → Aurora; append audit_log        │
   └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Key invariant:** the dashed boxes are *separate processes with logging between them*. The number a user hears is gated three times — intent (is this even a safe ask?), grounding (does a persisted source exist?), output (is every spoken token traceable + non-diagnostic?). No single model both decides and speaks.

---

## Data model (extend shared schema — do NOT redefine existing tables)

All new tables carry `region in ('in','eu')`, are protected by the same **Row-Level Security on `user_id`**, live in the **region-pinned Aurora**, and reference existing `users(id)`. Consent for voice is recorded in the existing `consents` table (new scope rows), not a new consent store.

### `voice_sessions`
```
voice_sessions(
  id                uuid pk,
  user_id           uuid not null references users(id),
  region            text not null check (region in ('in','eu')),     -- = user.region, denormalized for RLS/partition
  inference_geo     text not null,        -- asia-south1 | europe-west3 | eu-central-1 (resolved stack)
  storage_geo       text not null,        -- ap-south-1 | eu-central-1
  channel           text not null,        -- 'voice' | 'text_fallback'
  privacy_tier      text not null,        -- 'cloud_region' | 'on_device'   (on-device => no audio/transcript egress)
  livekit_room      text not null,
  started_at        timestamptz not null,
  ended_at          timestamptz,
  end_reason        text,                 -- user_hangup | timeout | emergency_escalation | error | route_lost
  consent_id        uuid references consents(id),   -- the standalone DPDP voice consent satisfied this session
  ai_disclosure_ack boolean not null default false, -- EU AI Act: spoken+visual disclosure acknowledged
  intent_summary    text,                 -- coarse: 'data_lookup','onboarding','mixed'
  escalation_flag   boolean not null default false, -- emergency/symptomatic hard-escalation fired
  model_versions    jsonb,                -- {stt, llm, tts, guardrail, router} pinned ids for audit
  audio_retained    boolean not null default false, -- default: audio NOT retained; transcript only
  s3_audio_key      text,                 -- null unless user opted into audio retention; SSE-KMS, region bucket
  created_at        timestamptz default now()
)
```

### `transcripts` (turn-level, append-only)
```
transcripts(
  id                uuid pk,
  session_id        uuid not null references voice_sessions(id),
  user_id           uuid not null references users(id),
  region            text not null check (region in ('in','eu')),
  turn_index        int not null,
  speaker           text not null,        -- 'user' | 'assistant' | 'system'
  text              text not null,
  stt_confidence    numeric,              -- null for assistant/system turns
  intent            text,                 -- router label for user turns
  grounded_sources  jsonb,               -- for assistant turns: [{measurement_id|score_id, value,unit,ref_low,ref_high,flag,date}]
  guardrail_action  text,                 -- 'pass' | 'redacted' | 'refused' | 'escalated'
  language          text,                 -- BCP-47 (en-IN, hi-IN, ...)
  created_at        timestamptz default now(),
  UNIQUE(session_id, turn_index)
)
```
`grounded_sources` is the **proof of grounding**: every assistant number must appear here with its source row id. An assistant turn that spoke a number absent from `grounded_sources` is a guardrail breach and is flagged in `audit_log`.

### `onboarding_profile` (structured elicited inputs — the model-input gap-filler)
One current row per `user_id` + append-only history via `onboarding_profile_history`. Every field is **versioned, consented, sourced, and confidence-scored**, because these feed clinical-educational scores (SCORE2, NAFLD-FS, PhenoAge BMI path).
```
onboarding_profile(
  user_id            uuid pk references users(id),
  region             text not null check (region in ('in','eu')),
  -- anthropometrics (unlock BMI -> NAFLD-FS, PhenoAge BMI-dependent display)
  height_cm          numeric,
  weight_kg          numeric,
  bmi                numeric generated always as (weight_kg / power(height_cm/100.0, 2)) stored,
  -- cardiometabolic model inputs (unlock SCORE2 / ASCVD educational estimate)
  smoking_status     text,        -- never | former | current
  sbp_mmhg           numeric,     -- self-reported BP, flagged source='self_report'
  dbp_mmhg           numeric,
  on_bp_treatment    boolean,
  diabetes_status    text,        -- none | prediabetes_IFG | type2 | type1 | gestational
  on_glucose_treatment boolean,
  -- NAFLD-FS needs diabetes/IFG flag (above) + BMI (above) + albumin/AST/ALT/platelets (from labs)
  -- clinical context
  chronic_conditions jsonb,       -- [{condition, since_year, controlled}] free-but-normalized
  medications        jsonb,       -- name/class only (no dosing logic), for interaction awareness display
  family_history     jsonb,       -- [{relation, condition}] -> e.g. early ASCVD, Lp(a) context
  -- lifestyle + goals + symptoms (qualitative, for personalization not scoring)
  activity_level     text,        -- sedentary | light | moderate | vigorous
  sleep_self_report  jsonb,       -- {avg_hours, quality}
  diet_pattern       text,
  alcohol_units_wk   numeric,
  goals              jsonb,        -- [{goal, priority}]
  current_symptoms   jsonb,        -- [{symptom, onset, severity}] -> ALSO triggers escalation router
  -- governance
  field_sources      jsonb not null, -- per-field: {field: {source:'voice_onboarding'|'self_report'|'derived', session_id, turn_index, confidence}}
  policy_version     text not null,  -- consent policy version under which captured
  last_confirmed_at  timestamptz,    -- user re-confirmed; stale fields re-prompted
  updated_at         timestamptz default now()
)
```

**Write-back rule:** the LLM never writes these directly. It emits a `write_onboarding_field` tool call with `{field, value, unit, confidence, evidence_turn}`; the **server validates against a JSON schema + plausibility bounds (reuse `canonical_parameters.plausibility_low/high` patterns, e.g. height 50–250 cm), confirms verbally ("I've noted your height as 175 cm — is that right?"), then persists** with `field_sources` provenance and an `audit_log` entry. Anthropometrics that feed scores require an explicit spoken confirmation turn before commit.

**Feeding the scores:** once `bmi` + `diabetes_status` exist, the existing analytics layer can compute **NAFLD-FS** (which previously had to be withheld for lack of BMI+diabetes flag); `smoking_status` + `sbp_mmhg` + `on_bp_treatment` + `diabetes_status` unlock the **SCORE2/ASCVD educational estimate** (still emitted with the locked "not calibrated for India — educational estimate" caveat). These are computed server-side by the existing pipeline; SPAN-CONSULTANT only *captures inputs* and *reads results back*.

---

## APIs / interfaces

### 1. Session API (REST, `/v1`, region-routed)

**`POST /v1/voice/sessions`** — mint a session + ephemeral WebRTC token. Bearer = Apple Sign-in JWT.
```jsonc
// request
{ "channel": "voice",                  // or "text_fallback"
  "privacy_tier": "cloud_region",      // or "on_device"
  "ai_disclosure_ack": true,           // EU AI Act: client confirms it showed visual+played spoken disclosure
  "consent_scope": "voice_consult_v3", // standalone DPDP voice consent scope (must be granted, not withdrawn)
  "language_pref": "en-IN" }
// 201 response
{ "session_id": "uuid",
  "livekit": { "url": "wss://sfu.<region>.span...", "token": "<EPHEMERAL JWT, TTL 60s>",
               "room": "vs-<session_id>" },
  "region": "in", "inference_geo": "asia-south1",
  "disclosure": { "spoken_script_id": "...", "visual_required": true },
  "limits": { "max_session_sec": 900, "idle_timeout_sec": 45 } }
// 403 if consent not granted / withdrawn, or AI disclosure not acked  ->  forces consent+disclosure flow first
```
- Token minting is **server-side only**; the LiveKit API secret never reaches the device (locked iOS rule: never embed key). Token grants are scoped to exactly one room + identity, short TTL, single-use.
- Server resolves `user.region` → region stack and **refuses any cross-region**; an India user can only ever receive an ap-south-1 SFU + asia-south1 inference. No client override.

**`POST /v1/voice/sessions/{id}/end`** — explicit hangup; sets `ended_at`, `end_reason`. (Idempotent; also fired server-side on timeout/route-loss.)
**`GET /v1/voice/sessions/{id}/transcript`** — caption history / accessibility export (RLS-scoped).
**Reuses, not redefines:** grounded reads go through existing `/v1/overview`, `/v1/systems/{key}`, `/v1/parameters/{id}`, `/v1/bioage`; the RAG gate calls these internally so the voice path and the visual app share one source of truth.

### 2. WebRTC / LiveKit event contract (data channel, JSON events)

Server→client and client→server messages on the LiveKit data channel, so the thin client renders captions/state without business logic:
```jsonc
// server -> client (caption + state stream)
{ "type": "stt.partial",   "turn": 7, "text": "how is my chole" }
{ "type": "stt.final",     "turn": 7, "text": "how is my cholesterol", "confidence": 0.94 }
{ "type": "agent.state",   "state": "listening|thinking|speaking|escalated|ended" }
{ "type": "tts.caption",   "turn": 8, "text": "Your most recent LDL was 130 mg/dL ...", "sources":[{"measurement_id":"...","value":130,"unit":"mg/dL","ref_low":0,"ref_high":100,"flag":"high","date":"2026-03-02","lab":"Tata 1mg"}] }
{ "type": "disclosure.play","script_id":"ai_disclosure_v2" }      // client must show visual + has played spoken
{ "type": "escalation",    "kind":"emergency","script":"...","action":"end_after_play" }
{ "type": "error",         "code":"route_lost|stt_down|llm_refused|guardrail_block" }

// client -> server (control)
{ "type": "ptt.start" } / { "type": "ptt.end" }                   // push-to-talk gates mic publish
{ "type": "barge_in" }                                            // user tapped to interrupt TTS
{ "type": "mode.set", "open_mic": true }                          // open-mic opt-in
{ "type": "disclosure.ack", "script_id":"ai_disclosure_v2" }      // satisfies EU AI Act + DPDP gate
```

### 3. LLM system-prompt + tool-schema contract

**System prompt (region-templated, locked content):**
```
ROLE: SPAN-CONSULTANT, an EDUCATIONAL longevity assistant. You are NOT a clinician.
HARD RULES:
- Speak ONLY numbers present in the supplied GROUNDED_CONTEXT block. If a number is asked for and
  not present, say you don't have that result and offer to note it / suggest a test discussion. NEVER invent or estimate a lab value.
- NEVER diagnose, NEVER name a disease as the user's, NEVER suggest or imply a medication, dose, or titration.
- For each value spoken, include its reference range and flag, and frame longevity-optimal bands as
  "expert opinion (Attia/expert), discuss with your clinician" — distinct from the clinical reference range.
- If the user reports a symptom or anything urgent, DO NOT advise; the router will have escalated. Defer.
- Close clinically-relevant answers with "discuss this with your clinician."
- Onboarding: collect only via the write_onboarding_field tool; always read back numeric inputs for confirmation.
GROUNDED_CONTEXT: { measurements:[...], scores:[...], profile:{...} }   // injected per turn, user-scoped, RLS-fetched
TIER LABELS: T1 consensus / T2 promising / T3 contested-show-only-with-"no human outcome RCT, discuss w clinician".
```

**Tool schema (the only ways the model can touch data — all server-validated):**
```jsonc
get_measurement(parameter, latest|date_range)        // -> {value,unit,ref_low,ref_high,flag,date,lab,loinc_code} or null
list_trend(parameter, window)                        // -> ordered points for "is it improving?" (trend-only markers: TyG/NLR/AAR/PLR)
get_score(score in [phenoage,eGFR,FIB4,NAFLD_FS,TyG,...]) // -> {value, interpretation_band, caveats[]} (server-computed; never client/LLM-computed)
get_optimal_band(parameter)                          // -> {tier, band, label:"Attia/expert opinion"} (educational)
write_onboarding_field(field, value, unit, confidence, evidence_turn) // -> server validates+confirms+persists; LLM cannot write directly
flag_symptom(symptom, onset, severity)               // -> writes current_symptoms AND signals router/escalation
```
Every tool returns `null`/empty rather than a guess; a `null` forces the model down the "I don't have that result" path, which the output guardrail then verifies was honored.

---

## Tech choices

**Pipeline orchestration:** LiveKit Agents, **self-hosted on BAA-covered EU/India infra** (not LiveKit Cloud where region/BAA is unproven for India). Gives us VAD/turn-detection/barge-in primitives + the explicit STT→LLM→TTS step graph we need guardrails between.

**Two-region vendor topology (every box below is a PHI processor and needs a DPA/BAA + no-train clause):**

| Step | **EU stack** (eu-central-1 / Dublin) | **India stack** (ap-south-1, all-in-India) | On-device privacy tier |
|---|---|---|---|
| STT | Deepgram Nova-3 **or** AssemblyAI (Dublin region, **HIPAA BAA, no-train**) | **Sarvam AI** STT (in-India, 22 langs, Indian medical terms; VPC/on-prem) | Apple SpeechAnalyzer (iOS26) / whisper.cpp — **zero egress** |
| LLM | Vertex **europe-west3** *or* **Claude on Bedrock eu-central-1** (in-region + ZDR); de-identified→Claude OK | **Gemini on Vertex AI asia-south1** (BAA-eligible single-vendor true-India stack); **Claude EXCLUDED (global cross-region)** | small on-device model only for trivial/no-PHI turns; complex turns require cloud |
| TTS | **Cartesia Sonic-3** (40 ms TTFA, **HIPAA+GDPR+ZDR**) | **Sarvam** TTS (Indian-language prosody) | AVSpeechSynthesizer — **zero egress** |
| Turn/VAD | Silero VAD + SmolLM-v2 semantic end-of-turn; adaptive barge-in | same | same (local) |
| Guardrail | Llama Guard / Guardrails output filter (in-region) | Llama Guard / Guardrails (in-India) | n/a (on-device tier still routes text through in-region guardrail unless fully local) |

**DPA/BAA chain (the controller→processor map that must exist before launch):**
```
SPAN (controller)
 ├─ AWS (Aurora ap-south-1/eu-central-1, S3 SSE-KMS)        — BAA + Art.28 DPA + SCCs
 ├─ LiveKit self-hosted (our infra; SFU is a processor)     — runs on our BAA infra; no third-party media egress
 ├─ EU: Deepgram/AssemblyAI (STT)  — HIPAA BAA + GDPR DPA + SCCs + no-train
 │      Cartesia (TTS)             — HIPAA BAA + GDPR DPA + ZDR + no-train
 │      Google Vertex europe-west3 / AWS Bedrock eu-central-1 (LLM) — BAA/DPA + ZDR/no-train, in-region
 └─ IN: Sarvam (STT+TTS+LLM option) — India DPDP processor agreement + no-train + in-India residency
        Google Vertex asia-south1 (Gemini + Document AI)    — BAA + in-region (asia-south1), no-train
On-device tier: no processor — audio/transcript never leave device (best privacy posture; offered as opt-in).
```
A vendor without a signed BAA/DPA + no-train clause **cannot be in the PHI path** — that is the gating rule for the whole table.

**iOS audio path (locked details):**
- WebRTC client + **ephemeral tokens minted server-side** (key never embedded).
- `AVAudioSession` category `.playAndRecord`, **mode `.voiceChat`** → hardware **AEC/NS/AGC** so TTS playback doesn't feed back into the mic (enables clean barge-in).
- **Push-to-talk is the default**; **open-mic is explicit opt-in** (`mode.set open_mic:true`) — privacy + battery + accidental-capture safety, and it makes barge-in/turn-taking deterministic.
- **Interruption handling:** observe `AVAudioSession.interruptionNotification` (calls, Siri) → pause publish, mark `agent.state`, resume on `.shouldResume`. **Route-change handling:** observe `routeChangeNotification` (BT/headset unplug) → re-evaluate session, and **re-install the input tap** to work around the known *installTap-drops-after-call* bug; if route is lost mid-turn, end with `end_reason=route_lost`.
- **VAD = Silero** locally + server semantic turn-end; **adaptive barge-in** cancels in-flight TTS the instant user speech is detected.
- **Accessibility:** live **caption view** of partial + final transcripts (`stt.partial/final`, `tts.caption`), VoiceOver-labelled state, full transcript export — also the **text-chat fallback** surface.

**Latency budget (cloud-region tier, target first-audio ≤ ~1.3 s after user stops speaking):**
```
end-of-speech detection (Silero+SmolLM turn-end)   ~150–250 ms
STT finalization (streaming, Nova-3/Sarvam)         ~150–300 ms
intent router + RAG fetch (Aurora, RLS, indexed)    ~100–200 ms
LLM first token (Vertex/Bedrock/Gemini streaming)   ~300–500 ms
output guardrail (streamed, first-chunk)            ~ 50–120 ms
TTS TTFA (Cartesia Sonic-3 ~40 ms / Sarvam)         ~ 40–150 ms
network (WebRTC, in-region SFU)                      ~ 40–100 ms
------------------------------------------------------------------
first audible token                                 ~ 0.9–1.5 s
```
Mitigations: stream STT + LLM + guardrail + TTS (don't wait for full turns), prefetch the user's `GROUNDED_CONTEXT` at session start, in-region SFU, speculative TTS of safe filler ("let me check that…") while the grounded answer renders.

**Cost:** ~**$0.08–0.18/min** self-hosted (STT + LLM tokens + TTS + SFU/compute), line-item controllable; on-device tier ≈ compute-only. **Text-chat fallback** (same intent router + RAG + guardrail + LLM, no STT/TTS) is the cheapest path and the accessibility/degraded-network/no-mic-permission backstop — same grounding contract, just typed.

---

## Risks

| # | Risk | Why it bites SPAN | Mitigation |
|---|---|---|---|
| R1 | **Ungrounded number spoken** (model hallucinates a lab value) | Directly violates educational stance + erodes trust; a fabricated "your LDL is 90" is a safety event. | Triple gate: RAG-only context, tool returns `null` not guesses, output guardrail byte-traces every spoken number to `grounded_sources`; refuse + log if untraceable. |
| R2 | **India PHI leaks to a global/cross-region inference path** (esp. accidental Claude-on-Bedrock) | Breaks DPDP residency + inference_geo pin; regulatory + India-block precedent (Supabase). | Hard server-side region routing; Claude blocked from India PHI path in code + infra policy; per-session `inference_geo` recorded; audit. |
| R3 | **Emergency/symptomatic turn handled as Q&A** | Educational bot giving urgent-care guidance = clinical + legal exposure. | Intent router **hard-escalates before LLM**; speaks fixed safety script; `flag_symptom`; ends turn; never advises. |
| R4 | **EU AI Act high-risk non-compliance** | Likely high-risk regardless of "educational" label; transparency duties since Aug 2025. | Spoken+visual AI disclosure gated in session API (403 without ack); documented intended-use/limitations; standalone DPDP consent pre-session; append-only audit. |
| R5 | **iOS mic capture bug** (installTap drops after call/route change) | Silent dead-mic mid-consult; user thinks bot ignores them. | Route-change + interruption observers re-install tap; watchdog detects silent input; surface `error route_lost`; PTT bounds exposure. |
| R6 | **Background/HW unreliability** (watchOS26 background delivery, AEC variance across devices) | Degraded turn-taking, echo, false barge-in. | `.voiceChat` HW AEC; PTT default; Silero VAD thresholds adaptive; foreground-only voice session. |
| R7 | **Onboarding writes a wrong model input** (bad BMI → wrong NAFLD/SCORE2) | Garbage-in to clinical-educational scores. | Plausibility bounds + verbal read-back confirmation before commit; `field_sources` provenance + confidence; re-confirm stale fields. |
| R8 | **STT mishears medical terms / code-switching (Hindi-English)** | Wrong parameter retrieved, wrong language TTS. | India = Sarvam (Indian medical lexicon, 22 langs, code-switch); confirm parameter back to user before reading values; confidence threshold → re-ask. |
| R9 | **Vendor without no-train/BAA slips into path** | Silent residency/training violation. | Gating rule: no PHI hop without signed BAA/DPA + no-train; `model_versions` pinned per session; vendor allowlist enforced server-side. |
| R10 | **Latency erodes UX vs integrated API** | Users abandon slow voice. | Streaming everything, context prefetch, in-region SFU, speculative filler; accept ~0.5 s tax as the cost of residency+safety; text fallback. |
| R11 | **Audio retention scope creep** | Raw voice is PHI; storing it widens breach surface + erasure burden. | Default `audio_retained=false` (transcript-only); audio only on explicit opt-in, SSE-KMS region bucket, in the one delete/export pipeline. |

---

## Phased build

**Phase 0 — Foundations & legal gates (no audio).** DPA/BAA + no-train signed with every prospective processor (Deepgram/AssemblyAI, Cartesia, Sarvam, Vertex regions, Bedrock); EU AI Act intended-use/limitations doc + disclosure scripts; standalone DPDP `voice_consult_v*` consent scope + `consents` rows; new tables (`voice_sessions`, `transcripts`, `onboarding_profile`) with RLS + region pins; `audit_log` wiring.

**Phase 1 — Text-chat fallback first (de-risks grounding).** Intent router + RAG over `measurements`/`analysis_results`/`onboarding_profile` + LLM with the locked system prompt/tool schema + Llama Guard output filter + grounding-refusal, *typed only*. This proves the safety spine before adding audio, and ships the accessibility/degraded-network path. Region routing + Claude-exclusion-for-India enforced here.

**Phase 2 — Voice EU stack.** LiveKit Agents self-hosted (eu-central-1), Deepgram/AssemblyAI STT + EU LLM + Cartesia TTS; iOS WebRTC + ephemeral tokens + `.voiceChat` AEC + PTT default + interruption/route-change handling + Silero VAD + captions. Wire spoken+visual AI disclosure gate.

**Phase 3 — Voice India stack.** Sarvam all-in-India STT/TTS/LLM (or Gemini asia-south1 LLM) on ap-south-1 BAA infra; Hindi-English code-switch + Indian medical lexicon; same disclosure/consent gates; verify zero cross-region.

**Phase 4 — Structured onboarding conversation.** Guided elicitation of lifestyle/goals/symptoms/chronic conditions **and the missing model inputs (BMI, smoking, BP, diabetes/IFG)**; `write_onboarding_field` with plausibility + verbal confirmation + provenance; unlock NAFLD-FS + SCORE2 educational estimate in the existing analytics layer.

**Phase 5 — On-device privacy tier + open-mic opt-in.** Apple SpeechAnalyzer/whisper.cpp + AVSpeechSynthesizer zero-egress tier; open-mic opt-in with adaptive barge-in; speculative-filler latency polish; audio-retention opt-in (default off).

---

## Open questions

1. **EU LLM default:** Vertex europe-west3 vs Claude-on-Bedrock eu-central-1 as the *primary* EU consult LLM — Claude's medical-reasoning quality vs keeping one LLM vendor across regions (Gemini/Vertex is mandatory for India anyway). Pick one default, keep the other as failover?
2. **Sarvam as sole India LLM** vs Sarvam STT/TTS + Gemini-asia-south1 LLM — Sarvam wins single-vendor-in-India simplicity and Indian-language depth; Gemini may win reasoning. Does Sarvam's BAA/DPDP + no-train posture fully match Vertex asia-south1's?
3. **Open-mic + barge-in robustness** across the AEC-variable iOS device fleet — is PTT-only acceptable for v1 of voice, deferring open-mic to Phase 5 until barge-in is proven?
4. **Audio retention:** do we ever retain raw audio (even opt-in) given it widens the erasure/breach surface, or is transcript-only a hard rule? Default is off; question is whether the opt-in path exists at all.
5. **On-device tier boundary:** which intents are "safe + simple enough" to answer fully on-device (zero egress) vs always requiring in-region cloud grounding? Likely only non-PHI/navigation turns stay local.
6. **Escalation script localization + legal sign-off** per region (India vs EU emergency guidance differs) — who owns the clinical/legal review of the fixed safety scripts?
7. **Code-switching language detection** confidence threshold before we trust STT enough to read back a value — what is the re-ask threshold, and does mixed Hindi-English degrade Sarvam parameter recognition below it?
8. **Session caps:** `max_session_sec=900` / `idle_timeout=45 s` are placeholders — tune against real consult lengths and per-minute cost.
9. **PROMIS/WHO-5 in voice:** should the daily WHO-5 check-in and PROMIS Global-10 be administerable *by voice* (accessibility win) or kept visual-only to avoid mis-scoring spoken responses?