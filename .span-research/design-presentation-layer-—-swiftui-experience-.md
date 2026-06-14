# Presentation Layer — SwiftUI experience + thinking-model (Opus) report generation for Span (longevity/health-awareness iOS app)

## Overview
The presentation layer turns Span's normalized per-measurement data (the existing flat Measurement/ParamCatalog schema in app/src/lib/health.ts, generalized multi-user) into a premium-but-restrained native SwiftUI experience plus an Opus-generated doctor-visit prep sheet. The governing rule everywhere: EDUCATIONAL — cite a tiered source on every claim, frame as "discuss with your clinician," never diagnose or prescribe doses, never make a single composite score the headline.

DECISION on the scoring/visual metaphor (the central question): we reject "one big number" as the home-screen headline. Per the research, single composite scores and "biological age" draw the heaviest clinician criticism (false precision, snapshot/daily-fluctuation problem, ~1/3 of one app's "biomarkers" were derived ratios, ~10 flagged abnormals had no clinical significance, supplement upsell). Instead the home screen is a grid of ORGAN-SYSTEM TILES driven by Attia's "Four Horsemen" buckets (ASCVD / Metabolic / plus Kidney, Liver, Hematologic/CBC, Thyroid, Nutrition, Inflammation), each tile carrying the SAME three-zone traffic-light metaphor (Red=outside clinical reference / Yellow=clinically normal / Green=evidence-based optimal, InsideTracker pattern) that the existing PWA already uses (FLAG_HSL: High/Low/Normal). PhenoAge "biological age" IS computed (it's defensible — 9 labs Span already stores, published formula, fact-check CONFIRMED) but is a SECONDARY, opt-in, clearly-bounded number behind a tap, shown only as a trend with an explicit "this fluctuates day to day / directional only" caption and natural-frequency framing — never used to recommend supplements. The whole-person header carries PROMIS Global-10's two normed T-scores (Global Physical Health, Global Mental Health) as labeled bands instead of a proprietary number, so population normalization does the interpretive work.

Five surfaces: (1) Whole-Person Overview (Today tab) — system tiles + two PROMIS bands + "needs attention" rail reusing the existing attentionParams logic; (2) Organ-System drill-down — Swift Charts trend with dual reference/optimal bands (the two-range-layer model from longevity research); (3) Daily QoL check-in — WHO-5 (5 items, free*, multilingual) as primary micro-survey, rotating PROMIS Fatigue 4a / Sleep Disturbance 4a, mapped against HealthKit sleep/HRV/steps and biomarkers; (4) Doctor-Visit Prep Sheet — Opus thinking model producing an AHRQ-style Question Prompt List + flagged trends + cited lifestyle/supplement suggestions with cite+defer, modeled directly on the existing Doctor_Visit_Prep.docx which is already the gold-standard tone reference; (5) span-consultant realtime voice entry point. A PAM-style 4-level activation model tiers how much detail/autonomy each surface reveals.

*Licensing caveats surfaced as open questions: WHO-5 is CC-BY-NC-SA (commercial use needs handling), EQ-5D/ESS/PAM are licensed — so we use WHO-5 + PROMIS (public-domain) as the spine and treat PAM as a "PAM-style" home-grown staged model, not the licensed instrument.

## Architecture
SCREEN-BY-SCREEN INFORMATION ARCHITECTURE (SwiftUI, iOS 17+, Observation framework, NavigationStack + type-safe Hashable route enum, Swift Charts).

Root = TabView with 4 tabs: [Today] [Systems] [Check-in] [Prep]. A persistent floating "Ask span" mic button (entry to voice consultant) sits above the tab bar on Today/Systems.

ROUTE ENUM (drives NavigationStack):
  enum Route: Hashable { case systemDetail(SystemKey), parameterDetail(paramID), prepSheet(reportID), checkinFlow(InstrumentID), bioAge, voiceConsultant, citation(sourceID) }

(1) TODAY / WHOLE-PERSON OVERVIEW  — the answer to "premium but NOT overwhelming"
  Layout top→bottom:
   a. Greeting + date. No giant score.
   b. TWO PROMIS bands (only if a Check-in exists): horizontal labeled band gauges for Global Physical Health and Global Mental Health T-scores. Band labels severe(<30)/moderate(30-40)/mild(40-45)/average(45-55)/above-average(>55); a dot marks the user. Caption: "Compared with the general population (50 = average). Based on your check-in on <date>." No decimal T-score shown by default (avoids false precision); tap reveals the number + "what this means."
   c. NEEDS-ATTENTION RAIL — reuses existing attentionParams(idx, allParams): horizontal chips of parameters whose LATEST reading is out of clinical range, colored by flag. "X markers to discuss with your clinician." Tapping a chip → parameterDetail. This is the existing PWA attention banner, restyled as a calm rail not an alarm.
   d. SYSTEM TILES (the headline metaphor) — a 2-col grid of 8 organ-system tiles. Each tile = system name + icon + a traffic-light status derived from its member parameters' latest flags (worst-of rule, but capped: a tile is Red only if ≥1 member is out of clinical range; "optimal/Green" only where a peer-reviewed optimal band exists, else max Yellow) + a 1-line plain-language summary + tiny Swift Charts sparkline of the system's "lead marker." Systems map to Attia Four Horsemen + Span categories: Heart & Arteries (Lipids+Inflammation→ASCVD, lead=ApoB/LDL), Metabolic (Diabetes, lead=HbA1c), Kidney, Liver, Blood & Immunity (CBC, lead=Hemoglobin/RDW), Thyroid, Nutrition (Vitamins+Minerals, lead=Vitamin D), Inflammation (CRP/ESR). Tap tile → systemDetail.
   e. Collapsed secondary row: "Your biological age trend (optional)" link → bioAge screen. Never above the fold; never a number on this screen.
   f. Persistent footer microcopy: "Educational only. Discuss any result with your clinician."

   ASCII:
   ┌─ Today ───────────────────────────────┐
   │ Good morning, Anoop      14 Jun 2026   │
   │ ┌Physical health ──●────┐ above avg    │
   │ ┌Mental health ────●──┐  average       │
   │ ⚑ 6 markers to discuss → [LDL][HbA1c]…│
   │ ┌──────────┐ ┌──────────┐             │
   │ │Heart&Art ●│ │Metabolic●│  (tiles)    │
   │ │ ApoB ⤴   │ │ HbA1c ⤳ │             │
   │ ├──────────┤ ├──────────┤             │
   │ │Kidney   ●│ │Liver    ●│             │
   │ │Blood    ●│ │Thyroid  ●│             │
   │ │Nutrition●│ │Inflamm. ●│             │
   │ └──────────┘ └──────────┘             │
   │ Biological age trend (optional) →      │
   │ Educational only · discuss w/ clinician│
   └──────────────────[ 🎙 Ask span ]──────┘

(2) SYSTEM DETAIL  (systemDetail)
   Header: system name + the Hallmark-of-Aging + Horseman it maps to ("Why this matters: chronic inflammation hallmark"). List of member parameters as rows: name, latest value+unit, traffic-light dot, mini-sparkline (reuse existing sparkPath/Sparkline), trend arrow (improving/worsening from slope). Tap row → parameterDetail. A "Compare in one chart" action (mirrors existing compareSet, overlays members). Bottom: "Discuss this system with your clinician" + optional "Ask span about my [system]" deep-links voice with context preloaded.

(3) PARAMETER DETAIL  (parameterDetail) — the Swift Charts centerpiece
   TrendChart (Swift Charts) over full 2001–2026 history on a real .dateTime axis:
     • RectangleMark/AreaMark yStart:ref_low yEnd:ref_high = CLINICAL reference band (gray/yellow).
     • Second RectangleMark = OPTIMAL/longevity band where one exists (e.g., ApoB<60, HbA1c<5.5, Vit D 40-60), tinted green, with a tap-through citation + evidence tier badge. Two-range-layer model.
     • LineMark value-vs-date; PointMark colored by flag (High=red/Low=blue/Normal=green, the existing FLAG_HSL palette ported to Color).
     • value==null rows = annotated symbol markers (don't break the line), matching existing behavior.
   Controls: weekly / 28-day / 1y / all windows (research says trend-vs-own-baseline is more honest than one-shot scores); baseline-first then population overlay toggle.
   Below chart: "How unusual is this?" card using NATURAL FREQUENCIES + icon array ("about 31 of 100 people your age/sex have a value this high") never a bare %. Reference range source + optimal-target source as tiered citations. Data table (reuse existing sortable table + CSV export). Footer cite+defer.

(4) CHECK-IN  (checkinFlow) — Daily QoL
   Card-stack of 5 WHO-5 items, 0–5 segmented controls, ~1 min. On submit: raw×4 → 0–100 well-being; store + show trend, NOT a verdict. If score ≤50 (raw<13), a soft non-modal nudge: "You might want to talk about how you've been feeling with a clinician" — never "depression," never a diagnosis. Rotation engine surfaces PROMIS Fatigue 4a / Sleep Disturbance 4a on a schedule, ESS occasionally. After submit, a "what your check-in lines up with" card correlates today's energy/sleep/mood against recent HealthKit sleep duration, sleep stages, HRV(SDNN), resting HR, steps — shown as gentle co-occurrence ("your lower energy days tend to follow shorter sleep"), explicitly NOT causal, never tying mood to a single lab as diagnosis.

(5) PREP  (prepSheet) — Opus-generated Doctor-Visit Prep Sheet
   "Generate prep sheet" CTA → async job → rendered scrollable sheet + share/print/PDF. Structure mirrors the existing Doctor_Visit_Prep.docx exactly (proven tone): (a) "Raise this first" single most-urgent trend; (b) "Key markers at a glance" status table; (c) "Questions to ask" grouped by system (AHRQ-style QPL); (d) "Lifestyle & supplements to discuss" table with Why/Caution/Verdict and citations; (e) coaching note ("bring this, tick the questions that matter, it's normal to feel a bit anxious writing these down") — the QPL-with-instructions requirement; (f) disclaimer. Every row cites a tiered source; supplements NEVER carry doses (locked stance); contested items (NMN, metformin-for-longevity, rapamycin) shown only with "no human outcome RCT / contested / discuss with clinician."

DATA FLOW:
  FastAPI backend (region-pinned Postgres + S3) → /presentation/* REST endpoints → SwiftUI @Observable view models (HealthStore, OverviewModel, PrepModel) → views. Computed features (PhenoAge, slopes, system roll-ups, optimal-band tier lookups, natural-frequency percentiles) are computed SERVER-SIDE in the Python analysis layer and delivered as ready-to-render DTOs, so the client never embeds medical logic/coefficients (auditable, single source of truth, in-region PHI). HealthKit metrics are read on-device, normalized to the same measurements pipeline as a 'device' lab source, POSTed to backend so QoL/longevity scoring sees lab+wearable uniformly. The Opus prep-sheet job runs server-side (PHI prompt stays in-region), output stored as a structured ReportJSON the SwiftUI sheet renders natively (not free HTML).

         HealthKit ─┐
  Labs/S3 ─ Postgres ─ Python analysis (PhenoAge, slopes, systems,
                        optimal-band tiers, nat-freq, Opus prep)
              │
        FastAPI /presentation/* (DTOs)
              │
   SwiftUI @Observable models → TabView → 5 surfaces
              │
        span-consultant (voice) ← shared context

## Data model
Generalizes the existing flat schema (Measurement/ParamCatalog in app/src/lib/health.ts) with multi-user tenancy + the presentation-specific computed entities. All PHI region-pinned (eu / ap-south-1), RLS by user_id.

CORE (carried from existing, multi-user):
  Measurement { id, user_id, report_id, date, parameter(canonical), parameter_raw, category, value:number?, value_text, unit, ref_low:number?, ref_high:number?, ref_text, flag:"High"|"Low"|"Normal"|null, lab, sources:[string] }
  ParameterCatalog { user_id, parameter, category, unit, count, numeric_count, first_date, last_date, latest_value, latest_value_text, ref_low, ref_high }

NEW — OPTIMAL/REFERENCE TIER TABLE (the two-range-layer model; global, not per-user):
  OptimalBand { parameter, unit, opt_low:number?, opt_high:number?, direction:"lower_better"|"higher_better"|"window", evidence_tier:1|2|3, source_id, label }
   e.g. ApoB {opt_high:60,direction:lower_better,tier:1,label:"longevity-optimized (discuss w/ clinician)"}; HbA1c{opt_high:5.5,tier:1}; VitaminD{opt_low:40,opt_high:60,tier:2}; ALT{opt_high:20,tier:2}; UricAcid{opt_high:5.0,tier:1}; Omega-3Index{opt_low:8,tier:1}.

NEW — SYSTEM ROLL-UP (organ-system view):
  SystemKey enum: heart_arteries, metabolic, kidney, liver, blood_immunity, thyroid, nutrition, inflammation
  SystemRollup { user_id, system, status:"red"|"yellow"|"green", lead_parameter, member_parameters:[paramID], plain_summary, hallmark:[string], horseman:string?, attention_count:int, sparkline_points:[{date,value}] }
   status rule: red if ≥1 member latest out of clinical range; green only if ALL members within an existing peer-reviewed optimal band; else yellow.

NEW — COMPUTED LONGEVITY FEATURES:
  BioAgeResult { user_id, method:"PhenoAge", as_of_date, value_years, chrono_age, delta_years, trend:[{date,value}], confidence_caption, source_id }  (PhenoAge formula CONFIRMED in fact-check; computed server-side only; never drives suggestions)
  ParameterStat { user_id, parameter, slope_per_year, direction:"improving"|"worsening"|"stable", percentile_by_age_sex:int, natural_freq:{count:int, denom:100, comparator_desc} }  (natural-frequency + icon-array source for "how unusual")

NEW — QoL / CHECK-IN:
  Instrument { id, name:"WHO-5"|"PROMIS-Fatigue-4a"|"PROMIS-SleepDisturbance-4a"|"ESS", items:[{key,prompt,scale}], scoring, license }
  CheckinResponse { id, user_id, instrument_id, datetime, raw_scores:[int], computed_score, computed_band, soft_flag:bool }
   WHO-5: computed_score = raw(0-25)*4 → 0-100; soft_flag = score<=50.
  PromisGlobalResult { user_id, datetime, gph_tscore, gph_band, gmh_tscore, gmh_band }  (bands: severe/moderate/mild/average/above-average from T-score, mean 50 SD 10)
  QoLBiomarkerLink { user_id, qol_domain:"energy"|"sleep"|"mood", correlated_metric, co_occurrence_note, causal:false }  (always non-causal)

NEW — PREP SHEET (the Opus output contract, stored structured not as prose):
  PrepReport {
    id, user_id, generated_at, model:"claude-opus", data_window:[date,date], measurement_count,
    raise_first: { title, narrative, parameters:[paramID], action_phrasing, citations:[sourceID] },
    glance_table:[ { parameter, latest_value, latest_date, target_or_ref, status:"High"|"Low"|"Normal", meaning, stale:bool } ],
    questions:[ { system_group, question_text, rationale_param:[paramID], priority:int } ],   // AHRQ-style QPL
    lifestyle_supplements:[ { item, why_from_data, caution, verdict:"discuss"|"reasonable"|"check_first"|"avoid_adding"|"unproven", evidence_tier:1|2|3, dose:null(LOCKED), citations:[sourceID] } ],
    coaching_note: string,   // QPL-with-instructions + "anxiety is normal"
    gaps_clinician_missed:[ { description, parameter:[paramID], citation } ],
    disclaimer: string
  }

CITATIONS (tiered, shared by every surface — the cite+defer backbone):
  Source { id, tier:1|2|3, kind:"guideline"|"peer_reviewed"|"expert_opinion"|"contested", title, citation_text, url, claim_supported, conflict_disclosure:string? }
   Tier1 = consensus/guideline (reference ranges, SCORE2, CKD-EPI); Tier2 = peer-reviewed optimal targets (PhenoAge, omega-3 index); Tier3 = expert/contested (Attia optimal bands labeled "expert opinion," NMN/metformin/rapamycin labeled "contested / no human RCT").
  CitationRef { source_id, displayed_inline:bool } attached to every PrepReport row, every OptimalBand, every suggestion.

PRESENTATION DTOs (what FastAPI returns to SwiftUI, already-computed):
  OverviewDTO { promis:{gph,gmh}?, attention:[{parameter,flag}], systems:[SystemRollup], bioage_available:bool }
  SystemDetailDTO { system, hallmark, horseman, members:[{parameter,latest,flag,slope,direction,sparkline}] }
  ParameterDetailDTO { parameter, points:[{date,value,flag,value_text}], ref_band, optimal_band, optimal_source, stat:ParameterStat, citations }
  ActivationState { user_id, pam_style_level:1|2|3|4 }  // tiers UI verbosity/autonomy

## APIs / interfaces
REST/JSON (FastAPI, versioned /v1), all PHI in-region, RLS by user_id. SwiftUI talks only to these; no medical computation client-side.

PRESENTATION ENDPOINTS:
  GET  /v1/overview                     → OverviewDTO (PROMIS bands, attention rail, 8 system tiles, bioage_available)
  GET  /v1/systems/{systemKey}          → SystemDetailDTO (members + hallmark/horseman mapping + slopes)
  GET  /v1/parameters/{paramId}         → ParameterDetailDTO (points, clinical ref band, optimal band + tiered source, natural-frequency stat)
  GET  /v1/parameters/{paramId}/trend?window=28d|1y|all&baseline=self|population
  GET  /v1/bioage                       → BioAgeResult (PhenoAge trend + uncertainty caption; opt-in)
  GET  /v1/citations/{sourceId}         → Source (tiered citation detail screen)

QoL / CHECK-IN:
  GET  /v1/checkin/next                 → which Instrument is due today (WHO-5 default; rotation logic)
  POST /v1/checkin/responses            → {instrument_id, raw_scores[]} ⇒ CheckinResponse (server computes score/band/soft_flag)
  GET  /v1/checkin/history?instrument=  → trend series + QoLBiomarkerLink co-occurrence notes
  GET  /v1/promis/global                → latest PromisGlobalResult (the two header bands)

DOCTOR-VISIT PREP (async, Opus thinking model):
  POST /v1/prep/generate                → 202 {job_id}    (kicks server-side Opus job; PHI stays in-region)
  GET  /v1/prep/jobs/{job_id}           → {status, report_id?}
  GET  /v1/prep/reports/{report_id}     → PrepReport (structured JSON the SwiftUI sheet renders natively)
  GET  /v1/prep/reports/{report_id}/pdf → rendered PDF for share/print

VOICE:
  POST /v1/voice/session                → ephemeral token + context bundle (current system/param if deep-linked) for span-consultant realtime session

══════════ LLM CONTRACT — DOCTOR-VISIT PREP SHEET (Opus / thinking model) ══════════
System role: "You are Span's clinical-context summarizer. You are NOT a doctor. You produce an EDUCATIONAL preparation sheet to help a person get more from a clinician visit. You NEVER diagnose, NEVER prescribe or suggest doses, NEVER tell the user to start/stop a medication on their own. Every factual claim and every suggestion MUST carry a citation id from the provided sources list and MUST defer to the clinician. Use natural frequencies, never bare percentages. Output ONLY valid JSON matching the PrepReport schema."

INPUT CONTEXT (assembled server-side, in-region, before the call):
  • user_profile: { age, sex, chronic_conditions:[...](e.g. 'insulin-deficient diabetes 25y'), on_supplements:[...] }   — lets the model frame ASCVD risk correctly for a diabetic, flag already-high B12, etc.
  • out_of_range: latest flagged parameters with value, ref range, flag
  • trends: per-parameter slope + recent series for markers that are moving fast (e.g. LDL 88→129→136→157→196) — precomputed, model does NOT do math
  • optimal_gaps: parameters within clinical range but outside an evidence-tiered optimal band (with the source + tier)
  • gaps_clinician_likely_missed: e.g. "ApoB stale since Jan 2024 despite LDL surge"; "ACR only measured 3x ever" — derived by analysis layer
  • allowed_sources: the full tiered Source list the model may cite (model may NOT invent citations)
  • locked_rules: {no_doses:true, contested_items_require_contested_framing:true, every_row_needs_citation:true}

OUTPUT (PrepReport JSON — see data_model): raise_first, glance_table, questions(AHRQ QPL grouped by system, prioritized), lifestyle_supplements(Why/Caution/Verdict, dose=null always, tier+citations), gaps_clinician_missed, coaching_note, disclaimer.

GUARDRAILS (enforced in code AFTER the model returns, not trusted to prompt alone):
  1. Schema-validate; reject if any suggestion has a non-null dose field → regenerate.
  2. Every glance_table/questions/lifestyle row must reference ≥1 source_id from allowed_sources; strip+flag any uncited claim.
  3. Tier-3/contested items must contain the contested framing string or are downgraded to "unproven / discuss."
  4. Banned-phrase filter: "you have [disease]", "take X mg", "stop your medication", "this is normal/nothing to worry about", "diagnosis." 
  5. Mandatory disclaimer block appended server-side (not model-generated) — identical to existing docx disclaimer.
  6. Model temperature low; thinking budget high (it's the reasoning surface). On any guardrail failure, one auto-retry, then human-review queue, never silent publish.

══════════ LLM CONTRACT — span-consultant (realtime voice) handoff ══════════
The voice bot receives the SAME tiered sources + current screen context; system prompt enforces identical cite+defer + no-dose + educational stance; it can read the user's flagged markers and system rollups but answers only with "discuss with your clinician" framing and surfaces citations verbally ("according to a peer-reviewed reference range…"). Detailed voice-vendor/residency design is owned by the ios-architecture workstream (Deepgram self-host ap-south-1 / OpenAI Realtime EU); this layer only defines the context bundle + guardrail parity.

## Tech choices
- SwiftUI native, iOS 17+ on the Observation framework (@Observable OverviewModel/PrepModel/HealthStore, @State ownership, @Environment injection) — matches the locked client decision and the ios-architecture research; no medical logic in the client.
- Swift Charts for all trends (replaces the PWA's Chart.js) — natively supports the exact reference-band pattern via RectangleMark/AreaMark for ref_low→ref_high PLUS a second RectangleMark for the optimal band, LineMark + flag-colored PointMark; ports the existing FLAG_HSL palette and value==null annotation behavior.
- System tiles (Attia Four-Horsemen organ buckets) as the home metaphor, NOT a single score — directly answers the research's strongest warning that composite scores/biological-age are the most-criticized, false-precision elements; keeps the proven three-zone traffic light the existing PWA already uses.
- PROMIS Global-10 two T-score bands for the whole-person header — population-normed (mean 50, SD 10) so normalization does the interpretive work; avoids inventing a proprietary number; public-domain (no license fee unlike EQ-5D).
- WHO-5 as the daily QoL spine (5 items, ~1 min, multilingual, validated, raw×4→0–100) with PROMIS Fatigue 4a / Sleep Disturbance 4a rotation — best-fit per research; soft ≤50 nudge framed as 'discuss your mood,' never a depression diagnosis.
- PhenoAge as the ONLY biological-age feature, computed server-side from 9 labs Span already stores (formula fact-check CONFIRMED), shown opt-in/secondary with an uncertainty + 'fluctuates day to day' caption — defensible, never headline, never drives supplement suggestions.
- Two-range-layer encoding per parameter (clinical ref band + evidence-tiered optimal band) with every optimal target tagged tier 1/2/3 + a citeable Source — implements 'reference range vs longevity-optimized target (discuss with clinician)' and the cite-everywhere stance.
- Claude Opus (thinking model) for the prep sheet, run server-side on a structured PrepReport JSON contract with post-generation guardrails (schema + citation + no-dose + banned-phrase filters) — keeps PHI prompt in-region, makes output auditable and renderable natively rather than trusting free-text.
- AHRQ-style Question Prompt List delivered WITH a coaching note ('tick what matters; feeling a bit anxious writing these is normal') — research shows QPLs only move question-asking/decision self-efficacy when paired with instructions, and must be framed as activation not prognosis.
- Natural frequencies + Swift Charts icon arrays for every 'how unusual is this / mortality-longevity' figure ('about 31 of 100 people like you…'), never bare percentages — Gigerenzer evidence; serves GDPR/DPDP non-deceptive educational framing.
- PAM-style 4-level activation model (home-grown, not the licensed PAM-13) to tier UI verbosity/autonomy — validated engagement→shared-decision pathway, avoids Insignia licensing.
- Server-computed presentation DTOs (FastAPI) — PhenoAge, slopes, system roll-ups, percentiles, optimal-band lookups all in the Python analysis layer; single auditable source of truth, in-region PHI, thin client. Residency note: all PHI endpoints + Opus prompts region-pinned (eu / ap-south-1 Mumbai), citations/optimal-band tables are non-PHI and global.

## Risks
- False-precision/over-flagging: if the system-tile worst-of rule or the optimal bands flag too aggressively, Span reproduces exactly the Superpower/Function criticism (~10 abnormals of no clinical significance). Mitigation: tile is Red only on a real out-of-clinical-range member; 'optimal/Green' only where a peer-reviewed band exists; derived ratios are de-emphasized; natural-frequency context on every 'unusual' value.
- Biological-age misuse: users (or screenshots) treating PhenoAge as a verdict despite the snapshot/daily-fluctuation problem. Mitigation: opt-in, secondary, never headline, never feeds suggestions, mandatory uncertainty + 'fluctuates day to day' caption, shown only as a trend.
- Opus prep-sheet hallucination — inventing a citation, a dose, a diagnosis, or an uncited optimal target. Mitigation: model may only cite from an allowed_sources list; post-gen schema + citation + no-dose + banned-phrase guardrails with auto-retry then human-review; disclaimer appended in code not by the model.
- QPL transient anxiety: research shows writing questions can raise anxiety ~1 week out and does NOT improve hard outcomes. Mitigation: frame prep as activation/'getting more from your visit,' include the 'feeling anxious is normal' coaching note, never imply prognosis change.
- QoL→biomarker over-reach: implying mood/energy maps causally to a lab (e.g., 'low mood = thyroid'). Mitigation: co-occurrence notes only, explicitly non-causal, WHO-5 soft flag says 'discuss with a clinician,' never names a condition.
- Instrument licensing: WHO-5 is CC-BY-NC-SA (commercial handling needed); EQ-5D, ESS, PAM-13 are licensed/paid. Mitigation: spine = WHO-5 + PROMIS (public domain), 'PAM-style' not PAM-13, EQ-5D excluded for v1; clear licensing in open questions.
- Fact-check corrections to honor: WHO-5 14-day recall shortened for daily use voids strict validation (label as product modification); WHO-5 sens/spec is ~0.86/0.81 (Topp 2015) not 0.87/0.76; PROMIS '40=mild/30=severe' are interpretive labels; FIB-4 needs cutoff 2.0 over age 65; Attia optimal bands are expert opinion (tier 3), not guideline. Mitigation: encode exact corrected values/tiers in OptimalBand + Source tables.
- Background HealthKit unreliability means QoL↔wearable correlations may show stale/missing data. Mitigation: foreground catch-up sync, tolerate empty results, never assert a correlation on sparse data.
- Cross-domain color reuse (same traffic light for biomarkers, QoL, risk) is a sensible design hypothesis but NOT validated science per fact-check; per-parameter semantics (which direction is 'bad') must be explicit so green/red aren't misread.
- Tile roll-up hides nuance: a 'green' system could still contain one stale/never-tested critical marker (e.g., ApoB). Mitigation: surface 'gaps_clinician_likely_missed' (stale/never-measured) in prep sheet and as a subtle tile annotation.

## Phased build
- M1 — Port the proven core to SwiftUI: TabView shell + NavigationStack route enum; Parameter Detail with Swift Charts TrendChart (clinical reference band + flag-colored points + value==null markers + data table/CSV), reading the generalized Measurement schema via /v1/parameters. This is a faithful, shippable native port of the existing PWA's strongest feature.
- M2 — Whole-Person Overview: 8 organ-system tiles (Four-Horsemen mapping) with traffic-light status + sparklines + needs-attention rail (reusing attentionParams logic) via /v1/overview and /v1/systems. No score headline. Establishes the core metaphor end-to-end.
- M3 — Two-range-layer + optimal bands: add the OptimalBand + tiered Source tables, render the second (green) optimal band + 'reference vs longevity-optimized (discuss with clinician)' citation chips on Parameter Detail; natural-frequency 'how unusual' card with icon array. Cite+defer becomes visible everywhere.
- M4 — Daily QoL check-in: WHO-5 flow (raw×4→0–100, soft ≤50 nudge), PROMIS Global-10 two-band header on Today, Fatigue/Sleep rotation, and gentle non-causal QoL↔HealthKit co-occurrence card.
- M5 — Doctor-Visit Prep Sheet: server-side Opus job on the PrepReport JSON contract + full guardrail stack (schema/citation/no-dose/banned-phrase/disclaimer), native sheet rendering modeled on the existing Doctor_Visit_Prep.docx, AHRQ QPL + coaching note, PDF/share export.
- M6 — Biological-age (opt-in) + activation tiering: PhenoAge trend screen with uncertainty caption (secondary, never headline); PAM-style 4-level model that tunes verbosity/autonomy across all surfaces.
- M7 — span-consultant entry point: floating mic, context-bundle handoff (current system/param + flagged markers + allowed sources) with cite+defer guardrail parity; deep-links from System Detail ('Ask span about my [system]'). Realtime vendor/residency wiring handed to the ios-architecture workstream.

## Open questions
- Licensing: confirm WHO-5 commercial-use handling under CC-BY-NC-SA-IGO, and whether to license PROMIS-style scoring services or self-score; ESS and EQ-5D are paid — confirm they stay out of v1. PAM-13 is proprietary (Insignia) — confirm 'PAM-style' home-grown leveling is acceptable.
- Does the user model store self-reported chronic conditions and current medications/supplements? The prep sheet quality (e.g., 'B12 already high, do NOT add more'; framing ASCVD for a 25-yr diabetic) depends on this context; how is it captured and consented?
- Population reference for natural-frequency percentiles + PhenoAge norms: NHANES is US-derived. For EU+India residents, which reference cohort do we use, and how do we caption that the percentile/biological-age may not be calibrated for an Indian population (cf. SCORE2/PCE not calibrated for India)?
- How aggressively should the optimal/Green band appear given most parameters lack a peer-reviewed optimal target? Need a curated, signed-off OptimalBand table (which parameters get tier-1/2/3 bands) before M3 — who is the clinical reviewer?
- Who staffs the human-review queue for prep sheets that fail guardrails, and what is the SLA before a user sees their requested sheet?
- Should the daily WHO-5 use the validated 14-day recall (and thus be weekly, not daily) or a shortened recall (daily but non-validated)? This is a product-vs-rigor tradeoff to decide explicitly.
- Tile roll-up rule edge cases: how to weight a single critical stale marker (e.g., ApoB never re-tested) in a system that is otherwise green — surface as amber annotation vs separate 'gaps' surface?
- Activation-level detection: how do we infer PAM-style level 1–4 without administering the licensed PAM-13 — behavioral proxies (engagement, question-asking) need definition and validation.
