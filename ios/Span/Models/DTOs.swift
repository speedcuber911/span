//
//  DTOs.swift
//  Span — Codable structs that mirror the backend /v1 responses.
//
//  These are pure data carriers. NO medical logic lives here — the analysis layer
//  (SPAN_MASTER_PLAN §7) computes every score/band/frequency server-side and the
//  client only renders. snake_case JSON keys are mapped explicitly so the wire
//  format matches the TypeScript backend without a global decoder strategy.
//

import Foundation

// MARK: - Sources / citations (shared by many screens)

struct Source: Codable, Hashable, Identifiable {
    let id: String
    let tier: EvidenceTier
    /// e.g. "guideline", "research", "expert_opinion".
    let kind: String?
    let title: String
    /// Full bibliographic line, e.g. "American Diabetes Association · Diabetes Care, 2024".
    let citationText: String
    let url: String?
    let claimSupported: String?
    /// Present for contested / conflict-of-interest sources (Tier 3).
    let conflictDisclosure: String?

    enum CodingKeys: String, CodingKey {
        case id, tier, kind, title, url
        case citationText = "citation_text"
        case claimSupported = "claim_supported"
        case conflictDisclosure = "conflict_disclosure"
    }
}

// MARK: - GET /v1/overview  →  Today + Systems tabs

struct OverviewDTO: Codable, Hashable {
    let greetingName: String
    let asOf: Date
    let promis: PromisDTO?
    let attention: [AttentionItem]
    let systems: [SystemRollup]
    let bioageAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case promis, attention, systems
        case greetingName = "greeting_name"
        case asOf = "as_of"
        case bioageAvailable = "bioage_available"
    }
}

/// PROMIS Global-10 physical + mental bands. Only present if a check-in exists.
struct PromisDTO: Codable, Hashable {
    let gphTScore: Double
    let gphBand: String
    let gmhTScore: Double
    let gmhBand: String
    let basedOnDate: Date

    enum CodingKeys: String, CodingKey {
        case gphTScore = "gph_tscore"
        case gphBand = "gph_band"
        case gmhTScore = "gmh_tscore"
        case gmhBand = "gmh_band"
        case basedOnDate = "based_on_date"
    }
}

/// A parameter currently outside its clinical reference range (attention rail chip).
struct AttentionItem: Codable, Hashable, Identifiable {
    let canonicalParamId: String
    let parameter: String
    let flag: MeasurementFlag
    let latestValue: Double?
    let unit: String?

    var id: String { canonicalParamId }

    enum CodingKeys: String, CodingKey {
        case parameter, flag, unit
        case canonicalParamId = "canonical_param_id"
        case latestValue = "latest_value"
    }
}

/// One organ-system tile / row.
struct SystemRollup: Codable, Hashable, Identifiable {
    let key: SystemKey
    let status: ZoneStatus
    /// Lead marker display name, e.g. "HbA1c".
    let leadParameter: String
    let leadDirection: TrendDirection
    /// Count basis, e.g. "1 red · 2 yellow of 8 measured" — never a percentage.
    let statusBasis: String
    /// Last ~12 readings of the lead marker, oldest → newest, for the sparkline.
    let sparklinePoints: [Double]

    var id: SystemKey { key }

    enum CodingKeys: String, CodingKey {
        case key, status
        case leadParameter = "lead_parameter"
        case leadDirection = "lead_direction"
        case statusBasis = "status_basis"
        case sparklinePoints = "sparkline_points"
    }
}

// MARK: - GET /v1/systems/{key}  →  System Detail

struct SystemDetailDTO: Codable, Hashable {
    let key: SystemKey
    let displayName: String
    let subtitle: String?
    let status: ZoneStatus
    let statusBasis: String
    /// "Why this matters" ontology.
    let horseman: String?
    let hallmark: [String]
    let whyItMatters: String
    let whyCitations: [Source]
    let members: [SystemMember]

    enum CodingKeys: String, CodingKey {
        case key, status, subtitle, horseman, hallmark, members
        case displayName = "display_name"
        case statusBasis = "status_basis"
        case whyItMatters = "why_it_matters"
        case whyCitations = "why_citations"
    }
}

