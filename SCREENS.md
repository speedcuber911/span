# Span — Screen Specification Document

**Version:** 1.0 — 2026-06-14
**Status:** Implementation-ready spec. Visual designs to be attached by founder (see `[DESIGN: …]` blocks in each section).
**Target platform:** iOS 17+, native SwiftUI, India-only users, Sign in with Apple.
**Author of this doc:** Produced from SPAN_MASTER_PLAN.md + design-presentation-layer research file.

---

## Purpose of This Document

This file is the single source of truth for every screen Span ships. It is written for iOS engineers and designers — concrete enough to implement without additional clarification, but leaving designated `[DESIGN: …]` placeholder blocks where the founder will attach visual comps.

This is a **specification, not code.** No Swift appears here. Every decision documented here derives from the locked founder decisions in SPAN_MASTER_PLAN.md §11 and the phased build plan in §10.

### Core product stance (repeated on every screen)

1. **Never a single composite score as the headline.** The home screen is organ-system tiles, not a number.
2. **Three-zone traffic light, consistently.** Red = outside clinical reference range / Yellow = inside clinical normal but outside evidence-based optimal / Green = inside peer-reviewed optimal. Green is only shown where a cited optimal band actually exists.
3. **Educational cite-and-defer tone.** Every risk figure uses natural frequencies ("about 31 of 100 people like you…"), never bare percentages. Every claim cites a tiered source. Every screen carries the footer: *"Educational only · discuss any result with your clinician."*
4. **No diagnoses, no doses.** The app never names a disease for the user, never suggests a dose, never tells the user to start or stop a medication.
5. **Biological age (PhenoAge) is secondary and opt-in.** Never above the fold. Always shown as a trend with a "directional only, fluctuates day to day" caption.

---

## Screens Index

| # | Screen | Primary API Endpoint | Milestone |
|---|--------|---------------------|-----------|
| 1 | Sign In with Apple | `POST /v1/auth/apple` | M0 |
| 2 | Onboarding — Consent (DPDP + Educational Disclaimer) | `POST /v1/consents` | M0 |
| 3 | Onboarding — Profile Capture (step 1: demographics) | `PUT /v1/profiles` | M0 |
| 4 | Onboarding — Profile Capture (step 2: clinical flags) | `PUT /v1/profiles` | M0 |
| 5 | Onboarding — Profile Capture (step 3: conditions / meds / goals) | `PUT /v1/profiles` | M0 |
| 6 | Onboarding — First Upload Prompt | `POST /v1/ingestion/intents` | M1 |
| 7 | Today / Whole-Person Overview (home tab) | `GET /v1/overview` | M3 |
| 8 | Systems Tab (list of 8 organ systems) | `GET /v1/overview` | M3 |
| 9 | System Detail | `GET /v1/systems/{key}` | M3 |
| 10 | Parameter Detail (Swift Charts centerpiece) | `GET /v1/parameters/{id}` + `/trend` | M3 |
| 11 | Ingestion / Upload | `POST /v1/ingestion/intents` + `GET /v1/ingestion/jobs` | M1 |
| 12 | Ingestion — User Self-Confirm Review | `POST /v1/ingestion/{job_id}/review` | M1 |
| 13 | Check-In (daily QoL) | `GET /v1/checkin/next` + `POST /v1/checkin/responses` | M4 |
| 14 | Doctor-Visit Prep Sheet | `POST /v1/prep/generate` + `GET /v1/prep/reports/{id}` | M5 |
| 15 | Biological Age (opt-in, secondary) | `GET /v1/bioage` | M6 |
| 16 | Span-Consultant (voice) | `POST /v1/voice/session` | M6 |
| 17 | Settings / Account | `GET /v1/account` + `DELETE /v1/account` | M0 |
| 18 | Citation Detail (modal/sheet) | `GET /v1/citations/{id}` | M3 |

---

## Global UI Conventions

### Navigation Model

Root is a `TabView` with four persistent tabs:

```
[ Today ]  [ Systems ]  [ Check-in ]  [ Prep ]
```

A floating **"Ask Span" mic button** sits above the tab bar on the Today and Systems tabs. It is a circular pill/button, not a tab item. It launches the Span-Consultant screen as a full-screen modal.

All drill-down navigation uses `NavigationStack` with a type-safe `Route` enum. The enum covers: `systemDetail(SystemKey)`, `parameterDetail(paramID)`, `prepSheet(reportID)`, `checkinFlow(instrumentID)`, `bioAge`, `voiceConsultant`, `citation(sourceID)`, `ingestionReview(jobID)`.

### Color Semantics

**Flag colors** (for individual measurements, direct from the lab flag):
- `High` → Red (`#D93025` or semantic equivalent)
- `Low` → Blue (`#1A73E8` or semantic equivalent)
- `Normal` → Green (`#34A853` or semantic equivalent)

**Three-zone traffic light** (for organ-system tiles and trend bands):
- `Red / attention` — at least one member parameter is **outside the clinical reference range**
- `Yellow / monitor` — all parameters within clinical normal, but at least one is **outside the peer-reviewed optimal band**
- `Green / on_track` — all measured parameters are **inside the optimal band** (only shown where a cited optimal band exists)
- `Gray / not_enough_data` — fewer than the minimum measured parameters for a verdict

The two color systems (flag colors and zone colors) are semantically distinct. Flag colors operate per measurement point. Zone colors operate at the system-tile level and the trend-band level. Engineers must not conflate them.

**Optimal band tint:** A secondary, lighter green (e.g., `#E6F4EA` fill with `#34A853` border) marks the optimal zone in charts, visually distinct from the clinical reference band (gray/off-white fill).

### Typography Intent

Premium restraint: one variable-weight sans-serif family (SF Pro). Use Dynamic Type exclusively — no hardcoded point sizes. Key hierarchy:

- Screen titles: `.title2`, weight `.semibold`
- Section headers: `.headline`, weight `.medium`
- Body copy: `.body`, weight `.regular`
- Footnotes / disclaimers: `.footnote`, weight `.regular`, color `.secondary`
- Data values (lab values, scores): `.title3` or `.largeTitle` (context-dependent), weight `.bold`
- Citation chips: `.caption2`, weight `.medium`, rounded background

### Persistent Footer

Every content screen carries a non-interactive text row at the very bottom of the scroll view (not the tab bar area):

```
Educational only · discuss any result with your clinician.
```

Font: `.footnote`, color: `.secondary`, centered. This copy is appended in code on every screen — it is not generated by any AI model.

### Floating "Ask Span" Mic Entry Point

Displayed above the tab bar on the Today and Systems tabs. Implementation note: position as a floating button using `.overlay` or a custom `ZStack` arrangement; it must not block tab bar touch targets.

Visual: a pill-shaped button with a microphone SF Symbol + "Ask Span" label. Tapping launches the voice consultant screen as a `.fullScreenCover`.

### Accessibility

- **VoiceOver:** Every interactive element has a meaningful `.accessibilityLabel`. Chart marks carry `.accessibilityValue` with the numeric reading and its interpretation (e.g., "HbA1c 6.2, flagged High"). Traffic-light dots carry both color and text label (never color-only communication).
- **Dynamic Type:** All text scales. Charts scale their axis labels. System tiles reflow to a single column when text is extra-large.
- **Captions:** All voice output in the Span-Consultant screen is simultaneously rendered as live captions. The text-chat fallback is the primary accessibility backstop for users who cannot or prefer not to use voice.
- **Reduced Motion:** Sparklines and trend animations respect `@Environment(\.accessibilityReduceMotion)`.
- **Minimum touch targets:** 44×44 pt for all interactive elements per Apple HIG.

---

## Screen 1 — Sign In with Apple

### Purpose

The sole entry point to the app. Span requires Sign in with Apple per App Store rule 4.8 (any app collecting personal data must offer SiwA if it offers any other login). There is no username/password option.

### What the User Sees

A full-screen view with the Span wordmark or logomark, a brief one-line value proposition, and the standard Sign in with Apple button. No email or password fields. No other login options.

```
┌─────────────────────────────────────┐
│                                     │
│           [Span Wordmark]           │
│                                     │
│     Your health data, clearly.      │
│     Understand trends. Prepare      │
│     for your next visit.            │
│                                     │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Sign in with Apple       │   │
│   └─────────────────────────────┘   │
│                                     │
│  By signing in you agree to our     │
│  Terms of Service and Privacy       │
│  Policy (links).                    │
│                                     │
│  India only · Data stored in India  │
└─────────────────────────────────────┘
```

### Data

- Sends Apple's `identityToken` + `authorizationCode` + `nonce` to `POST /v1/auth/apple`
- Server returns a Span access token + refresh token (our own JWTs, KMS-signed)
- No Apple token is stored on device or on the server after bootstrap

### Interactions / Navigation

- Sign in with Apple button → native Apple auth sheet → on success → server call → on first login → Onboarding Screen 2 (Consent)
- On returning login → Today tab (if profile complete and consent active)
- On returning login with incomplete profile → resume onboarding at the last incomplete step

### Empty / Loading / Error States

- Loading: a subtle activity indicator replaces the button after tap
- Network error: inline error message below the button; the button re-enables
- Apple sign-in cancelled: silently returns to the initial state; no error shown
- Server error on token exchange: "Something went wrong. Please try again." with a retry button

### Edge Cases

- Apple private email relay: server stores only the stable `apple_sub`; email is not required
- User has previously deleted their account (tombstone exists): server returns 410, app shows "Your account has been deleted. Sign up for a new account?" prompt

---

`[DESIGN: Screen 1 — Sign In with Apple — to be attached]`

---

## Screen 2 — Onboarding: Consent (DPDP + Educational Disclaimer)

### Purpose

Captures lawful basis for processing PHI under India's DPDP Act and the EU AI Act educational disclaimer before any data is stored. This screen is mandatory and cannot be skipped. Per DPDP, consent must be explicit, granular, and withdrawable; per App Store 5.1.1, the user must be informed before any data collection.

### What the User Sees

A scrollable consent screen with two clearly separated sections:

1. **DPDP Data Consent** — explains what data is collected (lab reports, derived measurements, profile data), why (health tracking and personalized insights), where it is stored (India servers only, ap-south-1), and how long (until deletion). Each scope is separately grantable with a toggle:
   - Ingestion & storage of lab reports
   - Processing reports to extract measurements
   - Storing your profile (age, sex, health conditions)
   - Generating a doctor-visit prep sheet
   - [Shown at voice setup, not here] Voice session transcript

2. **Educational Disclaimer (standalone, scroll-to-bottom enforced)** — states that Span is not a medical device, does not diagnose, does not prescribe, and that all results must be discussed with a qualified clinician. User must actively tap "I understand" — passive scroll is not sufficient.

