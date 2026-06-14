//
//  ZoneIndicator.swift
//  Span — a labelled zone pill (glowing dot + word), used on detail headers and
//  rows where a bare dot needs an explicit word ("🔴 Attention · 1 red, 2 amber…").
//

import SwiftUI

struct ZoneIndicator: View {
    let status: ZoneStatus
    /// Optional basis string, e.g. "1 red · 2 amber of 8 measured".
    var basis: String?

    var body: some View {
        HStack(spacing: SpanSpacing.xs) {
            TrafficLightDot(status: status, diameter: 8)
            Text(status.label)
                .font(SpanFont.headline.weight(.bold))
                .foregroundStyle(status.color)
            if let basis {
                Text("· \(basis)")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inline status badge as seen on parameter rows (a tinted capsule with the word).
/// Thin wrapper over `StatusBadge` so existing call-sites keep working.
struct ZoneBadge: View {
    let flag: MeasurementFlag

    var body: some View {
        StatusBadge(flag: flag, systemImage: badgeSymbol)
    }

    private var badgeSymbol: String? {
        switch flag {
        case .high: return "arrow.up"
        case .low:  return "arrow.down"
        case .normal: return "checkmark"
        case .none: return nil
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ZoneIndicator(status: .attention, basis: "1 red · 2 amber of 8 measured")
        ZoneIndicator(status: .onTrack, basis: nil)
        HStack { ZoneBadge(flag: .high); ZoneBadge(flag: .normal); ZoneBadge(flag: .low) }
    }
    .padding(40)
    .background(SpanColor.background)
}
