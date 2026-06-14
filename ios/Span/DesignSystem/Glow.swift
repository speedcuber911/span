//
//  Glow.swift
//  Span — the status-dot / bio-age-ring glow.
//
//  The comp gives status dots a colored box-shadow (e.g. the red dot:
//  box-shadow:0 0 7px rgba(255,45,85,.6)) and the bio-age ring a
//  drop-shadow(0 0 10px rgba(48,209,88,.4)). We reproduce that with a layered
//  shadow modifier. Respects Reduce Transparency by dimming the glow.
//

import SwiftUI

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let o = reduceTransparency ? opacity * 0.4 : opacity
        return content
            .shadow(color: color.opacity(o), radius: radius)
    }
}

extension View {
    /// Apply a colored glow (the comp's status-dot / ring box-shadow).
    /// - Parameters:
    ///   - color: glow color.
    ///   - radius: blur radius (comp uses ~7 for red dots, ~10 for the ring).
    ///   - opacity: glow strength (comp uses .6 for red, ~.3–.4 elsewhere).
    func spanGlow(_ color: Color, radius: CGFloat = 7, opacity: Double = 0.6) -> some View {
        modifier(GlowModifier(color: color, radius: radius, opacity: opacity))
    }
}