```
┌─────────────────────────────────────┐
│ ← Back       Your data & consent    │
├─────────────────────────────────────┤
│ How Span uses your data             │
│                                     │
│ Span stores your lab reports and    │
│ the measurements extracted from     │
│ them on servers in India.           │
│                                     │
│ ─── What we collect ─────────────── │
│ ○ Lab reports & extracted data   [✓]│
│   Purpose: show you trends          │
│   Stored: India (ap-south-1)        │
│                                     │
│ ○ Profile (age, sex, conditions) [✓]│
│   Purpose: personalize insights     │
│                                     │
│ ○ Doctor-visit prep sheet        [✓]│
│   Purpose: prepare you for visits   │
│                                     │
│ You can withdraw any consent at     │
│ any time in Settings.               │
│                                     │
│ ─── Educational disclaimer ───────── │
│ Span is not a medical device. It    │
│ does not diagnose. All results are  │
│ educational and must be discussed   │
│ with a qualified clinician.         │
│                                     │
│   [I understand — continue →]       │
└─────────────────────────────────────┘
```

### Data

- `POST /v1/consents` — one row per scope, with `policy_version`, `ip_at_grant`, `granted_at`, `method='explicit_tap'`, and the full consent copy text hash (`evidence_blob`)
- The app must send the exact consent copy hash it displayed; the server records it for audit

### Interactions / Navigation

- All scopes must be granted to proceed (Span cannot function without the base ingestion + processing consent)
- "I understand" button is only active after scrolling to the bottom of the disclaimer section
- Tapping "I understand" → Profile Capture Step 1
- Back button returns to Sign In

### Empty / Loading / Error States

- If the server fails to record consent: do not proceed; show "Unable to save your consent. Please check your connection and try again." No data is processed before consent is persisted.
- Policy version mismatch (returning user, updated terms): show a "We've updated our terms" banner; require re-consent of changed scopes only

### Edge Cases

- User toggles off all scopes: disable "continue" button; show "Span requires your consent to process lab reports. You can delete your account at any time in Settings."
- Returning user who previously consented to all scopes: this screen is skipped unless the policy version has changed

---

`[DESIGN: Screen 2 — Onboarding Consent — to be attached]`

---

## Screen 3 — Onboarding: Profile Capture Step 1 (Demographics)

### Purpose

Collects age/DOB, biological sex, height, and weight. These fields directly unlock medical scoring: height + weight → BMI (stored, not recalculated on client), sex + DOB → age-adjusted CKD-EPI eGFR, PhenoAge, and FIB-4 cutoff.

### What the User Sees

A focused form, one question group per card, with a progress indicator at the top (Step 1 of 3).

```
┌─────────────────────────────────────┐
│ ●──○──○   Step 1 of 3               │
│                                     │
│ Tell us about yourself              │
│ This lets us apply the right        │
│ reference ranges for your age       │
│ and sex.                            │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Date of birth                   │ │
│ │ [  DD  ] / [  MM  ] / [ YYYY ] │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Biological sex                  │ │
│ │ ○ Male   ○ Female               │ │
│ │ (used only for reference ranges)│ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Height        Weight            │ │
│ │ [___] cm      [___] kg          │ │
│ │         BMI: — (calculated)     │ │
│ └─────────────────────────────────┘ │
│                                     │
│           [Continue →]              │
│      Skip for now (some scores      │
│      won't be available)            │
└─────────────────────────────────────┘
```

### Data

- `PUT /v1/profiles` with `dob`, `sex`, `height_cm`, `weight_kg`
- Server computes and stores `bmi` (not client-side)
- Triggers recompute of eGFR, PhenoAge, FIB-4 age cutoff, NAFLD-FS (once other fields present)

### Interactions / Navigation

- BMI auto-displays once height + weight entered; label reads "BMI: 23.4 (calculated)" — informational only
- "Continue" → Step 2 (Clinical Flags)
- "Skip for now" → Step 2 with a persistent banner: "Some scores unavailable — complete your profile to unlock them"
- Sex picker: "Male" / "Female" with a footnote: "Used only to apply sex-specific reference ranges. Not used for any other purpose."

### Empty / Loading / Error States

- DOB validation: must be 18+ years; values outside 18–110 show inline error
- Height/weight plausibility: values outside 100–250 cm or 20–300 kg show inline warning (not blocking, user can proceed)

---

`[DESIGN: Screen 3 — Onboarding Profile Step 1 (Demographics) — to be attached]`

---

## Screen 4 — Onboarding: Profile Capture Step 2 (Clinical Flags)

### Purpose

Captures the clinical inputs that gate the NAFLD Fibrosis Score and the cardiovascular risk estimate: smoking status, blood pressure (systolic), whether the user is on BP treatment, and diabetes/IFG status. These are model inputs, not diagnoses.

### What the User Sees

Step 2 of 3, same card-per-question layout.

```
┌─────────────────────────────────────┐
│ ○──●──○   Step 2 of 3               │
│                                     │
│ A few clinical details              │
│ These unlock additional risk        │
│ estimates. All are optional.        │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Smoking status                  │ │
│ │ ○ Never smoked                  │ │
│ │ ○ Former smoker                 │ │
│ │ ○ Current smoker                │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Usual blood pressure (systolic) │ │
│ │ [___] mmHg  (top number)        │ │
│ │ ○ I take blood pressure meds    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Diabetes / blood sugar status   │ │
│ │ ○ No known issue                │ │
│ │ ○ Impaired fasting glucose (IFG)│ │
│ │ ○ Type 2 diabetes               │ │
│ │ ○ Type 1 diabetes               │ │
│ └─────────────────────────────────┘ │
│                                     │
│           [Continue →]              │
│      Skip for now                   │
└─────────────────────────────────────┘
```

### Data

- `PUT /v1/profiles` with `smoking_status`, `bp_systolic`, `bp_treated` (bool), `diabetes_status`
- Unlocks: `diabetes_status` + `bmi` → NAFLD-FS computable flag; `smoking_status` + `bp_systolic` + `bp_treated` + `diabetes_status` → CV risk estimate (with not-calibrated-India caveat) computable flag
- Server-side plausibility: bp_systolic 60–250 mmHg; values outside → store with a `field_confidence` caveat, not rejected

### Interactions / Navigation

- "I take blood pressure meds" checkbox appears inline below the BP field
- All fields optional; skipping means those scores show "Add profile details to unlock" in the relevant screens
- Continue → Step 3

---

`[DESIGN: Screen 4 — Onboarding Profile Step 2 (Clinical Flags) — to be attached]`

---

## Screen 5 — Onboarding: Profile Capture Step 3 (Conditions, Meds/Supplements, Goals)

### Purpose

Captures chronic conditions, current medications and supplements (names only, never doses), and the user's health goals. This context is used by the prep-sheet generator and the voice consultant to frame suggestions correctly (e.g., "B12 already high — do not add more").

### What the User Sees

Step 3 of 3.

```
┌─────────────────────────────────────┐
│ ○──○──●   Step 3 of 3               │
│                                     │
│ Your health context                 │
│ Helps us tailor your prep sheet.    │
│ All optional.                       │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Chronic conditions              │ │
│ │ (tap to add)                    │ │
│ │ [+ Hypertension] [+ Type 2 DM]  │ │
│ │ [+ Hypothyroidism] [+ Add…]     │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Current medications             │ │
│ │ Name only — no doses needed.    │ │
│ │ [Metformin ×]  [Atorvastatin ×] │ │
│ │ [+ Add medication]              │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Supplements you currently take  │ │
│ │ Name only — no doses needed.    │ │
│ │ [Vitamin D ×]  [Omega-3 ×]     │ │
│ │ [+ Add supplement]              │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ What are you most focused on?   │ │
│ │ ○ Understanding my lab trends   │ │
│ │ ○ Preparing for a doctor visit  │ │
│ │ ○ Tracking my metabolic health  │ │
│ │ ○ Longevity / healthy ageing    │ │
│ └─────────────────────────────────┘ │
│                                     │
│        [Complete profile →]         │
└─────────────────────────────────────┘
```

### Data

- `PUT /v1/profiles` with `chronic_conditions: string[]`, `current_supplements: string[]` (names only; no dose field exists in the schema)
- A separate `current_medications: string[]` field (names only) may be stored under the same profile record or a dedicated medications table — spec the exact schema as part of M0
- Goals are stored as a `user_goals: string[]` preference field and influence home-screen ordering only; they are not PHI in the medical sense but are stored as profile data under consent

### Interactions / Navigation

- Chronic conditions: a predefined chip list (Hypertension, Type 2 Diabetes, Hypothyroidism, PCOS, Coronary artery disease, CKD, Other) plus a free-text "Add other" field
- Meds and supplements: free-text input with type-ahead suggestions (non-PHI drug name dictionary); the input never asks for dose or frequency
- "Complete profile" → First Upload Prompt (Screen 6)

---

`[DESIGN: Screen 5 — Onboarding Profile Step 3 (Conditions / Meds / Goals) — to be attached]`

---

## Screen 6 — Onboarding: First Upload Prompt

### Purpose

Immediately after profile capture, prompt the user to upload their first lab report. This is the moment of highest motivation. Empty states throughout the app all deep-link back here.

### What the User Sees

A welcoming, low-friction nudge — not a wall of text. Two primary CTAs: upload a file or take a photo. A third "I'll do this later" option.

```
┌─────────────────────────────────────┐
│                                     │
│   🗂  Your profile is set up.        │
│                                     │
│   Add your first lab report         │
│   to see your health trends.        │
│                                     │
│   Span reads PDFs, photos of        │
│   lab printouts, and scanned        │
│   reports from any Indian lab.      │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │  📁  Upload from Files / Drive  │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │  📷  Scan a paper report        │ │
│ └─────────────────────────────────┘ │
│                                     │
│        I'll do this later →         │
│                                     │
│ Reports are stored securely in      │
│ India and are only used to          │
│ generate your health trends.        │
└─────────────────────────────────────┘
```

### Data

- "Upload from Files" → launches native document picker → follows the Ingestion flow (Screen 11)
- "Scan a paper report" → launches VisionKit document camera → follows the Ingestion flow (Screen 11)
- "I'll do this later" → navigates to Today tab (which will show the empty state with an "Add your first report" prompt)

### Edge Cases

- If consent for ingestion is not yet confirmed (edge case: user navigated back), redirect to consent screen before allowing any upload
- If a user arrives here from the Today tab empty state, the "I'll do this later" option is replaced with "Go to Today →"

---

`[DESIGN: Screen 6 — First Upload Prompt — to be attached]`

---

## Screen 7 — Today / Whole-Person Overview (Home Tab)

### Purpose

The home screen. Answers: "How am I doing overall, right now?" without a single composite number. The central metaphor is organ-system tiles — each one tells a story, none of them are a verdict.

### What the User Sees

A scrollable, vertical layout. No tab bar title ("Today" lives in the content, not a navigation bar title).

