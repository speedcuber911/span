//
//  StatusBadge.swift
//  Span — the `.bdg` status pill.
//
//  Tinted capsule with a colored fill (rgba .08–.1), a 0.5px colored border, and
//  matching foreground. Variants map 1:1 to the comp:
//   • .high     → .br  (red)
//   • .monitor  → .by  (amber)
//   • .optimal  → .bgs (green)
//   • .info     → .bb  (purple accent)
//   • .neutral  → .bgr (muted, e.g. "Not tested")
//
//  Optional leading SF Symbol (e.g. trend arrow) and trailing text. Never relies on
//  color alone — the word is always present for VoiceOver.
//

import SwiftUI

enum StatusBadgeStyle {
    case high, monitor, optimal, info, neutral

    var foreground: Color {
        switch self {
        case .high:    return SpanColor.statusRed
        case .monitor: return SpanColor.statusYellow
        case .optimal: return SpanColor.statusGreen
        case .info:    return SpanColor.accent
        case .neutral: return SpanColor.textSecondary
        }
    }

    var fill: Color {
        switch self {
        case .high:    return SpanColor.statusRedBg
        case .monitor: return SpanColor.statusYellowBg
        case .optimal: return SpanColor.statusGreenBg
        case .info:    return SpanColor.accentBg
        case .neutral: return SpanColor.surfaceCard
        }
    }

    var border: Color {
        switch self {
        case .high:    return SpanColor.statusRedBorder
        case .monitor: return SpanColor.statusYellowBorder
        case .optimal: return SpanColor.statusGreenBorder
        case .info:    return SpanColor.accentBorder
        case .neutral: return SpanColor.border
        }
    }

    /// Map a three-zone status to a badge style.
    init(zone: ZoneStatus) {
        switch zone {
        case .attention:     self = .high
        case .monitor:       self = .monitor
        case .onTrack:       self = .optimal
        case .notEnoughData: self = .neutral
        }
    }

    /// Map a per-measurement flag to a badge style.
    init(flag: MeasurementFlag) {
        switch flag {
        case .high:   self = .high
        case .low:    self = .info
        case .normal: self = .optimal
        case .none:   self = .neutral
        }
    }
}

struct StatusBadge: View {
    let text: String
    var style: StatusBadgeStyle = .neutral
    /// Optional leading SF Symbol (e.g. "arrow.up", "arrow.down").
    var systemImage: String? = nil
    /// Slightly larger variant for detail headers.
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: prominent ? 11 : 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: prominent ? 11 : 9.5, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, prominent ? 10 : 8)
        .padding(.vertical, prominent ? 4 : 2.5)
        .background(style.fill, in: RoundedRectangle(cornerRadius: SpanRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.badge, style: .continuous)
                .strokeBorder(style.border, lineWidth: SpanSpacing.hairline)
        )
        .accessibilityLabel("Status: \(text)")
    }
}

extension StatusBadge {
    /// Convenience: badge for a zone status, label = the status word.
    init(zone: ZoneStatus, systemImage: String? = nil, prominent: Bool = false) {
        self.init(text: zone.label, style: StatusBadgeStyle(zone: zone),
                  systemImage: systemImage, prominent: prominent)
    }
    /// Convenience: badge for a measurement flag, label = the flag word.
    init(flag: MeasurementFlag, systemImage: String? = nil, prominent: Bool = false) {
        self.init(text: flag.label, style: StatusBadgeStyle(flag: flag),
                  systemImage: systemImage, prominent: prominent)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StatusBadge(text: "High ↑", style: .high, systemImage: "arrow.up")
        StatusBadge(text: "Monitor", style: .monitor)
        StatusBadge(text: "Optimal", style: .optimal)
        StatusBadge(text: "Vit D 13", style: .info, systemImage: "arrow.down")
        StatusBadge(text: "Not tested", style: .neutral)
        StatusBadge(zone: .attention)
        StatusBadge(flag: .high, systemImage: "arrow.up", prominent: true)
    }
    .padding(40)
    .background(SpanColor.background)
}
