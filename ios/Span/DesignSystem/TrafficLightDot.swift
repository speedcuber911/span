//
//  TrafficLightDot.swift
//  Span — the glowing three-zone status dot (.dot / .dr / .dy / .dg / .dgr).
//
//  Never color-only: always carries an accessibility label so VoiceOver announces
//  the status text too. The red dot glows hard (box-shadow 0 0 7px rgba(.6)); amber
//  and green glow softly; the "no data" dot (--b2) does not glow.
//

import SwiftUI

struct TrafficLightDot: View {
    let status: ZoneStatus
    var diameter: CGFloat = 8

    private var glowOpacity: Double {
        switch status {
        case .attention:     return 0.6   // red glows strongest (comp)
        case .monitor:       return 0.3
        case .onTrack:       return 0.3
        case .notEnoughData: return 0      // --b2 dot, no glow
        }
    }

    private var glowRadius: CGFloat { status == .attention ? 7 : 5 }

    private var fill: Color {
        status == .notEnoughData ? SpanColor.borderStrong : status.color
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .spanGlow(status.color, radius: glowRadius, opacity: glowOpacity)
            .accessibilityLabel("Status: \(status.label)")
    }
}

/// A small flag dot keyed off a per-measurement flag (High/Low/Normal).
struct FlagDot: View {
    let flag: MeasurementFlag
    var diameter: CGFloat = 8

    private var glowOpacity: Double {
        switch flag {
        case .high:   return 0.6
        case .low:    return 0.4
        case .normal: return 0.3
        case .none:   return 0
        }
    }

    private var fill: Color {
        flag == .none ? SpanColor.borderStrong : flag.color
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .spanGlow(flag.color, radius: flag == .high ? 7 : 5, opacity: glowOpacity)
            .accessibilityLabel("Flag: \(flag.label)")
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach([ZoneStatus.attention, .monitor, .onTrack, .notEnoughData], id: \.self) {
            TrafficLightDot(status: $0, diameter: 12)
        }
    }
    .padding(40)
    .background(SpanColor.background)
}