```
┌─────────────────────────────────────┐
│  Good morning, Anoop   14 Jun 2026  │
├─────────────────────────────────────┤
│ How you're feeling  (if check-in    │
│ exists for today or past 7d)        │
│                                     │
│ Physical health                     │
│ ├──────────────●────────────┤       │
│ Severe  Moderate  Avg  Above avg    │
│ "Above average compared to the      │
│  general population."               │
│                                     │
│ Mental health                       │
│ ├───────────────────●───────┤       │
│ Severe  Moderate  Avg  Above avg    │
│ "Average." · Based on check-in      │
│  10 Jun 2026. [Update →]            │
├─────────────────────────────────────┤
│ ⚑ 3 markers to discuss              │
│ [LDL ↑] [HbA1c ↑] [Uric acid ↑]   │
│ Tap any marker to see its trend →   │
├─────────────────────────────────────┤
│ YOUR SYSTEMS                        │
│                                     │
│ ┌──────────────┐ ┌──────────────┐   │
│ │ 🔴 Metabolic  │ │ 🟡 Heart &   │   │
│ │ HbA1c ↑      │ │    Arteries  │   │
│ │ 1 red · 2 yel│ │ LDL ↑       │   │
│ │ of 8 measured│ │ 0 red · 3 yel│   │
│ │ ~~~sparkline~│ │ of 9 measured│   │
│ └──────────────┘ └──────────────┘   │
│ ┌──────────────┐ ┌──────────────┐   │
│ │ 🟢 Kidney    │ │ 🟡 Liver     │   │
│ │ eGFR ↗       │ │ FIB-4 ⤳     │   │
│ │ 0 red · 0 yel│ │ 0 red · 1 yel│   │
│ │ of 4 measured│ │ of 7 measured│   │
│ └──────────────┘ └──────────────┘   │
│ ┌──────────────┐ ┌──────────────┐   │
│ │ 🟡 Inflam.   │ │ 🟢 Blood &   │   │
│ │ CRP ↑        │ │    Immunity  │   │
│ │ 0 red · 1 yel│ │ 0 red · 0 yel│   │
│ └──────────────┘ └──────────────┘   │
│ ┌──────────────┐ ┌──────────────┐   │
│ │ 🟡 Thyroid   │ │ 🟡 Nutrients │   │
│ │ TSH ↗        │ │ Vit D ↓      │   │
│ │ 0 red · 1 yel│ │ 0 red · 2 yel│   │
│ └──────────────┘ └──────────────┘   │
├─────────────────────────────────────┤
│ Biological age trend (optional) →   │
├─────────────────────────────────────┤
│ Educational only · discuss any      │
│ result with your clinician.         │
└───────────────[🎙 Ask Span]─────────┘
```

### Data

`GET /v1/overview` returns an `OverviewDTO`:
- `promis: { gph_tscore, gph_band, gmh_tscore, gmh_band, based_on_date }?` — null if no check-in exists
- `attention: [{ parameter, flag, latest_value, unit, canonical_param_id }]` — parameters outside clinical range
- `systems: [SystemRollup]` — 8 tiles, each with `status`, `lead_parameter`, `status_basis` (e.g. "1 red, 2 yellow of 8 measured"), `sparkline_points`
- `bioage_available: bool`

### Tile Detail

Each system tile displays:
- System name + icon
- Traffic-light status dot (Red / Yellow / Green / Gray)
- Lead marker name + trend arrow (↑ worsening / ↗ improving / ⤳ stable) — direction is parameter-polarity-aware (eGFR ↑ = improving, LDL ↑ = worsening)
- Status basis string, e.g., "1 red · 2 yellow of 9 measured" — never a percentage
- Mini sparkline of the lead marker's last 12 readings

The 8 systems and their lead markers:
| System Key | Display Name | Lead Marker |
|---|---|---|
| `metabolic` | Metabolic | HbA1c |
| `cardiovascular` | Heart & Arteries | ApoB (fallback: LDL) |
| `liver` | Liver | ALT (FIB-4 composite if computable) |
| `kidney` | Kidney | eGFR |
| `inflammation_immune` | Inflammation & Immunity | hsCRP |
| `hematologic` | Blood & Immunity | Haemoglobin |
| `endocrine_thyroid` | Thyroid | TSH |
| `micronutrient_bone` | Nutrients & Bone | Vitamin D |

### PROMIS Bands

The two PROMIS Global-10 gauges are **only shown if a check-in result exists** (either from today, or the most recent within 30 days). If no check-in exists, this section is replaced with:

```
┌─────────────────────────────────────┐
│ How are you feeling overall?        │
│ A 2-minute check-in gives you a    │
│ whole-person health picture.        │
│ [Start check-in →]                  │
└─────────────────────────────────────┘
```

The PROMIS T-score bands use these labels (from T-score ranges):
- <30: Severe
- 30–40: Moderate
- 40–45: Mild
- 45–55: Average
- >55: Above Average

Caption below each gauge: "Compared with the general population (50 = average). Based on your check-in on [date]."

### Attention Rail

The "markers to discuss" rail shows horizontal chip items for each parameter currently outside its clinical reference range. Each chip shows the parameter name and a Red (High) or Blue (Low) flag indicator. The rail scrolls horizontally if there are more chips than fit the screen. A header row says "N markers to discuss with your clinician."

If no parameters are outside range, the attention rail is omitted entirely. No "all clear" trophy or celebratory copy — absence of red is not an occasion for praise.

### Biological Age Link

A single collapsed row at the bottom of the tiles section, before the footer: "Your biological age trend (optional) →". Tapping navigates to Screen 15. This link is only visible if `bioage_available=true`. It is never above the fold, never a number on this screen.

### Interactions / Navigation

- Tap attention chip → Parameter Detail (Screen 10) for that parameter
- Tap system tile → System Detail (Screen 9)
- "Biological age trend" link → Biological Age (Screen 15)
- [Update →] link on PROMIS section → Check-In (Screen 13)
- "Ask Span" floating button → Voice Consultant (Screen 16)

### Empty State (no reports uploaded yet)

```
┌─────────────────────────────────────┐
│ Good morning, Anoop                 │
│                                     │
│ Upload your first lab report to     │
│ see your health trends here.        │
│                                     │
│ [📁 Upload a report]                │
│ [📷 Scan a paper report]            │
│                                     │
│ Span reads PDFs from Thyrocare,     │
│ Tata 1mg, Healthians, CLUMAX,       │
│ and 20+ other Indian labs.          │
└─────────────────────────────────────┘
```

### Loading State

Skeleton views (gray rounded rectangles) in place of each tile and the PROMIS gauges while the overview DTO loads.

### Error State

"Unable to load your health overview. Please check your connection." with a Retry button.

---

`[DESIGN: Screen 7 — Today / Whole-Person Overview — to be attached]`

---

## Screen 8 — Systems Tab

### Purpose

A dedicated tab giving direct access to all 8 organ systems. Functionally equivalent to scrolling the tile grid, but lives in the tab bar so it is always one tap away without requiring a scroll to the home grid.

### What the User Sees

A list of 8 system rows, each showing the same tile data as the home screen but in a taller row format that accommodates more text.

```
┌─────────────────────────────────────┐
│  Systems                            │
├─────────────────────────────────────┤
│ 🔴 Metabolic                   >    │
│   HbA1c ↑ · 1 red, 2 yellow of 8   │
│   ~~~lead marker sparkline~~~       │
├─────────────────────────────────────┤
│ 🟡 Heart & Arteries            >    │
│   LDL ↑ · 0 red, 3 yellow of 9     │
├─────────────────────────────────────┤
│ 🟢 Kidney                      >    │
│   eGFR ↗ · 0 red, 0 yellow of 4    │
├─────────────────────────────────────┤
│ 🟡 Liver                       >    │
│   ALT ⤳ · 0 red, 1 yellow of 7     │
├─────────────────────────────────────┤
│ 🟡 Inflammation & Immunity     >    │
│   hsCRP ↑ · 0 red, 1 yellow of 5   │
├─────────────────────────────────────┤
│ 🟢 Blood & Immunity            >    │
│   Hb ↗ · 0 red, 0 yellow of 11     │
├─────────────────────────────────────┤
│ 🟡 Thyroid                     >    │
│   TSH ↗ · 0 red, 1 yellow of 3     │
├─────────────────────────────────────┤
│ 🟡 Nutrients & Bone            >    │
│   Vitamin D ↓ · 0 red, 2 yellow    │
├─────────────────────────────────────┤
│ Educational only · discuss any      │
│ result with your clinician.         │
└───────────────[🎙 Ask Span]─────────┘
```

### Data

Same `GET /v1/overview` response as Screen 7, `systems` array.

### Interactions / Navigation

- Tap any row → System Detail (Screen 9) for that system
- Floating "Ask Span" → Voice Consultant

### Empty / Error States

Same as Screen 7.

---

`[DESIGN: Screen 8 — Systems Tab — to be attached]`

---

## Screen 9 — System Detail

### Purpose

Shows all member parameters for one organ system, with individual trend indicators, and provides the "why this matters" educational context linking the system to the Hallmarks of Aging and the Four Horsemen framework.

### What the User Sees

```
┌─────────────────────────────────────┐
│ ← Back         Metabolic           │
├─────────────────────────────────────┤
│ 🔴 attention · 1 red, 2 yellow of 8 │
├─────────────────────────────────────┤
│ WHY THIS MATTERS                    │
│ Metabolic dysfunction is one of     │
│ Peter Attia's Four Horsemen —       │
│ a key driver of cardiovascular      │
│ disease, dementia, and cancer.      │
│ In the Hallmarks of Aging framework │
│ (López-Otín 2023), it maps to       │
│ deregulated nutrient-sensing and    │
│ chronic inflammation.               │
│ [Tier 1 — ACC/AHA guideline ↗]      │
├─────────────────────────────────────┤
│ PARAMETERS                          │
│                                     │
│ HbA1c             6.9%  🔴 High    │
│ ~~~sparkline~~~   ↑ rising          │
│                                     │
│ Fasting glucose   102   🟡 Monitor  │
│ ~~~sparkline~~~   ↗ improving       │
│                                     │
│ TyG index         8.7   🟡 Monitor  │
│ (insulin resistance, trend only)    │
│ ~~~sparkline~~~   ⤳ stable          │
│                                     │
│ BMI               26.1  🟢 Optimal  │
│ ~~~sparkline~~~   ↗ improving       │
│                                     │
│ Triglycerides     148   🟡 Monitor  │
│ ~~~sparkline~~~   ↑ rising          │
│                                     │
│ Fasting insulin   —     not tested  │
│                                     │
│ HOMA-IR           —     needs       │
│                         fasting     │
│                         insulin     │
├─────────────────────────────────────┤
│ [Compare these in one chart →]      │
│                                     │
│ [🎙 Ask Span about my Metabolic     │
│     health →]                       │
├─────────────────────────────────────┤
│ Educational only · discuss any      │
│ result with your clinician.         │
└─────────────────────────────────────┘
```

### Data

`GET /v1/systems/{systemKey}` returns a `SystemDetailDTO`:
- `system`: display name, icon name, `hallmark: string[]`, `horseman: string?`
- `members: [{ canonical_param_id, display_name, latest_value, unit, flag, zone_status, slope, direction, sparkline_points: [{date, value}], note? }]`
- `status`, `status_basis`

Parameters with `latest_value = null` (never tested or not in any uploaded report) display as "— not tested" in gray.

Parameters that are computed scores (TyG, FIB-4, eGFR) display their score value with a footnote "computed score" and their own zone_status, with a "trend only, no fixed cutoff" label where appropriate (TyG, NLR, AAR, PLR).

### Parameter Row

