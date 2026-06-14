# src/analysis — Scoring Engine

Server-side medical math. All scoring logic runs here — never on-device.

Implements the validated models from SPAN_MASTER_PLAN.md §7 (§2.2 / §2.3):

Core (Phase 1):
- PhenoAge biological age (Levine 2018, PMC6388911) — 9 labs + chronological age, exact coefficients
- CKD-EPI 2021 race-free eGFR (Inker NEJM 2021) — use 2021 exponents, NOT 2009
- FIB-4 liver fibrosis (Sterling 2006) — age > 65 uses cutoff 2.0 not 1.45
- NAFLD-FS (Angulo 2007, PMID 17393509) — gated: needs BMI + diabetes/IFG flag
- TyG index (insulin resistance) — trend/relative only, no universal cutoff
- HOMA-IR — only when fasting insulin is present
- NLR / AAR (De Ritis ratio) / PLR — soft flags / longitudinal trends only

Phase 2 (deferred):
- KDM biological age (requires NHANES reference cohort fit)
- Homeostatic Dysregulation / Mahalanobis distance (requires reference cohort, recalibrate for India)
- Allostatic Load blood subscore (quartile cutoffs from Span's own population)
- SCORE2 / ASCVD — gated on BP + smoking at onboarding; display with explicit not-calibrated-for-India caveat

IMPORTANT: Unit handling is the #1 implementation bug. PhenoAge inputs must be in exact units
(CRP mg/dL, creatinine µmol/L, glucose mmol/L, albumin g/L). Conversions live here.
