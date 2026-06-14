//
//  Color+Span.swift
//  Span — "Clinical Precision" design system
//
//  Every token from DESIGN_SYSTEM.md, implemented as a code-only Color extension
//  (no asset catalog required). Hex values come straight from the exported Stitch
//  HTML so the SwiftUI app matches the comps byte-for-byte.
//
//  Two distinct color systems live here and MUST NOT be conflated (per SCREENS.md):
//   • FLAG colors  — per individual measurement (High=red, Low=blue, Normal=green)
//   • ZONE colors  — the three-zone traffic light for organ-system tiles & bands
//

import SwiftUI

extension Color {
    /// Build a Color from a hex string ("#RRGGBB" or "RRGGBBAA"); falls back to clear.
    init(spanHex hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r, g, b, a: Double
        switch raw.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            r = 0; g = 0; b = 0; a = 0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// All Span design tokens, namespaced under `Color.span`.
enum SpanColor {

    // MARK: Surfaces & background
    /// Screen background — very light gray.
    static let background = Color(spanHex: "#F9F9FE")
    /// Cards / tiles — pure white.
    static let surface = Color(spanHex: "#FFFFFF")
    /// One step up from background, used for footer / grouped fills.
    static let surfaceLow = Color(spanHex: "#F3F3F8")
    /// Skeletons, sparkline placeholder bars, chips.
    static let surfaceHigh = Color(spanHex: "#E8E8ED")
    static let surfaceHighest = Color(spanHex: "#E2E2E7")

    // MARK: Text
    static let textPrimary = Color(spanHex: "#000000")
    static let onSurface = Color(spanHex: "#1A1C1F")
    static let textSecondary = Color(spanHex: "#636366")
    static let textTertiary = Color(spanHex: "#8E8E93")

    // MARK: Lines & brand
    /// 1px hairline card borders (borders over shadows).
    static let outlineVariant = Color(spanHex: "#C1C6D6")
    /// Primary buttons, links, "Ask Span".
    static let primary = Color(spanHex: "#005BBF")
    /// Brighter primary used on the floating FAB / accent dots.
    static let primaryBright = Color(spanHex: "#1A73E8")
    static let onPrimary = Color(spanHex: "#FFFFFF")

    // MARK: Status — three-zone traffic light
    /// Red — outside clinical reference range (attention).
    static let statusRed = Color(spanHex: "#D93025")
    /// Yellow — within clinical range but sub-optimal (monitor).
    static let statusYellow = Color(spanHex: "#FBBC04")
    /// Green — within evidence-based optimal band (on track).
    static let statusGreen = Color(spanHex: "#34A853")
    /// Blue — low value flag (cool contrast to red).
    static let statusBlue = Color(spanHex: "#1A73E8")

    // MARK: Chart bands
    /// Light-green chart band fill for the optimal range.
    static let optimalFill = Color(spanHex: "#E6F4EA")
    /// Optimal band stroke (rgba(52,168,83,0.4)).
    static let optimalBorder = Color(spanHex: "#34A853").opacity(0.4)
    /// Gray chart band for the clinical reference range (rgba(60,60,67,0.12)).
    static let clinicalBand = Color(spanHex: "#3C3C43").opacity(0.12)

    // MARK: Attention rail
    /// Light-red fill behind the "markers to discuss" rail.
    static let errorContainer = Color(spanHex: "#FFDAD6")
    /// High-contrast text on the error container.
    static let onErrorContainer = Color(spanHex: "#93000A")
}

extension Color {
    /// Convenience accessor so call-sites read `Color.span.statusRed`.
    static let span = SpanColor.self
}