Each member parameter row shows:
- Display name (left)
- Latest value + unit (right)
- Traffic-light dot (color only, plus a text label for VoiceOver)
- Mini sparkline (last 8–12 readings, auto-scaled, no axes shown)
- Trend arrow below the sparkline: ↑ worsening / ↗ improving / ⤳ stable (derived from `direction` field; label accounts for polarity — eGFR ↑ = improving, LDL ↑ = worsening)

Tapping any row → Parameter Detail (Screen 10).

### "Why This Matters" Section

Every system detail screen has a collapsible "Why this matters" card showing:
- The Four Horsemen category this system maps to (if applicable)
- The Hallmark(s) of Aging it is most strongly linked to (from López-Otín 2023)
- A 2–3 sentence plain-language explanation
- A Tier 1 citation chip (guideline source)

### "Compare in One Chart" Action

A button at the bottom launches an overlay sheet with a multi-series Swift Charts view overlaying all numeric member parameters on one timeline. Each series uses a distinct line style (not just color, for accessibility). This is a comparison view only — no reference bands, no optimal bands — to avoid visual clutter.

### "Ask Span" Deep-Link

A button reading "Ask Span about my [System Name] →" launches the voice consultant (Screen 16) with the current system pre-loaded as context (`context: { system: systemKey, flagged_params: [...] }`). The voice consultant's opening prompt references this system.

### Interactions / Navigation

- Tap parameter row → Parameter Detail (Screen 10)
- "Compare in one chart" → multi-series overlay sheet (modal)
- "Ask Span about my [system]" → Voice Consultant (Screen 16, with context)

---

`[DESIGN: Screen 9 — System Detail — to be attached]`

---

## Screen 10 — Parameter Detail (Swift Charts Centerpiece)

### Purpose

The richest single-parameter view. Shows the full measurement history as a trend chart with a clinical reference band and (where it exists) a green evidence-based optimal band. Answers: "What has this marker been doing, how unusual is my current level, and what should I know about it?"

### What the User Sees

```
┌─────────────────────────────────────┐
│ ← Back       HbA1c              ⤢  │
├─────────────────────────────────────┤
│ GLYCATED HAEMOGLOBIN               │
│ Latest: 6.9%  🔴 High              │
│ As of 8 Jun 2026 · Tata 1mg        │
├─────────────────────────────────────┤
│ [28d] [1y] [All]  Baseline ○       │
├─────────────────────────────────────┤
│  7.5 ┤                          ●  │
│  7.0 ┤                     ●       │
│  6.5 ┤    ██████████████████       │  ← clinical band (gray fill)
│  6.0 ┤ ●  ██ optimal (green) ██   │  ← optimal band (light green fill)
│  5.5 ┤    ██████████████████       │
│  5.0 ┤                             │
│      └────────────────────────────  │
│        2023     2024     2025  2026 │
│                                     │
│ Clinical range: 4.0–5.6%           │
│ [Tier 1 · ICMR 2023 guideline ↗]   │
│                                     │
│ Optimal target: < 5.5%             │
│ [Tier 1 · Attia (expert opinion)   │
│  · discuss with clinician ↗]        │
├─────────────────────────────────────┤
│ HOW UNUSUAL IS THIS?                │
│                                     │
│ About 23 of 100 people your age    │
│ and sex have HbA1c this high.       │
│                                     │
│ 👤👤👤👤👤👤👤👤👤👤            │
│ 👤👤👤👤👤👤👤👤👤👤            │
│ 👥👥👥                             │
│ (filled = people like you          │
│  with similarly elevated HbA1c)     │
│                                     │
│ Based on NHANES reference data.     │
│ May not be calibrated for Indian    │
│ populations.                        │
├─────────────────────────────────────┤
│ READINGS                            │
│ Date       Value  Lab      Flag     │
│ 08 Jun 26  6.9%   Tata 1mg  High   │
│ 14 Mar 26  7.1%   Thyrocare High   │
│ 01 Dec 25  7.0%   Healthian High   │
│ 20 Jun 25  6.4%   Tata 1mg  High   │
│ …                                   │
│ [Export CSV]                        │
├─────────────────────────────────────┤
│ ABOUT HBAIC                         │
│ HbA1c reflects your average blood  │
│ sugar over the past 2–3 months.     │
│ Values above 6.5% are the          │
│ diagnostic threshold for diabetes   │
│ in most guidelines.                 │
│ [Tier 1 · ADA 2024 ↗]              │
├─────────────────────────────────────┤
│ Educational only · discuss any      │
│ result with your clinician.         │
└─────────────────────────────────────┘
```

### Chart Construction (Swift Charts)

The chart is built in Swift Charts with these mark layers (back to front):

1. **Clinical reference band** — `RectangleMark` from `y: ref_low` to `y: ref_high`, spanning the full x-axis. Fill: a light gray or off-white (`Color.gray.opacity(0.12)`). This represents the lab/guideline clinical normal range.

2. **Optimal band** (only if an `optimal_band` exists for this parameter) — a second `RectangleMark` over the optimal zone, tinted light green (`Color.green.opacity(0.15)` with a `Color.green.opacity(0.4)` stroke). Tapping this band opens the Citation Detail sheet (Screen 18) for the band's source.

3. **Line mark** — `LineMark` connecting all non-null value points, in `.primary` color.

4. **Point marks** — `PointMark` for each reading, colored by flag: High = red, Low = blue, Normal = green. Size: 8pt diameter. For `value == null` points (where `value_text` is a non-numeric like "Negative" or "Trace"): render a hollow `PointMark` or a distinct symbol (e.g., diamond) at the expected y-position if estimable, otherwise at `ref_low` with an annotation label showing `value_text`.

5. **Baseline marker** (when baseline toggle is on) — a vertical dashed line at the baseline reading date, labeled "Your baseline."

### Window Controls

Three buttons above the chart: [28d] [1y] [All]. These adjust the x-axis domain. Default: [All] (show full history). The window control sends `?window=28d|1y|all` to `GET /v1/parameters/{id}/trend`.

### Baseline Toggle

A toggle switch labeled "Baseline first" — when on, the trend line uses the user's first in-range reading as the baseline (y=0 anchor visually), and a vertical line marks that date. When off, absolute values are shown. The toggle calls `?baseline=self|absolute`.

### "How Unusual Is This?" Card

Displays a natural-frequency statement: "About N of 100 people your age and sex have a value [this high / this low / like yours]." Below it, a 10×10 icon array (100 figures), with `N` figures filled/highlighted to represent the frequency. The remaining figures are outlined.

Rules:
- Never shows a bare percentage (e.g., never "23%")
- The comparator text is human-written, not generated: "About 23 of 100 people your age and sex have HbA1c this high."
- Source: derived server-side from NHANES percentile lookup
- Always shows the caveat: "Based on NHANES reference data. May not be calibrated for Indian populations."
- If N = 0 or data is insufficient: "Not enough reference data for this comparison."

### Citation Chips

Below the chart, two citation chip rows:
- Clinical range: "[Tier X · [Source title] ↗]" — tapping opens Citation Detail modal
- Optimal band: "[Tier X · [Source title] — expert opinion · discuss with clinician ↗]"

Optimal band citations must always carry the "expert opinion" or "peer-reviewed" qualifier, never presented as a diagnostic guideline.

### Data Table

A sortable table below the "how unusual" card, showing all readings for this parameter, sorted newest first by default. Columns: Date, Value (+ unit), Lab, Flag. User can tap any column header to sort. An "Export CSV" button exports the table to a shareable CSV file (via the system share sheet), containing Date, Parameter, Value, Unit, Lab, Flag, Reference Low, Reference High.

### Data

`GET /v1/parameters/{id}` returns `ParameterDetailDTO`:
- `parameter`: display name, canonical ID, category
- `points: [{ date, value, unit, flag, value_text, lab, ref_low, ref_high }]`
- `ref_band: { low, high, source_id, ref_source_label }` (clinical reference)
- `optimal_band: { low?, high?, direction, evidence_tier, source_id, label }?` (only if exists)
- `stat: { slope_per_year, direction, natural_freq: { count, denom, comparator_desc } }`
- `citations: [Source]`

`GET /v1/parameters/{id}/trend?window=28d|1y|all&baseline=self|absolute` returns filtered point series.

### Interactions / Navigation

- Tap reference band → no action (static)
- Tap optimal band → Citation Detail sheet (Screen 18) for the optimal band source
- Tap citation chip → Citation Detail sheet (Screen 18)
- Tap a point mark → tooltip/popover with: date, value, unit, lab name, flag
- Tap a data table row → same tooltip/popover
- "Export CSV" → system share sheet with CSV attachment
- Back → previous screen in NavigationStack

### Empty State

If `points` is empty (parameter exists in catalog but user has no readings): "No readings yet for [Parameter Name]. Upload a lab report that includes it to see your trend here."

### Error State

"Unable to load [Parameter Name] data. Please try again." with Retry button.

---

`[DESIGN: Screen 10 — Parameter Detail — to be attached]`

---

## Screen 11 — Ingestion / Upload

### Purpose

The primary entry point for adding lab reports. Supports two methods: bulk file/folder selection from Files app, and VisionKit document camera scan. Gmail is explicitly deferred and must not appear in this interface.

### What the User Sees

An upload management screen with two entry points and a list of in-progress / recently completed uploads.

```
┌─────────────────────────────────────┐
│ ← Back         Add reports          │
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │  📁  Select files from Files   │ │
│ │  PDF or image · multiple files  │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │  📷  Scan a paper report        │ │
│ │  Camera · auto-enhanced          │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ RECENT UPLOADS                      │
│                                     │
│ [✓] Thyrocare_Mar26.pdf             │
│     Done · 42 measurements saved   │
│                                     │
│ [⋯] Healthians_Feb26.pdf            │
│     Parsing · usually <2 min        │
│     [████████░░] 80%                │
│                                     │
│ [!] CLUMAX_Jan26.pdf                │
│     Needs your review → [Review]    │
│                                     │
│ [✓] Tata1mg_Dec25.pdf               │
│     Done · 38 measurements saved   │
└─────────────────────────────────────┘
```

### Upload Flow (File Picker)

1. User taps "Select files from Files" → native UIDocumentPickerViewController, allowing multiple file selection, file types: PDF, JPG, PNG, HEIC, TIFF.
2. For each selected file, app sends `POST /v1/ingestion/intents` with `{ filename, mime_type, byte_size, content_sha256, source: 'folder' }`.
3. Server returns `{ artifact_id, job_id, verdict: 'new'|'duplicate', upload: { url, method: 'PUT', headers, expires_at } }` per file.
4. For `verdict = 'duplicate'`: show inline chip "Already in Span — skipped." Do not upload.
5. For `verdict = 'new'`: client PUTs file bytes directly to the presigned S3 URL (never through the app server).
6. After PUT completes, client calls `POST /v1/ingestion/{job_id}/complete` → server transitions to `enqueued`.
7. App begins polling `GET /v1/ingestion/jobs?since=...` (or subscribes to SSE stream) for status updates.

### Upload Flow (VisionKit Scan)

1. User taps "Scan a paper report" → `VNDocumentCameraViewController` presented.
2. User scans one or more pages; VisionKit performs on-device de-skew and enhancement.
3. On scan completion, app shows a preview of the scanned pages with a "Use this scan" / "Retake" option.
4. "Use this scan" → same `POST /v1/ingestion/intents` + PUT flow as above with `source: 'photo'`.