struct SystemMember: Codable, Hashable, Identifiable {
    let canonicalParamId: String
    let displayName: String
    let subtitle: String?
    let latestValue: Double?
    let valueText: String?
    let unit: String?
    let flag: MeasurementFlag
    let zoneStatus: ZoneStatus
    let direction: TrendDirection
    let sparklinePoints: [Double]
    /// e.g. "not tested", "needs fasting insulin", "computed score".
    let note: String?

    var id: String { canonicalParamId }

    /// Convenience: formatted latest value or an em-dash for null.
    var displayValue: String {
        if let v = latestValue {
            return v.formatted(.number.precision(.fractionLength(0...1)))
        }
        return valueText ?? "—"
    }

    enum CodingKeys: String, CodingKey {
        case subtitle, unit, flag, direction, note
        case canonicalParamId = "canonical_param_id"
        case displayName = "display_name"
        case latestValue = "latest_value"
        case valueText = "value_text"
        case zoneStatus = "zone_status"
        case sparklinePoints = "sparkline_points"
    }
}

// MARK: - GET /v1/parameters/{id} (+/trend)  →  Parameter Detail

struct ParameterDetailDTO: Codable, Hashable {
    let id: String
    let displayName: String
    let fullName: String?
    let category: String?
    let unit: String?
    let latestValue: Double?
    let latestFlag: MeasurementFlag
    let latestDate: Date?
    let latestLab: String?
    let about: String?
    let points: [TrendPoint]
    let refBand: ReferenceBand?
    let optimalBand: OptimalBand?
    let stat: ParameterStat?
    let citations: [Source]

    enum CodingKeys: String, CodingKey {
        case id, category, unit, about, points, stat, citations
        case displayName = "display_name"
        case fullName = "full_name"
        case latestValue = "latest_value"
        case latestFlag = "latest_flag"
        case latestDate = "latest_date"
        case latestLab = "latest_lab"
        case refBand = "ref_band"
        case optimalBand = "optimal_band"
    }
}

struct TrendPoint: Codable, Hashable, Identifiable {
    let date: Date
    /// nil for non-numeric readings ("Negative", "Trace") — rendered as annotated marker.
    let value: Double?
    let unit: String?
    let flag: MeasurementFlag
    let valueText: String?
    let lab: String?
    let refLow: Double?
    let refHigh: Double?

    var id: Date { date }

    enum CodingKeys: String, CodingKey {
        case date, value, unit, flag, lab
        case valueText = "value_text"
        case refLow = "ref_low"
        case refHigh = "ref_high"
    }
}

/// Clinical reference range (gray band).
struct ReferenceBand: Codable, Hashable {
    let low: Double?
    let high: Double?
    let sourceId: String?
    let refSourceLabel: String?

    enum CodingKeys: String, CodingKey {
        case low, high
        case sourceId = "source_id"
        case refSourceLabel = "ref_source_label"
    }
}

/// Peer-reviewed optimal band (light-green band). Only present where one exists.
struct OptimalBand: Codable, Hashable {
    let low: Double?
    let high: Double?
    /// "below" / "above" / "between".
    let direction: String?
    let evidenceTier: EvidenceTier
    let sourceId: String?
    let label: String

    enum CodingKeys: String, CodingKey {
        case low, high, direction, label
        case evidenceTier = "evidence_tier"
        case sourceId = "source_id"
    }
}

struct ParameterStat: Codable, Hashable {
    let slopePerYear: Double?
    let direction: TrendDirection
    let naturalFreq: NaturalFrequency?

    enum CodingKeys: String, CodingKey {
        case direction
        case slopePerYear = "slope_per_year"
        case naturalFreq = "natural_freq"
    }
}

/// "About N of 100 people…" — never a bare percentage (Gigerenzer).
struct NaturalFrequency: Codable, Hashable {
    let count: Int
    let denom: Int
    let comparatorDesc: String
    let caveat: String?

    enum CodingKeys: String, CodingKey {
        case count, denom, caveat
        case comparatorDesc = "comparator_desc"
    }
}

// MARK: - GET /v1/bioage  →  Biological Age

