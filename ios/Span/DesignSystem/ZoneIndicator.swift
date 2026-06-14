//
//  ZoneIndicator.swift
//  Span — a labelled zone pill (dot + text), used on detail headers and rows
//  where a bare dot needs an explicit word ("🔴 attention · 1 red, 2 yellow…").
//

import SwiftUI

struct ZoneIndicator: View {
    let status: ZoneStatus
    /// Optional basis string, e.g. "1 red · 2 yellow of 8 measured".
    var basis: String?

    var body: some View {
        HStack(spacing: SpanSpacing.xs) {
            TrafficLightDot(status: status, diameter: 10)
            Text(status.label.lowercased())
                .font(SpanFont.callout.weight(.medium))
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
struct ZoneBadge: View {
    let flag: MeasurementFlag

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeSymbol)
                .font(.system(size: 10, weight: .semibold))
            Text(flag.label)
                .font(SpanFont.caption2)
        }
        .foregroundStyle(flag.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(flag.color.opacity(0.12), in: Capsule())
        .accessibilityLabel("Flagged \(flag.label)")
    }

    private var badgeSymbol: String {
        switch flag {
        case .high: return "arrow.up"
        case .low:  return "arrow.down"
        case .normal: return "checkmark"
        case .none: return "minus"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ZoneIndicator(status: .attention, basis: "1 red · 2 yellow of 8 measured")
        ZoneIndicator(status: .onTrack, basis: nil)
        HStack { ZoneBadge(flag: .high); ZoneBadge(flag: .normal); ZoneBadge(flag: .low) }
    }
    .padding()
    .background(SpanColor.background)
}