### Per-Job Status States

Each upload item in the "Recent Uploads" list maps to an `ingestion_jobs.status` value:

| Status | Display | Icon |
|---|---|---|
| `intent_created` | Preparing upload… | spinner |
| `uploading` | Uploading… | progress bar |
| `uploaded` | Uploaded, in queue… | spinner |
| `enqueued` | In queue… | spinner |
| `parsing` | Parsing · usually <2 min | progress bar (indeterminate) |
| `needs_review` | Needs your review | `!` orange dot + [Review] button |
| `extracted` | Processing… | spinner |
| `committed` | Done · N measurements saved | ✓ green |
| `failed` | Failed to process | `✕` red + [Try again] button |
| `duplicate` | Already in Span | gray, no action |
| `quarantined` | File could not be processed (contact support) | `✕` red |

### Needs-Review State

When a job reaches `needs_review`, the list item shows an orange `!` dot and a [Review] button. Tapping navigates to Screen 12 (User Self-Confirm Review).

### Data

- `POST /v1/ingestion/intents` — per file
- `PUT <presigned-s3-url>` — direct to S3
- `POST /v1/ingestion/{job_id}/complete` — signals upload done
- `GET /v1/ingestion/jobs?status=&since=` — polling (or SSE stream)

### Interactions / Navigation

- "Select files from Files" → document picker
- "Scan a paper report" → VisionKit camera
- [Review] button on a needs-review job → Screen 12
- [Try again] on a failed job → re-initiates the upload intent flow for that file

### Error States

- File too large (>50MB): inline error "This file is too large. Try a PDF under 50 MB."
- Unsupported format: "Span supports PDFs and images (JPG, PNG). This file type isn't supported."
- Network failure during PUT: inline "Upload interrupted. [Retry]"
- Presigned URL expired: re-request from `/v1/ingestion/intents` automatically

### Edge Cases

- User uploads the same file twice: `content_sha256` dedup — server returns `verdict: 'duplicate'`; app shows "Already in Span" in the list item for the second attempt
- File contains multiple reports (e.g., a merged PDF of 12 months of tests): the parsing layer handles this; each report page group becomes its own extraction batch; UI shows one combined job with an aggregate count
- App goes to background mid-upload: iOS background URLSession (`URLSession.shared` with `.background` configuration) continues the PUT; on foregrounding, the job status is polled and the UI updates

---

`[DESIGN: Screen 11 — Ingestion / Upload — to be attached]`

---

## Screen 12 — Ingestion: User Self-Confirm Review

### Purpose

When the parsing pipeline has low confidence in a specific extraction — a value, unit, or parameter name — it routes the measurement to human review rather than auto-committing. Per the resolved decision (§11 decision 3), the user is the reviewer at MVP (no clinical staff). This screen presents one review task at a time, showing the source image crop alongside the extracted value, and asks the user to confirm or correct.

### What the User Sees

A focused, one-task-at-a-time interface. Each review task is a "card" the user works through sequentially.

