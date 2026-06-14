//
//  MockSpanAPI.swift
//  Span — realistic sample data so the whole app RUNS and every #Preview works
//  without the backend. Numbers are illustrative, not a real person.
//

import Foundation

struct MockSpanAPI: SpanAPI {

    /// Toggle to exercise empty / loading paths from previews if desired.
    var simulatedLatency: Duration = .milliseconds(150)

    private func delay() async {
        try? await Task.sleep(for: simulatedLatency)
    }

    private static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: iso) ?? Date()
    }

    // MARK: Overview

    func overview() async throws -> OverviewDTO {
        await delay()
        return Self.sampleOverview
    }

    static let sampleOverview = OverviewDTO(
        greetingName: "Anoop",
        asOf: Date(),
        promis: PromisDTO(
            gphTScore: 48, gphBand: "Average",
            gmhTScore: 56, gmhBand: "Good",
            basedOnDate: date("2026-06-10")
        ),
        attention: [
            AttentionItem(canonicalParamId: "ldl", parameter: "LDL", flag: .high, latestValue: 157, unit: "mg/dL"),
            AttentionItem(canonicalParamId: "hba1c", parameter: "HbA1c", flag: .high, latestValue: 6.9, unit: "%"),
            AttentionItem(canonicalParamId: "uric_acid", parameter: "Uric Acid", flag: .high, latestValue: 7.2, unit: "mg/dL")
        ],
        systems: [
            SystemRollup(key: .metabolic, status: .attention, leadParameter: "HbA1c", leadDirection: .worsening,
                         statusBasis: "1 red · 2 yellow of 8 measured", sparklinePoints: [5.6, 5.8, 6.0, 6.2, 6.4, 6.7, 6.9]),
            SystemRollup(key: .cardiovascular, status: .monitor, leadParameter: "ApoB", leadDirection: .stable,
                         statusBasis: "0 red · 3 yellow of 9 measured", sparklinePoints: [88, 92, 90, 95, 96, 94, 95]),
            SystemRollup(key: .kidney, status: .onTrack, leadParameter: "eGFR", leadDirection: .improving,
                         statusBasis: "0 red · 0 yellow of 4 measured", sparklinePoints: [78, 80, 82, 83, 84, 85, 86]),
            SystemRollup(key: .liver, status: .onTrack, leadParameter: "ALT", leadDirection: .stable,
                         statusBasis: "0 red · 1 yellow of 7 measured", sparklinePoints: [28, 30, 29, 31, 30, 30, 29]),
            SystemRollup(key: .endocrineThyroid, status: .monitor, leadParameter: "TSH", leadDirection: .worsening,
                         statusBasis: "0 red · 1 yellow of 3 measured", sparklinePoints: [2.1, 2.4, 2.9, 3.4, 3.9, 4.3, 4.6]),
            SystemRollup(key: .inflammationImmune, status: .onTrack, leadParameter: "hs-CRP", leadDirection: .stable,
                         statusBasis: "0 red · 0 yellow of 5 measured", sparklinePoints: [0.9, 1.1, 1.0, 0.8, 0.9, 1.0, 0.9]),
            SystemRollup(key: .micronutrientBone, status: .monitor, leadParameter: "Vitamin D", leadDirection: .improving,
                         statusBasis: "0 red · 2 yellow of 6 measured", sparklinePoints: [18, 22, 24, 26, 28, 31, 33]),
            SystemRollup(key: .hematologic, status: .onTrack, leadParameter: "Hemoglobin", leadDirection: .stable,
                         statusBasis: "0 red · 0 yellow of 11 measured", sparklinePoints: [14.1, 14.2, 14.0, 14.3, 14.2, 14.1, 14.2])
        ],
        bioageAvailable: true
    )

    // MARK: System detail

    func systemDetail(_ key: SystemKey) async throws -> SystemDetailDTO {
        await delay()
        return Self.sampleMetabolicDetail
    }

    static let sampleMetabolicDetail = SystemDetailDTO(
        key: .metabolic,
        displayName: "Metabolic",
        subtitle: "Energy synthesis & storage",
        status: .attention,
        statusBasis: "1 red · 2 yellow of 8 measured",
        horseman: "Metabolic dysfunction",
        hallmark: ["Deregulated nutrient-sensing", "Chronic inflammation"],
        whyItMatters: "Metabolic dysfunction is a primary driver of chronic disease. Optimizing these markers directly impacts healthspan by addressing the root cause of the Four Horsemen diseases.",
        whyCitations: [Self.adaSource, Self.attiaSource],
        members: [
            SystemMember(canonicalParamId: "hba1c", displayName: "HbA1c", subtitle: "Average blood sugar (3 mo)",
                         latestValue: 6.9, valueText: nil, unit: "%", flag: .high, zoneStatus: .attention,
                         direction: .worsening, sparklinePoints: [5.6, 5.8, 6.0, 6.2, 6.4, 6.7, 6.9], note: nil),
            SystemMember(canonicalParamId: "fasting_glucose", displayName: "Fasting Glucose", subtitle: "Blood sugar at rest",
                         latestValue: 102, valueText: nil, unit: "mg/dL", flag: .normal, zoneStatus: .monitor,
                         direction: .improving, sparklinePoints: [110, 108, 106, 104, 103, 102, 102], note: nil),
            SystemMember(canonicalParamId: "tyg", displayName: "TyG index", subtitle: "Insulin resistance · trend only",
                         latestValue: 8.7, valueText: nil, unit: nil, flag: .normal, zoneStatus: .monitor,
                         direction: .stable, sparklinePoints: [8.5, 8.6, 8.7, 8.7, 8.6, 8.7, 8.7], note: "computed score · no fixed cutoff"),
            SystemMember(canonicalParamId: "bmi", displayName: "BMI", subtitle: "Body Mass Index",
                         latestValue: 26.1, valueText: nil, unit: nil, flag: .normal, zoneStatus: .onTrack,
                         direction: .improving, sparklinePoints: [28.0, 27.5, 27.0, 26.6, 26.3, 26.1, 26.1], note: nil),
            SystemMember(canonicalParamId: "triglycerides", displayName: "Triglycerides", subtitle: nil,
                         latestValue: 148, valueText: nil, unit: "mg/dL", flag: .normal, zoneStatus: .monitor,
                         direction: .worsening, sparklinePoints: [120, 128, 132, 138, 142, 145, 148], note: nil),
            SystemMember(canonicalParamId: "fasting_insulin", displayName: "Fasting insulin", subtitle: nil,
                         latestValue: nil, valueText: nil, unit: nil, flag: .none, zoneStatus: .notEnoughData,
                         direction: .insufficientData, sparklinePoints: [], note: "not tested"),
            SystemMember(canonicalParamId: "homa_ir", displayName: "HOMA-IR", subtitle: nil,
                         latestValue: nil, valueText: nil, unit: nil, flag: .none, zoneStatus: .notEnoughData,
                         direction: .insufficientData, sparklinePoints: [], note: "needs fasting insulin")
        ]
    )

    // MARK: Parameter detail

    func parameterDetail(_ id: String) async throws -> ParameterDetailDTO {
        await delay()
        return Self.sampleHbA1c
    }

    static let sampleHbA1c = ParameterDetailDTO(
        id: "hba1c",
        displayName: "HbA1c",
        fullName: "Glycated Haemoglobin",
        category: "Metabolic",
        unit: "%",
        latestValue: 6.9,
        latestFlag: .high,
        latestDate: date("2026-06-08"),
        latestLab: "Tata 1mg",
        about: "HbA1c reflects your average blood sugar over the past 2–3 months. Values above 6.5% are the diagnostic threshold for diabetes in most guidelines.",
        points: [
            TrendPoint(date: date("2023-10-12"), value: 5.6, unit: "%", flag: .normal, valueText: nil, lab: "Tata 1mg", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2024-03-14"), value: 5.9, unit: "%", flag: .high, valueText: nil, lab: "Thyrocare", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2024-08-20"), value: 6.2, unit: "%", flag: .high, valueText: nil, lab: "Healthians", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2025-06-20"), value: 6.4, unit: "%", flag: .high, valueText: nil, lab: "Tata 1mg", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2025-12-01"), value: 7.0, unit: "%", flag: .high, valueText: nil, lab: "Healthians", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2026-03-14"), value: 7.1, unit: "%", flag: .high, valueText: nil, lab: "Thyrocare", refLow: 4.0, refHigh: 5.6),
            TrendPoint(date: date("2026-06-08"), value: 6.9, unit: "%", flag: .high, valueText: nil, lab: "Tata 1mg", refLow: 4.0, refHigh: 5.6)
        ],
        refBand: ReferenceBand(low: 4.0, high: 5.6, sourceId: "icmr-2023", refSourceLabel: "ICMR 2023 guideline"),
        optimalBand: OptimalBand(low: nil, high: 5.5, direction: "below", evidenceTier: .tier3,
                                 sourceId: "attia-2023", label: "Optimal target: < 5.5%"),
        stat: ParameterStat(slopePerYear: 0.32, direction: .worsening,
                            naturalFreq: NaturalFrequency(count: 23, denom: 100,
                                comparatorDesc: "About 23 of 100 people your age and sex have HbA1c this high.",
                                caveat: "Based on NHANES reference data. May not be calibrated for Indian populations.")),
        citations: [Self.icmrSource, Self.attiaSource, Self.adaSource]
    )

    // MARK: Bio age

    func bioAge() async throws -> BioAgeResult {
        await delay()
        return Self.sampleBioAge
    }

    static let sampleBioAge = BioAgeResult(
        computable: true,
        missingInputs: [],
        valueYears: 24.8,
        chronoAge: 28.0,
        deltaYears: -3.2,
        trend: [
            BioAgePoint(date: date("2022-01-01"), valueYears: 27.0, chronoAge: 24),
            BioAgePoint(date: date("2023-01-01"), valueYears: 26.2, chronoAge: 25),
            BioAgePoint(date: date("2024-01-01"), valueYears: 25.8, chronoAge: 26),
            BioAgePoint(date: date("2025-01-01"), valueYears: 25.1, chronoAge: 27),
            BioAgePoint(date: date("2026-05-01"), valueYears: 24.8, chronoAge: 28)
        ],
        inputsUsed: [
            BioAgeInput(parameter: "Albumin", value: 4.2, unit: "g/dL", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "Creatinine", value: 0.91, unit: "mg/dL", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "Glucose", value: 102, unit: "mg/dL", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "C-Reactive Protein (CRP)", value: 3.1, unit: "mg/L", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "Lymphocyte %", value: 32, unit: "%", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "Mean Corpuscular Volume", value: 88, unit: "fL", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "RDW", value: 13.4, unit: "%", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "Alkaline Phosphatase", value: 72, unit: "U/L", date: date("2026-05-01"), found: true),
            BioAgeInput(parameter: "White Blood Cell Count", value: 6.8, unit: "10³/µL", date: date("2026-05-01"), found: true)
        ],
        confidenceCaption: "Directional only. This number fluctuates day to day.",
        caveats: ["trained_nhanes3", "not_calibrated_india"],
        sourceId: "levine-2018",
        source: Self.levineSource
    )

    // MARK: Citations

    func citation(_ id: String) async throws -> Source {
        await delay()
        return [Self.adaSource, Self.icmrSource, Self.attiaSource, Self.levineSource, Self.nmnSource]
            .first { $0.id == id } ?? Self.adaSource
    }

    // MARK: Ingestion

    func ingestionJobs() async throws -> [IngestionJob] {
        await delay()
        return [
            IngestionJob(id: "1", filename: "Quest_Diagnostics_Jan24.pdf", status: .parsing, progress: 0.7, detail: "Parsing · usually <2 min"),
            IngestionJob(id: "2", filename: "Scan_2024-02-15.jpg", status: .needsReview, progress: nil, detail: "Needs review · low quality image"),
            IngestionJob(id: "3", filename: "LabCorp_Metabolic_Panel.pdf", status: .committed, progress: nil, detail: "32 markers extracted"),
            IngestionJob(id: "4", filename: "Thyrocare_Mar26.pdf", status: .committed, progress: nil, detail: "42 measurements saved"),
            IngestionJob(id: "5", filename: "Healthians_Dec25.pdf", status: .duplicate, progress: nil, detail: "Already in Span")
        ]
    }

    // MARK: Check-in

    func checkinNext() async throws -> CheckinInstrument {
        await delay()
        return CheckinInstrument(
            instrumentId: "who5",
            instrumentName: "WHO-5",
            intro: "Over the past two weeks…",
            items: [
                CheckinItem(key: "who5_1", prompt: "Over the past two weeks, I have felt cheerful and in good spirits.",
                            scaleMin: 0, scaleMax: 5,
                            scaleLabels: ["All the time", "Most of the time", "More than half the time",
                                          "Less than half the time", "Some of the time", "At no time"]),
                CheckinItem(key: "who5_2", prompt: "Over the past two weeks, I have felt calm and relaxed.",
                            scaleMin: 0, scaleMax: 5,
                            scaleLabels: ["All the time", "Most of the time", "More than half the time",
                                          "Less than half the time", "Some of the time", "At no time"])
            ]
        )
    }

    // MARK: Prep

    func prepReport() async throws -> PrepReport {
        await delay()
        return Self.samplePrep
    }

    static let samplePrep = PrepReport(
        id: "prep-1",
        generatedAt: date("2026-06-14"),
        raiseFirst: RaiseFirst(
            body: "Your HbA1c has risen from 6.4% to 6.9% over the past year, now above the diagnostic threshold for type 2 diabetes. This is your most urgent trend to discuss.",
            citations: [Self.adaSource]),
        glanceTable: [
            GlanceRow(marker: "HbA1c", value: "6.9%", reference: "<5.6%", flag: .high, stale: false),
            GlanceRow(marker: "LDL", value: "157 mg/dL", reference: "<100", flag: .high, stale: false),
            GlanceRow(marker: "ApoB", value: "—", reference: "<90", flag: .none, stale: false),
            GlanceRow(marker: "eGFR", value: "82", reference: ">60", flag: .normal, stale: false),
            GlanceRow(marker: "hs-CRP", value: "3.1 mg/L", reference: "<1.0", flag: .high, stale: false)
        ],
        questions: [
            QuestionGroup(system: "Metabolic", questions: [
                "My HbA1c has crossed 6.5% — should I be tested for diabetes?",
                "Is my fasting glucose pattern concerning given my family history?"
            ]),
            QuestionGroup(system: "Heart & Arteries", questions: [
                "My LDL has risen to 157 — what is my cardiovascular risk?",
                "Should I test ApoB and Lp(a)? I have not had these tested."
            ]),
            QuestionGroup(system: "Inflammation", questions: [
                "My hs-CRP is elevated. What could be driving this?"
            ])
        ],
        lifestyleSupplements: [
            SupplementRow(item: "Omega-3 (fish oil)", why: "Omega-3 index 4.2% may be below 8%.",
                          caution: "Discuss dose with your doctor.",
                          verdict: "Reasonable to discuss", citations: [Self.adaSource]),
            SupplementRow(item: "NMN", why: "Interest in NAD+ precursors for ageing.",
                          caution: "No human outcome RCT. Contested.",
                          verdict: "Unproven — discuss with clinician", citations: [Self.nmnSource])
        ],
        gapsClinicianMissed: [
            "ApoB last tested Jan 2024 despite LDL rising +40% since.",
            "Lp(a) never tested (one-time genetic test; recommended in ACC/AHA 2022 guidance).",
            "ACR (urine albumin-creatinine ratio) only tested once."
        ]
    )

    // MARK: Sample sources

    static let adaSource = Source(
        id: "ada-2024", tier: .tier1, kind: "guideline",
        title: "ADA Standards of Medical Care in Diabetes — 2024",
        citationText: "American Diabetes Association · Diabetes Care, 2024",
        url: "https://diabetesjournals.org/care",
        claimSupported: "HbA1c ≥ 6.5% as a diagnostic threshold for type 2 diabetes, and HbA1c < 5.7% as normal.",
        conflictDisclosure: nil)

    static let icmrSource = Source(
        id: "icmr-2023", tier: .tier1, kind: "guideline",
        title: "ICMR Guidelines for Management of Type 2 Diabetes — 2023",
        citationText: "Indian Council of Medical Research, 2023",
        url: "https://www.icmr.gov.in",
        claimSupported: "Clinical reference range for HbA1c of 4.0–5.6% in non-diabetic adults.",
        conflictDisclosure: nil)

    static let attiaSource = Source(
        id: "attia-2023", tier: .tier3, kind: "expert_opinion",
        title: "Outlive — optimal metabolic targets (expert opinion)",
        citationText: "Peter Attia, MD · Outlive, 2023",
        url: nil,
        claimSupported: "An optimal HbA1c target below 5.5% for longevity (expert opinion · discuss with clinician).",
        conflictDisclosure: nil)

    static let levineSource = Source(
        id: "levine-2018", tier: .tier2, kind: "research",
        title: "An epigenetic biomarker of aging for lifespan and healthspan",
        citationText: "Levine et al. · Aging, 2018 · PMC6388911",
        url: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6388911",
        claimSupported: "PhenoAge derived from 9 clinical markers + chronological age (NHANES III).",
        conflictDisclosure: nil)

    static let nmnSource = Source(
        id: "nmn-contested", tier: .tier3, kind: "expert_opinion",
        title: "NMN supplementation and NAD+ precursors in ageing",
        citationText: "Selected short-term human studies · contested",
        url: nil,
        claimSupported: "NMN may raise NAD+ levels in humans (short-term studies only). No long-term human outcome RCT.",
        conflictDisclosure: "David Sinclair has commercial interests in NMN.")
}
