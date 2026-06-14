//
//  TrafficLightDot.swift
//  Span — the three-zone status dot. Never color-only: always carries an
//  accessibility label so VoiceOver announces the status text too.
//

import SwiftUI

struct TrafficLightDot: View {
    let status: ZoneStatus
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(false)
            .accessibilityLabel("Status: \(status.label)")
    }
}

/// A small flag dot keyed off a per-measurement flag (High/Low/Normal).
struct FlagDot: View {
    let flag: MeasurementFlag
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(flag.color)
            .frame(width: diameter, height: diameter)
            .accessibilityLabel("Flag: \(flag.label)")
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach([ZoneStatus.attention, .monitor, .onTrack, .notEnoughData], id: \.self) {
            TrafficLightDot(status: $0, diameter: 14)
        }
    }
    .padding()
    .background(SpanColor.background)
}