```
┌─────────────────────────────────────┐
│ ← Back     Review extractions       │
│            2 of 4 to review         │
├─────────────────────────────────────┤
│ We extracted this from your report: │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │  [SOURCE IMAGE CROP]            │ │
│ │  A cropped image of the         │ │
│ │  relevant row from the lab      │ │
│ │  report is shown here, with     │ │
│ │  the extracted field highlighted │ │
│ │  in yellow.                     │ │
│ └─────────────────────────────────┘ │
│                                     │
│ We read this as:                    │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Parameter  HbA1c                │ │
│ │ Value      6.7                  │ │
│ │ Unit       %                    │ │
│ │ Date       March 14, 2026       │ │
│ │ Lab        Thyrocare            │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Is this correct?                    │
│                                     │
│ ┌─────────┐  ┌─────────────────┐   │
│ │ ✓ Looks │  │ ✎ Edit          │   │
│ │  right  │  │                 │   │
│ └─────────┘  └─────────────────┘   │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ✕ This isn't right — skip       │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Review Task Types

The `review_tasks.reason` field determines what is being reviewed:

| `reason` | What is shown | What user can edit |
|---|---|---|
| `low_conf` | The full extracted row | All fields |
| `outlier` | Value with plausibility warning ("This looks unusually high") | Value + unit |
| `unmapped_param` | Parameter name that couldn't be matched to Span's catalog | Parameter name (from a dropdown of suggestions + "None of these") |
| `unit_ambiguous` | Unit shown, alternatives listed | Unit selection |

### Edit Flow

Tapping "Edit" expands the card into an editable form with:
- Parameter name: read-only (not editable by user) unless `reason = 'unmapped_param'`
- Value: numeric text field
- Unit: segmented picker showing the extracted unit + alternatives from the unit_rules catalog
- Date: date picker
- A "Cancel edit" link to revert changes

### Decisions

- **✓ Looks right:** `POST /v1/ingestion/{job_id}/review` with `{ task_id, decision: 'accept' }` → measurement committed with `extraction_status = 'human_reviewed'`
- **✎ Edit → Save:** `POST /v1/ingestion/{job_id}/review` with `{ task_id, decision: 'correct', corrected: { ... } }` → committed with `extraction_status = 'human_corrected'`
- **✕ Skip:** `POST /v1/ingestion/{job_id}/review` with `{ task_id, decision: 'reject' }` → measurement not committed; row recorded as rejected in `review_tasks`

### Progress and Completion

- A "N of M to review" counter at the top
- After all tasks are resolved, show a summary: "Done. N measurements confirmed, M skipped." with a [Go to Today] button
- If the user closes the review screen mid-way, the remaining tasks remain in `needs_review` status and the upload list (Screen 11) continues to show the [Review] badge

### Data

`GET /v1/ingestion/{job_id}/review-tasks` returns `[ReviewTask]`:
- `id`, `reason`, `measurement_draft` (extracted values), `bbox` (for image crop coordinates), `s3_image_key` (the artifact's stored image)
- `source_image_crop_url`: a presigned short-lived S3 URL to the cropped source image region

`POST /v1/ingestion/{job_id}/review` with `{ task_id, decision, corrected? }`

### Edge Cases

- Source image not available (e.g., original was a text-PDF with no visual content): show "No image preview available" placeholder; the extracted text context is shown instead
- All tasks in a job are low-confidence: user must review all before any measurement is committed
- User edits a value that is outside the plausibility window: inline warning "This value looks unusually high for [Parameter]. Are you sure?" — user can still save; the value is stored with a `field_confidence` low flag

---

`[DESIGN: Screen 12 — Ingestion Self-Confirm Review — to be attached]`

---

## Screen 13 — Check-In (Daily QoL)

### Purpose

A brief daily or weekly well-being check-in. The primary instrument is WHO-5. A rotation engine may substitute PROMIS Fatigue 4a or Sleep Disturbance 4a on a schedule. The result is a well-being trend, not a verdict. This screen feeds the PROMIS Global-10 bands on the Today tab.

### What the User Sees

A card-stack format where each item is presented as a full-width card. The user progresses through 5 cards (for WHO-5) by tapping a response option or swiping.

**Opening card (WHO-5 instrument):**
```
┌─────────────────────────────────────┐
│ ← Back      How have you been?      │
│             1 of 5                  │
├─────────────────────────────────────┤
│                                     │
│ "Over the past two weeks,          │
│  I have felt cheerful               │
│  and in good spirits."              │
│                                     │
│  ┌──────┐ ┌──────┐ ┌──────┐        │
│  │ All  │ │ Most │ │ More │        │
│  │ the  │ │ of   │ │ than │        │
│  │ time │ │ the  │ │ half │        │
│  │  5   │ │ time │ │ the  │        │
│  │      │ │  4   │ │ time │        │
│  │      │ │      │ │  3   │        │
│  └──────┘ └──────┘ └──────┘        │
│  ┌──────┐ ┌──────┐                  │
│  │ Less │ │ At   │                  │
│  │ than │ │ no   │                  │
│  │ half │ │ time │                  │
│  │ the  │ │  0   │                  │
│  │ time │ │      │                  │
│  │  2   │ │      │                  │
│  └──────┘ └──────┘                  │
└─────────────────────────────────────┘
```

WHO-5 items (CC-BY-NC-SA — commercial licensing must be cleared before shipping, per §2.5):
1. "Over the past two weeks, I have felt cheerful and in good spirits."
2. "Over the past two weeks, I have felt calm and relaxed."
3. "Over the past two weeks, I have felt active and vigorous."
4. "Over the past two weeks, I have woken up feeling fresh and rested."
5. "Over the past two weeks, my daily life has been filled with things that interest me."

Each item: 6-point segmented response (All the time = 5 / Most of the time = 4 / More than half the time = 3 / Less than half the time = 2 / Some of the time = 1 / At no time = 0).

**After completing all 5 items:**
```
┌─────────────────────────────────────┐
│ Check-in complete                   │
├─────────────────────────────────────┤
│ Your well-being today:              │
│                                     │
│ ├─────────────●────────────────┤    │
│ Low          56/100          High  │
│                                     │
│ This is a general picture of how   │
│ you have been feeling, based on    │
│ your responses. It is not a        │
│ diagnosis.                          │
│                                     │
│ YOUR TREND                          │
│ ~~~WHO-5 score trend chart~~~       │
│ Last 8 check-ins shown.             │
│                                     │
│ [What does this score mean? →]      │
├─────────────────────────────────────┤
│ ← Back to Today                     │
└─────────────────────────────────────┘
```

**Soft nudge (if score ≤ 50 / raw total < 13):**
```
┌─────────────────────────────────────┐
│ Note                                │
│                                     │
│ Your responses suggest you may      │
│ have been having a difficult time.  │
│ You might want to talk about how    │
│ you have been feeling with a        │
│ clinician.                          │
│                                     │
│ This is not a diagnosis.            │
│ [iCall India: 9152987821]           │
│ [Vandrevala Foundation: 1860-2662-345]│
│                                     │
│ [OK]                                │
└─────────────────────────────────────┘
```

The nudge is a non-modal alert-style card. It never uses the word "depression," never names a condition, and always frames as "discuss with a clinician." Emergency helpline numbers for India are included.

### QoL↔HealthKit Co-occurrence Card

If HealthKit data is available (sleep duration, HRV, resting HR), the post-check-in screen shows a gentle co-occurrence card after the score trend:

```
┌─────────────────────────────────────┐
│ A pattern we noticed                │
│                                     │
│ Your lower-energy days tend to      │
│ follow nights with less sleep.      │
│                                     │
│ This is a co-occurrence, not a      │
│ cause — many things affect how      │
│ we feel.                            │
│                                     │
│ [Sleep trend →]                     │
└─────────────────────────────────────┘
```

This card is only shown if the correlation has at least 3 paired data points. The copy is templated and non-causal by design. The word "cause" or any causal language never appears in this card. It must not link a check-in score to any specific lab parameter (e.g., never "your lower mood may be related to your TSH").

### PROMIS Fatigue / Sleep Rotation

The rotation engine (`GET /v1/checkin/next`) may substitute a PROMIS instrument on a schedule. When it does:
- Opening card shows: "This week, we are asking about your energy levels." (for Fatigue 4a) or "This week, we are asking about your sleep." (for Sleep Disturbance 4a).
- PROMIS items are presented in the same card-stack format.
- PROMIS items and scoring are public domain; no licensing footnote required.
- After completion, the computed T-score (if PROMIS Global-10) updates the Today tab bands.

### Data

`GET /v1/checkin/next` returns `{ instrument_id, instrument_name, items: [{ key, prompt, scale_min, scale_max, scale_labels }], due_date }`

`POST /v1/checkin/responses` with `{ instrument_id, raw_scores: [int], completed_at }` → server returns `CheckinResponse { computed_score, computed_band, soft_flag }`

`GET /v1/checkin/history?instrument=WHO-5` → trend series for the trend chart

### Interactions / Navigation

- Card navigation: tap a response → auto-advances to next card after a brief delay (300ms)
- Back arrow on any card → returns to previous card (responses are preserved in memory)
- After completion → stays on the result screen; [Back to Today] navigates to Today tab
- If score ≤ 50 → soft nudge card is shown first, then result; [OK] dismisses the nudge

### Empty State (no previous check-ins)

The trend chart section is hidden if there is only one check-in (today's). Instead, a label: "Your well-being trend will appear here after a few check-ins."

### Edge Cases

- WHO-5 commercial licensing note: this screen must not be shipped until the WHO commercial license is cleared (see §2.5). A feature flag `CHECKIN_WHO5_ENABLED` gates this screen.
- Partial completion: if the user closes the app mid-check-in, responses are preserved in local state and resumed on next open
- Skipping: a "Skip today" link is available from the first card; tapping logs a `null` response for the day, does not affect the trend

---

`[DESIGN: Screen 13 — Check-In (Daily QoL) — to be attached]`

---

## Screen 14 — Doctor-Visit Prep Sheet

### Purpose

Generates and displays a structured, Opus-LLM-produced doctor-visit preparation document. The document helps the user have a more productive clinical conversation by surfacing the most important trends, a question prompt list, and evidence-cited lifestyle/supplement discussion points. The prep sheet is educational — it does not diagnose, prescribe, or suggest doses.

### What the User Sees

**Before generation (entry point):**
```
┌─────────────────────────────────────┐
│  Prep                               │
├─────────────────────────────────────┤
│                                     │
│  Your next doctor's appointment     │
│  is a chance to discuss what        │
│  your data shows.                   │
│                                     │
│  [Generate prep sheet →]            │
│                                     │
│  Takes about 30–60 seconds.         │
│  Based on your most recent          │
│  lab results.                       │
│                                     │
│  Last generated: March 14, 2026     │
│  [View previous sheets →]           │
└─────────────────────────────────────┘
```

**During generation:**
```
┌─────────────────────────────────────┐
│  Generating your prep sheet…        │
│                                     │
│  ████████████░░░░░░░░░░░░  60%      │
│                                     │
│  Reviewing your lab trends.         │
│  Identifying questions to ask.      │
│  Adding citations.                  │
└─────────────────────────────────────┘
```

**Completed prep sheet:**
```
┌─────────────────────────────────────┐
│ ← Back    Doctor-Visit Prep  [↑ PDF]│
│           Generated 14 Jun 2026     │
├─────────────────────────────────────┤
│ ● RAISE THIS FIRST                  │
│                                     │
│ Your HbA1c has risen from 6.4%      │
│ to 6.9% over the past year, now     │
│ above the diagnostic threshold      │
│ for type 2 diabetes. This is your   │
│ most urgent trend to discuss.       │
│ [Tier 1 · ADA 2024 Standards ↗]    │
├─────────────────────────────────────┤
│ KEY MARKERS AT A GLANCE             │
│                                     │
│ Marker    Value   Ref    Status     │
│ HbA1c     6.9%    <5.6%  🔴 High   │
│ LDL       157     <100   🔴 High   │
│ ApoB      —       <90    Not tested │
│ eGFR      82      >60    🟢         │
│ hsCRP     3.1     <1.0   🔴 High   │
│ …                                   │
├─────────────────────────────────────┤
│ QUESTIONS TO ASK                    │
│                                     │
│ Metabolic                           │
│ ☐ My HbA1c has crossed 6.5% —      │
│   should I be tested for diabetes?  │
│ ☐ Is my fasting glucose pattern     │
│   concerning given my family        │
│   history?                          │
│                                     │
│ Heart & Arteries                    │
│ ☐ My LDL has risen to 157 —         │
│   what is my cardiovascular risk?   │
│ ☐ Should I test ApoB and Lp(a)?     │
│   I have not had these tested.      │
│                                     │
│ Inflammation                        │
│ ☐ My hsCRP is elevated. What        │
│   could be driving this?            │
│                                     │
│ (Tick the questions that matter     │
│  most to you before your visit.     │
│  It is normal to feel a bit anxious │
│  writing these down.)               │
├─────────────────────────────────────┤
│ LIFESTYLE & SUPPLEMENTS TO DISCUSS  │
│                                     │
│ Item          Why / Caution        │
│ Omega-3 (fish Omega-3 index 4.2%  │
│ oil)          may be below 8%.     │
│               Caution: discuss      │
│               dose with your Dr.   │
│               Verdict: Reasonable  │
│               to discuss.          │
│               [Tier 1 · ASCEND ↗] │
│                                     │
│ NMN           No human outcome     │
│               RCT. Contested.      │
│               Verdict: Unproven.   │
│               Discuss with Dr.     │
│               [Tier 3 · contested ↗]│
├─────────────────────────────────────┤
│ GAPS YOUR CLINICIAN LIKELY MISSED   │
│                                     │
│ · ApoB last tested Jan 2024         │
│   despite LDL rising +40% since.   │
│ · Lp(a) never tested (one-time     │
│   genetic test; recommended in     │
│   ACC/AHA 2022 guidance).          │
│ · ACR (urine albumin-creatinine    │
│   ratio) only tested once.         │
├─────────────────────────────────────┤
│ Span is not a medical device.       │
│ This sheet is educational only.     │
│ All information must be discussed   │
│ with a qualified clinician.         │
│ Do not start, stop, or adjust any  │
│ medication or supplement based on  │
│ this sheet alone.                   │
│ Generated by AI · Not clinically    │
│ validated · Educational only.       │
└─────────────────────────────────────┘
```

### PrepReport Sections

Each section maps directly to a field in the `PrepReport` JSON schema:

**1. Raise This First (`raise_first`)**
- Single most urgent trend, identified by the server-side analysis layer (highest urgency parameter passed to Opus)
- 2–4 sentences, plain language, defers to clinician
- Must cite ≥1 source

**2. Key Markers at a Glance (`glance_table`)**
- A structured table: Marker, Latest Value + Unit, Reference, Status (flag), Stale flag (if > 180 days old)
- "Not tested" shown for parameters that have never appeared in any uploaded report
- Parameters ordered by urgency (red > yellow > green > not tested)

**3. Questions to Ask (`questions` — AHRQ-style QPL)**
- Grouped by organ system
- Each question has a checkbox the user can tick before a visit
- Questions are written in first-person ("My HbA1c has crossed…")
- Priority ordering within each group (most urgent first)
- A coaching note inline: "(Tick the questions that matter most to you before your visit. It is normal to feel a bit anxious writing these down.)"
- No question implies a diagnosis; each is framed as something to ask, not something the user already knows

**4. Lifestyle & Supplements to Discuss (`lifestyle_supplements`)**
- Tabular: Item / Why (from user's data) / Caution / Verdict / Citation
- Verdict vocabulary: "Reasonable to discuss" / "Check first" / "Discuss before adding" / "Unproven — discuss with clinician"
- `dose` is always null — no dose is ever shown. The word "dose" does not appear in this section.
- Contested items (NMN, metformin-for-longevity, rapamycin etc.) must carry contested framing: "No human outcome RCT. Contested."
- Evidence tier badge on each item

**5. Gaps Your Clinician Likely Missed (`gaps_clinician_missed`)**
- Derived server-side by the analysis layer (stale critical markers, never-tested markers the profile suggests should be tested)
- Framed as prompts to raise, not as criticism

**6. Disclaimer**
- Appended server-side in code, never model-generated
- Identical copy on every sheet; includes "Generated by AI · Not clinically validated · Educational only"

### PDF Export

A [PDF] button (or share icon) in the navigation bar renders the prep sheet as a PDF via a server-side endpoint `GET /v1/prep/reports/{id}/pdf`. The PDF is shared via the system share sheet. The PDF includes all sections and the disclaimer, formatted for A4 printing.

### Data

`POST /v1/prep/generate` → `202 { job_id }` (async)

`GET /v1/prep/jobs/{job_id}` → `{ status: 'pending'|'processing'|'done'|'failed', report_id? }`

`GET /v1/prep/reports/{report_id}` → `PrepReport` JSON

`GET /v1/prep/reports/{report_id}/pdf` → PDF binary (served via presigned S3 URL)

### Generation Polling

The app polls `GET /v1/prep/jobs/{job_id}` every 5 seconds while on this screen. If the user navigates away, a background push notification (if enabled) is sent when generation completes. On return, the completed sheet is displayed.

### Interactions / Navigation

- [Generate prep sheet] → starts async job, shows progress UI
- [PDF] / [↑ share] button → system share sheet with PDF
- Tap citation chip on any row → Citation Detail modal (Screen 18)
- [View previous sheets] → a list of past prep reports with date + summary; tapping loads a historical report in read-only mode
- Checkboxes on questions are local state only (not synced to server)

### Empty State (no lab reports uploaded)

"Upload at least one lab report before generating your prep sheet. Your prep sheet will be based on your most recent results." with [Upload a report →] CTA.

### Error State (generation failed)

"We were unable to generate your prep sheet. This sometimes happens when our AI system is busy. Please try again in a few minutes." with [Try again] button.

### Guardrail Failure (handled server-side)

If the Opus output fails any post-generation guardrail (dose present, uncited claim, banned phrase), the job status is `failed` from the user's perspective. The server logs the failure to the human-review queue (internal, not visible to user). User sees the generic error state and is prompted to retry. The retry triggers a clean regeneration, not the failed draft.

---

`[DESIGN: Screen 14 — Doctor-Visit Prep Sheet — to be attached]`

---

## Screen 15 — Biological Age (Opt-In, Secondary)

### Purpose

Shows the user's PhenoAge-computed biological age as a trend. This screen is explicitly secondary — it is never the headline, never above the fold, never drives suggestions. It exists to satisfy user curiosity about longitudinal aging trajectory while being unambiguous about its limitations and the population norm caveat.

### What the User Sees

Accessible only via the "Biological age trend (optional)" link on the Today tab, or from Settings. Never from the tab bar directly.

```
┌─────────────────────────────────────┐
│ ← Back    Biological Age Trend      │
├─────────────────────────────────────┤
│ ABOUT THIS ESTIMATE                 │
│                                     │
│ This is a rough estimate based on   │
│ 9 blood markers, using the PhenoAge │
│ formula (Levine, 2018). It          │
│ fluctuates with each lab draw and   │
│ is directional only — not a         │
│ clinical diagnosis.                 │
│                                     │
│ Based on US reference data (NHANES).│
│ May not be calibrated for           │
│ Indian populations.                 │
│ [Tier 2 · Levine 2018 PMC6388911 ↗]│
├─────────────────────────────────────┤
│ YOUR PHENOAGE TREND                 │
│                                     │
│  52 ┤       ●                       │
│  50 ┤     ●                         │
│  48 ┤   ●     ●                     │
│  46 ┤ ●           ●                 │
│     └─────────────────────────────  │
│      2022   2023   2024  2025  2026 │
│                                     │
│ Latest: 49.3 years                  │
│ Chronological age: 47 years         │
│ Difference: +2.3 years              │
│                                     │
│ "Directional only. This number      │
│  fluctuates day to day."            │
├─────────────────────────────────────┤
│ THE 9 INPUTS USED                   │
│                                     │
│ Marker          Value   Date        │
│ Albumin         4.2 g/dL  May 2026  │
│ Creatinine      0.91 mg/dL May 2026 │
│ Glucose (fast.) 102 mg/dL  May 2026 │
│ hsCRP           3.1 mg/L   May 2026 │
│ Lymphocyte %    32%         May 2026 │
│ MCV             88 fL       May 2026 │
│ RDW             13.4%       May 2026 │
│ ALP             72 U/L      May 2026 │
│ WBC             6.8 thou/µL May 2026 │
│ Age             47 years             │
│                                     │
│ Each input comes from your most     │
│ recent uploaded lab report.         │
├─────────────────────────────────────┤
│ WHAT THIS IS NOT                    │
│                                     │
│ · Not a diagnosis                   │
│ · Not a prediction of lifespan      │
│ · Not comparable between different  │
│   people or different methods       │
│ · Not a reason to change any        │
│   medication or supplement          │
├─────────────────────────────────────┤
│ Educational only · discuss any      │
│ result with your clinician.         │
└─────────────────────────────────────┘
```

### PhenoAge Display Rules

- The "latest" value is prominently shown but not in an oversized typography style — `title2` or `title3`, not `largeTitle`
- The difference from chronological age is shown as `+N.N years` or `-N.N years` with no value judgment attached (no "older than your age!" alarm copy)
- The disclaimer "Directional only. This number fluctuates day to day." appears directly beneath the value, in `.footnote` style, never hidden in fine print
- The NHANES population caveat appears on the screen, not just in a tooltip

### When PhenoAge Is Not Computable

If any of the 9 inputs is missing from the user's uploaded reports:

```
┌─────────────────────────────────────┐
│ Biological age is not yet           │
│ computable for you.                 │
│                                     │
│ All 9 inputs are needed:            │
│                                     │
│ ✓ Albumin (found)                   │
│ ✓ Creatinine (found)                │
│ ✓ Fasting glucose (found)           │
│ ✗ hsCRP (not in your reports yet)   │
│ ✓ Lymphocyte % (found)              │
│ ✓ MCV (found)                       │
│ ✓ RDW (found)                       │
│ ✓ ALP (found)                       │
│ ✓ WBC (found)                       │
│                                     │
│ Upload a report that includes       │
│ hsCRP to unlock this estimate.      │
└─────────────────────────────────────┘
```

No imputation. No partial score. If any input is missing, `computable = false` and the checklist above is shown. This is a hard rule from §2.3 and §11 decision 7.

### Data

`GET /v1/bioage` returns `BioAgeResult`:
- `computable: bool`
- `missing_inputs: string[]` (if `computable = false`)
- `value_years: number`
- `chrono_age: number`
- `delta_years: number`
- `trend: [{ date, value_years, chrono_age }]`
- `inputs_used: [{ parameter, value, unit, date, measurement_id }]` — the exact 9 rows used
- `confidence_caption: string`
- `caveats: string[]` (e.g., `trained_nhanes3`, `not_calibrated_india`)
- `source_id: string`

### Interactions / Navigation

- Citation chip → Citation Detail modal (Screen 18)
- Trend chart points: tap → tooltip with date and value
- "Upload a report" CTA (in not-computable state) → Upload screen (Screen 11)

---

`[DESIGN: Screen 15 — Biological Age Trend — to be attached]`

---

## Screen 16 — Span-Consultant (Voice)

### Purpose

A spoken Q&A interface grounded entirely in the user's own stored data. The bot reads lab values back, explains trends, and helps the user prepare questions for their clinician. It does not diagnose, does not prescribe, and does not answer questions that go beyond the user's stored data. Voice is the primary mode; text-chat is the always-available fallback (for accessibility and preference).

This screen is the most safety-critical surface in the app. Every design decision must preserve the triple guardrail: intent screening before the LLM, RAG grounding gate, and output trace before speaking.

### What the User Sees

**AI Disclosure Gate (shown every session, cannot be skipped):**
```
┌─────────────────────────────────────┐
│ Before you start                    │
├─────────────────────────────────────┤
│ 🤖 AI Disclosure                    │
│                                     │
│ Span-Consultant is an AI assistant. │
│ It is not a doctor and does not     │
│ give medical advice.                │
│                                     │
│ It can only discuss information     │
│ already in your Span records. It    │
│ will always ask you to discuss      │
│ findings with a clinician.          │
│                                     │
│ This session's transcript will be   │
│ stored in India and linked to your  │
│ account. Audio is not recorded.     │
│                                     │
│ This is a standalone consent.       │
│ You may revoke it in Settings.      │
│                                     │
│ [I understand — start session]      │
│ [Not now]                           │
└─────────────────────────────────────┘
```

**Active Session (voice mode):**
```
┌─────────────────────────────────────┐
│ ✕ End session    Span-Consultant    │
│                                     │
│ 🤖 AI · Not a doctor                │
├─────────────────────────────────────┤
│                                     │
│  [LIVE CAPTION VIEW]                │
│                                     │
│  Span: "Your HbA1c was 6.9%        │
│  as of June 8th, based on your      │
│  Tata 1mg report. This is above     │
│  the clinical reference range of    │
│  4 to 5.6 percent. I would          │
│  recommend discussing this with     │
│  your clinician."                   │
│                                     │
│  You: "What should I ask my doctor  │
│  about it?"                         │
│                                     │
│  Span: [thinking…]                  │
│                                     │
├─────────────────────────────────────┤
│ Agent state indicator:              │
│  ● Listening  ○ Thinking            │
│  ○ Speaking   ○ Escalated           │
├─────────────────────────────────────┤
│                                     │
│  [🎙 Hold to speak]                 │
│                                     │
│  [Switch to text →]                 │
└─────────────────────────────────────┘
```

**Text-Chat Fallback Mode:**
```
┌─────────────────────────────────────┐
│ ✕ End session    Span-Consultant    │
│ 🤖 AI · Not a doctor · Text mode   │
├─────────────────────────────────────┤
│ Span: Hello. I can discuss your     │
│ lab data with you. What would you   │
│ like to know?                       │
│                                     │
│ You: What is my latest HbA1c?       │
│                                     │
│ Span: Your most recent HbA1c was    │
│ 6.9%, recorded on June 8, 2026,     │
│ from a Tata 1mg report. The         │
│ clinical reference range is         │
│ 4.0–5.6%. Please discuss this       │
│ with your clinician.                │
│                                     │
├─────────────────────────────────────┤
│ [_________________________] [Send]  │
└─────────────────────────────────────┘
```

**Escalation State (emergency / symptomatic query detected):**
```
┌─────────────────────────────────────┐
│ Important                           │
│                                     │
│ You have mentioned something that   │
│ sounds like a medical emergency or  │
│ urgent symptom.                     │
│                                     │
│ Span cannot help with this.         │
│                                     │
│ If you need immediate help,         │
│ please call emergency services:     │
│                                     │
│ Emergency: 112                      │
│ NIMHANS helpline: 080-46110007      │
│                                     │
│ [End session]                       │
└─────────────────────────────────────┘
```

### Session Flow

1. User taps "Ask Span" button.
2. **AI disclosure gate** is shown and must be acknowledged before session starts (per EU AI Act high-risk requirement; 403 if not acked).
3. `POST /v1/voice/session` — server mints an ephemeral LiveKit token (TTL ≤ 60 seconds). The LiveKit token never touches the client's persistent storage.
4. App connects to LiveKit SFU via WebRTC. Audio session mode: `.voiceChat` (hardware echo cancellation).
5. **Push-to-talk mode** (default): user holds the mic button to speak; releases to send. An "Enable open mic" opt-in toggle is available in session settings.
6. Turn-end detection: server-side (Silero VAD + SmolLM-v2 turn-end model). Client does not make this decision.
7. Agent state is reflected in the UI: Listening → Thinking → Speaking → (if needed) Escalated.
8. Live captions are rendered from the transcript stream in real time.
9. On session end (user taps "End session" or session timeout): audio session is torn down; audio is discarded; transcript is persisted to `transcripts` table.
10. Transcript is available in session history (see below).

### Agent States

| State | Visual Indicator | Copy |
|---|---|---|
| Listening | Animated mic glyph, green pulse | "Listening…" |
| Thinking | Spinning indicator | "Thinking…" (may show "Let me check that…" filler) |
| Speaking | Animated waveform | Live caption text updates in real time |
| Escalated | Full-screen escalation card (orange background) | Fixed safety script shown; session ends |
| Idle / waiting | Static mic glyph | "Hold to speak" |

### Transcript History

After a session ends, the transcript is stored server-side. Users can view transcript history from the Settings screen (Screen 17). Transcripts are deleted if the user revokes voice consent. Audio is never stored (transcript-only, per §11 decision 9).

### Context Pre-Loading

When launched from a System Detail screen ("Ask Span about my [System]"), the session receives a pre-loaded context bundle: `{ system: systemKey, flagged_params: [...], latest_values: [...] }`. The voice agent's opening line references this context directly: "You have opened this about your [system name]. Your [lead marker] was [value] as of [date]. What would you like to know?"

### Voice Technology (India Stack)

- STT: Sarvam (India, all-in-country, DPDP processor agreement required)
- LLM: Sarvam (India); fallback to Gemini on Vertex asia-south1 if reasoning quality insufficient
- TTS: Sarvam (India)
- Audio never leaves the device without a WebRTC Opus connection to the LiveKit SFU (in-region, self-hosted)
- Claude is explicitly excluded from the India PHI path (Bedrock-India = global cross-region)

### Safety Rules Enforced in Code

1. **Emergency/symptomatic escalation:** Intent router classifies every user turn *before* it reaches the LLM. If classified as symptomatic or emergency, the escalation screen is shown immediately; the LLM is never invoked; a fixed safety script is spoken.
2. **Grounding gate:** The LLM only receives the user's stored `measurements`, `analysis_results`, and `scores` as context. It cannot access the internet, external references, or any data outside the user's own records.
3. **Output guardrail:** Every number the bot is about to speak is byte-traced to its source `measurement.id` in `grounded_sources`. If any number cannot be traced, the bot must not speak it; it says "I don't have that information in your records."
4. **No diagnosis, no dose:** The output guardrail strips any sentence that names a disease for the user or implies causation. The closing phrase of every substantive answer must include a deferral ("discuss this with your clinician").
5. **`audio_retained = false` by default:** Audio is never persisted. Transcript is persisted under voice consent scope.

### Consent Gate

Voice requires a standalone consent separate from the main DPDP consent (`scope: 'voice'`). This consent must be granted before any voice session can start. If not yet granted, the disclosure gate includes the consent grant as part of the "I understand — start session" action. Consent can be withdrawn in Settings, which deletes all transcripts.

### Data

`POST /v1/voice/session` → `{ ephemeral_token, session_id, context_bundle }`

`GET /v1/voice/sessions` → list of past sessions with date, duration, turn count

`GET /v1/voice/sessions/{id}/transcript` → paginated transcript

### Interactions / Navigation

- "I understand — start session" → session starts, audio permission requested if not granted
- "Not now" → dismisses to previous screen
- "Hold to speak" → PTT mode (default)
- "Enable open mic" → opens mic continuously (opt-in)
- "Switch to text →" → toggles to text-chat fallback (same session, same grounding)
- "End session" → tears down WebRTC, discards audio, saves transcript, returns to previous screen
- Escalation card "End session" → same as above

### Accessibility

- Live captions are always shown simultaneously with voice output
- Text-chat fallback is fully functional without a microphone permission
- Caption text size respects Dynamic Type

---

`[DESIGN: Screen 16 — Span-Consultant (Voice) — to be attached]`

---

## Screen 17 — Settings / Account

### Purpose

Central hub for profile management, consent control, data rights, HealthKit permissions, and account deletion. Must include in-app account deletion per App Store rule 5.1.1(v).

### What the User Sees

```
┌─────────────────────────────────────┐
│  Settings                           │
├─────────────────────────────────────┤
│ PROFILE                             │
│ Name (from Apple)   Anoop Prabhu    │
│ Date of birth       14 Mar 1979     │
│ Sex                 Male         >  │
│ Height / Weight     178 cm / 74 kg  │
│ BMI                 23.4            │
│ [Edit profile →]                    │
├─────────────────────────────────────┤
│ CONSENT & PRIVACY                   │
│                                     │
│ Lab report storage   Granted  [···] │
│ Processing reports   Granted  [···] │
│ Profile data         Granted  [···] │
│ Prep sheet           Granted  [···] │
│ Voice sessions       Granted  [···] │
│                                     │
│ Tapping a scope shows its purpose   │
│ and lets you withdraw consent.      │
├─────────────────────────────────────┤
│ HEALTHKIT                           │
│ HealthKit connected   Yes           │
│ Permissions                         │
│  Steps               Allowed        │
│  Sleep analysis      Allowed        │
│  Heart rate variab.  Allowed        │
│  Resting heart rate  Allowed        │
│  VO₂ max             Allowed        │
│ [Open Health app to manage →]       │
├─────────────────────────────────────┤
│ DATA                                │
│ [Export all my data →]              │
│ [View voice transcripts →]          │
├─────────────────────────────────────┤
│ ACCOUNT                             │
│ Sign out                            │
│ [Delete account →]                  │
├─────────────────────────────────────┤
│ ABOUT                               │
│ Version   1.0.0                     │
│ Privacy Policy  ↗                   │
│ Terms of Service  ↗                 │
│ Licences  ↗                         │
└─────────────────────────────────────┘
```

### Consent Management

Tapping any consent scope row opens a detail sheet showing:
- The exact consent copy displayed at the time it was granted
- The date it was granted
- What data is covered by this scope
- What happens if you withdraw: "Withdrawing this consent will prevent Span from [purpose]. Your existing [data type] will be deleted within 30 days."
- A "Withdraw consent" destructive action button

Withdrawing a consent scope:
- Immediately gates the corresponding feature
- Triggers the consent-withdrawal re-materialization pipeline server-side (e.g., withdrawing voice consent → transcripts deleted)
- Cannot be undone; re-granting requires going through the consent flow again

### Data Export

Tapping "Export all my data":
- Sends `POST /v1/account/export`
- Server prepares a machine-readable archive (JSON of all user rows + original PDFs) in-region
- A push notification or email (if user has provided one) signals readiness
- A presigned S3 download URL (short-lived) is returned and presented to the user
- Archive contents: all `measurements`, `reports` (original PDFs), `consents`, `scores`, `prep_reports` (JSON), `qol_entries`, `voice_sessions` (transcripts, no audio), `profiles`

### Account Deletion

Tapping "Delete account" shows a confirmation flow:

```
┌─────────────────────────────────────┐
│ Delete your Span account?           │
│                                     │
│ This will permanently delete:       │
│ · All your lab reports              │
│ · All measurements and trends       │
│ · Your profile and health data      │
│ · All prep sheets                   │
│ · All voice transcripts             │
│                                     │
│ This cannot be undone.              │
│                                     │
│ [Cancel]                            │
│ [Delete my account]   (destructive) │
└─────────────────────────────────────┘
```

Confirming deletion:
- Sends `DELETE /v1/account`
- Server sets `users.status = 'deletion_pending'` → cascade-delete PHI rows → delete S3 objects → Apple token revocation → tombstone directory entry
- App returns to the Sign In screen with message: "Your account is being deleted. This may take up to 72 hours."
- Audit log is retained (append-only, no PHI values)

### HealthKit

Span cannot detect whether a specific HealthKit permission has been denied (Apple limitation). The settings screen shows the last-known permission state from a local cache. A deep link to the iOS Health app is provided for managing permissions. If HealthKit data stops syncing, an inline banner in the Today tab ("Tap to check your HealthKit permissions") deep-links to this section.

### Voice Transcripts

"View voice transcripts" lists past sessions with date, duration, and a preview. Tapping a session shows the full transcript. A "Delete this transcript" option is available per session, as well as "Delete all transcripts."

### Data

`GET /v1/account` → profile + consent statuses

`PUT /v1/profiles` → profile edit

`POST /v1/account/export` → triggers export

`DELETE /v1/account` → triggers deletion

`GET /v1/consents` → list with status

`POST /v1/consents/{scope}/withdraw` → withdrawal

---

`[DESIGN: Screen 17 — Settings / Account — to be attached]`

---

## Screen 18 — Citation Detail (Modal / Sheet)

### Purpose

Every citation chip in the app leads here. Shows the full tiered source metadata: title, author/body, year, claim it supports, evidence tier, and a link to the original source. Never a full article viewer — just enough context to let the user understand the basis for a claim.

### What the User Sees

Presented as a `.sheet` (bottom-up modal). Short enough to be read without scrolling in most cases.

```
┌─────────────────────────────────────┐
│ ✕     Source                        │
├─────────────────────────────────────┤
│ TIER 1 — Consensus guideline        │
│                                     │
│ ADA Standards of Medical Care       │
│ in Diabetes — 2024                  │
│                                     │
│ American Diabetes Association       │
│ Diabetes Care, 2024                 │
│                                     │
│ This source supports:               │
│ HbA1c ≥ 6.5% as a diagnostic       │
│ threshold for type 2 diabetes,      │
│ and HbA1c < 5.7% as normal.        │
│                                     │
│ [Open source ↗]   (external link)   │
├─────────────────────────────────────┤
│ Evidence tiers:                     │
│ Tier 1 = consensus guidelines       │
│ Tier 2 = peer-reviewed research     │
│ Tier 3 = expert opinion / contested │
└─────────────────────────────────────┘
```

### Contested Source Display

For Tier 3 / contested sources:

```
┌─────────────────────────────────────┐
│ ✕     Source                        │
├─────────────────────────────────────┤
│ ⚠ TIER 3 — Contested / No human    │
│   outcome RCT                       │
│                                     │
│ NMN supplementation and NAD+        │
│ precursors in ageing                │
│                                     │
│ Relevant conflict of interest:      │
│ David Sinclair has commercial       │
│ interests in NMN.                   │
│                                     │
│ This source supports:               │
│ NMN may raise NAD+ levels in        │
│ humans (short-term studies only).   │
│ No long-term human outcome RCT.     │
│                                     │
│ [Open source ↗]                     │
└─────────────────────────────────────┘
```

### Data

`GET /v1/citations/{id}` returns `Source { id, tier, kind, title, citation_text, url, claim_supported, conflict_disclosure? }`

---

`[DESIGN: Screen 18 — Citation Detail — to be attached]`

---

## Appendix A — Resolved Decisions Reflected in This Spec

The following decisions from SPAN_MASTER_PLAN.md §11 are directly reflected in this spec. Engineers must not deviate from these without a new founder decision.

| Decision | Where reflected |
|---|---|
| India-only; `region='in'` for all users | S17 data export; S2 consent copy; S16 voice vendor |
| Gmail deferred — no mention in product | S11 Upload has only file picker + VisionKit; no Gmail option |
| User self-confirm review (no ops staff) | S12 is the user-facing review screen |
| Conservative optimal-band seed table | S10 chart shows optimal band only where it exists in the catalog |
| Trend baseline = first in-range reading | S10 baseline toggle |
| Lp(a) / creatinine never auto-converted; split by specimen | S12 unit picker; S10 parameter display |
| NHANES norms with India caveat | S10 "How unusual" card; S15 PhenoAge |
| WHO-5 + PROMIS only (EQ-5D / ESS excluded) | S13 instruments |
| Transcript-only voice (no audio retained) | S16 session flow + consent copy |
| Sarvam for India voice (STT + TTS + LLM) | S16 technology note |
| Profile captured at onboarding (structured) | S3–S5 |
| React PWA not a product surface | Not mentioned anywhere in this spec |
| Biological age never the headline | S7 collapsed link; S15 always secondary |
| No composite numeric score as headline | S7 tile layout; S8 |

---

## Appendix B — Empty State Library

All screens must handle these four empty state types consistently:

| Situation | Display pattern |
|---|---|
| No reports uploaded yet | Illustration + "Upload your first report" CTA with both upload options |
| Parameter exists but no readings for the user | "No readings yet for [X]. Upload a lab report that includes it." |
| Feature requires profile completion | "Complete your profile to unlock [feature]." with [Edit profile →] |
| Feature requires a completed check-in | "Complete a check-in to see [PROMIS bands / co-occurrence insights]." with [Start check-in →] |

All empty states avoid negative or alarming language. No "you haven't done X yet" framing — use "Upload to get started" or "Complete a check-in to see this."

---

## Appendix C — PhenoAge Not-Computable Checklist Parameters

In exact order as displayed on Screen 15:

1. Albumin (g/dL → g/L for formula; conversion: × 10)
2. Creatinine (mg/dL → µmol/L for formula; conversion: × 88.42)
3. Fasting glucose (mg/dL → mmol/L for formula; conversion: ÷ 18)
4. hsCRP (mg/L → mg/dL for formula; conversion: ÷ 10)
5. Lymphocyte %
6. MCV (fL)
7. RDW (%)
8. ALP (U/L)
9. WBC (× 1000 cells/µL)

If any of these 9 is missing from the user's uploaded reports, `bioage.computable = false`. There is no imputation. The checklist shows which are found (✓) and which are missing (✗).

---

*End of SCREENS.md*