struct BioAgeResult: Codable, Hashable {
    let computable: Bool
    let missingInputs: [String]
    let valueYears: Double?
    let chronoAge: Double?
    let deltaYears: Double?
    let trend: [BioAgePoint]
    let inputsUsed: [BioAgeInput]
    let confidenceCaption: String?
    let caveats: [String]
    let sourceId: String?
    let source: Source?

    enum CodingKeys: String, CodingKey {
        case computable, trend, caveats, source
        case missingInputs = "missing_inputs"
        case valueYears = "value_years"
        case chronoAge = "chrono_age"
        case deltaYears = "delta_years"
        case inputsUsed = "inputs_used"
        case confidenceCaption = "confidence_caption"
        case sourceId = "source_id"
    }
}

struct BioAgePoint: Codable, Hashable, Identifiable {
    let date: Date
    let valueYears: Double
    let chronoAge: Double
    var id: Date { date }

    enum CodingKeys: String, CodingKey {
        case date
        case valueYears = "value_years"
        case chronoAge = "chrono_age"
    }
}

struct BioAgeInput: Codable, Hashable, Identifiable {
    let parameter: String
    let value: Double?
    let unit: String?
    let date: Date?
    let found: Bool
    var id: String { parameter }
}

// MARK: - Ingestion / Upload

enum IngestionStatus: String, Codable, Hashable {
    case intentCreated = "intent_created"
    case uploading
    case uploaded
    case enqueued
    case parsing
    case needsReview = "needs_review"
    case extracted
    case committed
    case failed
    case duplicate
    case quarantined
}

struct IngestionJob: Codable, Hashable, Identifiable {
    let id: String
    let filename: String
    let status: IngestionStatus
    /// 0...1 for uploading / parsing progress; nil for indeterminate.
    let progress: Double?
    /// e.g. "42 measurements saved" or "Low quality image".
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, status, progress, detail
    }
}

// MARK: - Prep sheet  →  POST /v1/prep/generate, GET /v1/prep/reports/{id}

struct PrepReport: Codable, Hashable, Identifiable {
    let id: String
    let generatedAt: Date
    let raiseFirst: RaiseFirst
    let glanceTable: [GlanceRow]
    let questions: [QuestionGroup]
    let lifestyleSupplements: [SupplementRow]
    let gapsClinicianMissed: [String]

    enum CodingKeys: String, CodingKey {
        case id, questions
        case generatedAt = "generated_at"
        case raiseFirst = "raise_first"
        case glanceTable = "glance_table"
        case lifestyleSupplements = "lifestyle_supplements"
        case gapsClinicianMissed = "gaps_clinician_missed"
    }
}

struct RaiseFirst: Codable, Hashable {
    let body: String
    let citations: [Source]
}

struct GlanceRow: Codable, Hashable, Identifiable {
    let marker: String
    let value: String
    let reference: String
    let flag: MeasurementFlag
    let stale: Bool
    var id: String { marker }
}

struct QuestionGroup: Codable, Hashable, Identifiable {
    let system: String
    let questions: [String]
    var id: String { system }
}

struct SupplementRow: Codable, Hashable, Identifiable {
    let item: String
    let why: String
    let caution: String?
    /// "Reasonable to discuss" / "Check first" / "Unproven — discuss with clinician".
    let verdict: String
    let citations: [Source]
    var id: String { item }
}

// MARK: - Check-in  →  GET /v1/checkin/next, POST /v1/checkin/responses

struct CheckinInstrument: Codable, Hashable {
    let instrumentId: String
    let instrumentName: String
    let intro: String?
    let items: [CheckinItem]

    enum CodingKeys: String, CodingKey {
        case intro, items
        case instrumentId = "instrument_id"
        case instrumentName = "instrument_name"
    }
}

struct CheckinItem: Codable, Hashable, Identifiable {
    let key: String
    let prompt: String
    let scaleMin: Int
    let scaleMax: Int
    /// Ordered labels high→low (e.g. "All the time" … "At no time").
    let scaleLabels: [String]
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, prompt
        case scaleMin = "scale_min"
        case scaleMax = "scale_max"
        case scaleLabels = "scale_labels"
    }
}
