//
//  SpanEnums.swift
//  Span — shared domain vocabulary mirroring the backend.
//
//  The two color systems are kept as separate types on purpose (SCREENS.md):
//   • MeasurementFlag — per-point lab flag (High/Low/Normal)
//   • ZoneStatus      — three-zone traffic light at tile / band level
//

import SwiftUI

/// Per-measurement lab flag. Drives point-mark color in charts and the dot on a row.
enum MeasurementFlag: String, Codable, Hashable {
    case high
    case low
    case normal
    /// Non-numeric / not-tested marker (value == null).
    case none

    var color: Color {
        switch self {
        case .high:   return SpanColor.statusRed
        case .low:    return SpanColor.statusBlue
        case .normal: return SpanColor.statusGreen
        case .none:   return SpanColor.textTertiary
        }
    }

    /// Text label for the flag (always paired with color — never color-only, for VoiceOver).
    var label: String {
        switch self {
        case .high:   return "High"
        case .low:    return "Low"
        case .normal: return "Normal"
        case .none:   return "Not tested"
        }
    }
}

/// Three-zone traffic light for organ-system tiles and trend bands.
enum ZoneStatus: String, Codable, Hashable {
    /// ≥1 member parameter outside the clinical reference range.
    case attention
    /// All within clinical range, ≥1 outside the peer-reviewed optimal band.
    case monitor
    /// All measured parameters inside the optimal band (only where a cited band exists).
    case onTrack = "on_track"
    /// Fewer than the minimum measured parameters for a verdict.
    case notEnoughData = "not_enough_data"

    var color: Color {
        switch self {
        case .attention:     return SpanColor.statusRed
        case .monitor:       return SpanColor.statusYellow
        case .onTrack:       return SpanColor.statusGreen
        case .notEnoughData: return SpanColor.textTertiary
        }
    }

    var label: String {
        switch self {
        case .attention:     return "Attention"
        case .monitor:       return "Monitor"
        case .onTrack:       return "On track"
        case .notEnoughData: return "Not enough data"
        }
    }
}

/// Clinical-impact-aware trend direction. Direction is polarity-aware:
/// an LDL ↓ is "improving" (green), an eGFR ↓ is "worsening" (red). The backend
/// resolves polarity; the client only renders the resolved meaning.
enum TrendDirection: String, Codable, Hashable {
    case improving
    case worsening
    case stable
    /// n < 3 readings — no trend yet.
    case insufficientData = "insufficient_data"

    /// SF Symbol for the trend arrow.
    var symbolName: String {
        switch self {
        case .improving:        return "arrow.up.right"
        case .worsening:        return "arrow.up"
        case .stable:           return "arrow.right"
        case .insufficientData: return "minus"
        }
    }

    /// Color encodes clinical impact, not raw direction.
    var color: Color {
        switch self {
        case .improving:        return SpanColor.statusGreen
        case .worsening:        return SpanColor.statusRed
        case .stable:           return SpanColor.textSecondary
        case .insufficientData: return SpanColor.textTertiary
        }
    }

    var label: String {
        switch self {
        case .improving:        return "improving"
        case .worsening:        return "rising"
        case .stable:           return "stable"
        case .insufficientData: return "not enough data"
        }
    }
}

/// Evidence tier badge vocabulary (Citation chips + detail).
enum EvidenceTier: Int, Codable, Hashable {
    case tier1 = 1  // consensus guideline
    case tier2 = 2  // peer-reviewed research
    case tier3 = 3  // expert opinion / contested

    var label: String {
        switch self {
        case .tier1: return "Tier 1"
        case .tier2: return "Tier 2"
        case .tier3: return "Tier 3"
        }
    }

    var longLabel: String {
        switch self {
        case .tier1: return "Tier 1 — Consensus guideline"
        case .tier2: return "Tier 2 — Peer-reviewed research"
        case .tier3: return "Tier 3 — Expert opinion / contested"
        }
    }
}

/// The 8 organ systems (stable keys, used by the type-safe Route and the API).
enum SystemKey: String, Codable, Hashable, CaseIterable {
    case metabolic
    case cardiovascular
    case liver
    case kidney
    case inflammationImmune = "inflammation_immune"
    case hematologic
    case endocrineThyroid = "endocrine_thyroid"
    case micronutrientBone = "micronutrient_bone"

    var displayName: String {
        switch self {
        case .metabolic:          return "Metabolic"
        case .cardiovascular:     return "Heart"
        case .liver:              return "Liver"
        case .kidney:             return "Kidney"
        case .inflammationImmune: return "Inflammation"
        case .hematologic:        return "Blood"
        case .endocrineThyroid:   return "Hormones"
        case .micronutrientBone:  return "Nutrients"
        }
    }

    /// SF Symbol used on tiles and rows.
    var symbolName: String {
        switch self {
        case .metabolic:          return "drop.triangle"
        case .cardiovascular:     return "heart"
        case .liver:              return "cross.case"
        case .kidney:             return "drop"
        case .inflammationImmune: return "allergens"
        case .hematologic:        return "drop.fill"
        case .endocrineThyroid:   return "point.3.connected.trianglepath.dotted"
        case .micronutrientBone:  return "fork.knife"
        }
    }
}
