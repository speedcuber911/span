//
//  Color+Span.swift
//  Span — "Health Intelligence" dark design system.
//
//  Every token from the authoritative comp (design/span_screens_v2.html :root),
//  implemented as a code-only Color extension (no asset catalog required). The dark
//  palette is a premium lavender-on-near-black system with a purple accent.
//
//  Two color systems remain distinct (medical stance, never conflated):
//   • FLAG colors  — per individual measurement (High=red, Low=blue/purple, Normal=green)
//   • ZONE colors  — the three-zone traffic light for organ systems & bands
//
//  Public symbol names are kept stable so every screen that already imports the
//  design system keeps resolving; the hex values are remapped to the dark tokens.
//

import SwiftUI

extension Color {
    /// Build a Color from a hex string ("#RRGGBB" or "#RRGGBBAA"); falls back to clear.
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

/// All Span design tokens, namespaced under `SpanColor` (and `Color.span`).
enum SpanColor {

    // MARK: - Surfaces & background  (--bg / --s1 / --s2 / --s3)

    /// App background — near-black (#030306).
    static let background = Color(spanHex: "#030306")
    /// Phone / primary surface chrome (#09090F). Nav bars, tab bar.
    static let surface = Color(spanHex: "#09090F")
    /// Cards / tiles (#0F0F1A).  Alias: `surfaceCard`.
    static let surfaceCard = Color(spanHex: "#0F0F1A")
    /// Raised surface inside cards / sheets (#151522). Alias: `surfaceRaised`.
    static let surfaceRaised = Color(spanHex: "#151522")

    /// Back-compat aliases used by older screen code.
    static let surfaceLow = surfaceCard       // grouped fills / footer
    static let surfaceHigh = surfaceRaised     // skeletons / chips
    static let surfaceHighest = Color(spanHex: "#242438") // placeholder bars (--b2)

    // MARK: - Borders / hairlines  (--b1 / --b2)

    /// Hairline border, the quiet one (#1A1A28). 0.5px in the comp.
    static let border = Color(spanHex: "#1A1A28")
    /// Hairline border, slightly brighter (#242438).
    static let borderStrong = Color(spanHex: "#242438")
    /// Back-compat: screens referenced `outlineVariant` for hairlines.
    static let outlineVariant = border
    /// Back-compat: chart gray reference band.
    static let clinicalBand = border

    // MARK: - Text  (--t1 / --t2 / --t3)

    /// Primary text — light lavender-white (#ECEAFF).
    static let textPrimary = Color(spanHex: "#ECEAFF")
    /// Secondary text (#6A6880).
    static let textSecondary = Color(spanHex: "#6A6880")
    /// Tertiary / uppercase labels (#3A3852).
    static let textTertiary = Color(spanHex: "#3A3852")
    /// Back-compat alias.
    static let onSurface = textPrimary

    // MARK: - Accent (purple)  (--p)

    /// Purple accent — "Ask Span", active tab, links, primary chips (#BF5AF2).
    static let accent = Color(spanHex: "#BF5AF2")
    /// rgba(191,90,242,.1) accent fill.
    static let accentBg = Color(spanHex: "#BF5AF2").opacity(0.10)
    /// rgba(191,90,242,.3) accent border.
    static let accentBorder = Color(spanHex: "#BF5AF2").opacity(0.30)

    /// Back-compat: screens used `primary` for links / "Ask Span". Remapped to accent.
    static let primary = accent
    static let primaryBright = accent
    /// On a filled primary (white pill = light button) the label is near-black.
    static let onPrimary = background

    // MARK: - Status — three-zone traffic light  (--r / --a / --g)

    /// Red — outside clinical reference range (attention / high).  (#FF2D55)
    static let statusRed = Color(spanHex: "#FF2D55")
    /// Amber — within range but sub-optimal (monitor).  (#FF9500)
    static let statusYellow = Color(spanHex: "#FF9500")
    /// Alias used in some call-sites.
    static let statusAmber = statusYellow
    /// Green — within evidence-based optimal band (optimal / on track).  (#30D158)
    static let statusGreen = Color(spanHex: "#30D158")
    /// Blue/low flag — the comp uses the purple accent for a "low" marker chip.
    static let statusBlue = accent
    /// Purple status (info) — same as accent.
    static let statusPurple = accent

    // MARK: - Status fills & borders (the .bdg / band variants)

    /// rgba(255,45,85,.1)
    static let statusRedBg = statusRed.opacity(0.10)
    /// rgba(255,45,85,.28)
    static let statusRedBorder = statusRed.opacity(0.28)
    /// rgba(255,149,0,.1)
    static let statusYellowBg = statusYellow.opacity(0.10)
    /// rgba(255,149,0,.28)
    static let statusYellowBorder = statusYellow.opacity(0.28)
    /// rgba(48,209,88,.08)
    static let statusGreenBg = statusGreen.opacity(0.08)
    /// rgba(48,209,88,.28)
    static let statusGreenBorder = statusGreen.opacity(0.28)

    // MARK: - Chart bands

    /// Light-green chart band fill for the optimal range (rgba(48,209,88,.04)).
    static let optimalFill = statusGreen.opacity(0.04)
    /// Optimal band stroke.
    static let optimalBorder = statusGreen.opacity(0.25)

    // MARK: - Attention rail (back-compat container names)

    /// Fill behind the "Discuss with your clinician" rail.
    static let errorContainer = statusRedBg
    /// High-contrast text on the error container.
    static let onErrorContainer = statusRed
}

extension SpanColor {
    /// Fill behind a status chip / band for a given zone.
    static func bg(for status: ZoneStatus) -> Color {
        switch status {
        case .attention:     return statusRedBg
        case .monitor:       return statusYellowBg
        case .onTrack:       return statusGreenBg
        case .notEnoughData: return surfaceCard
        }
    }

    /// Hairline border for a status chip / band for a given zone.
    static func border(for status: ZoneStatus) -> Color {
        switch status {
        case .attention:     return statusRedBorder
        case .monitor:       return statusYellowBorder
        case .onTrack:       return statusGreenBorder
        case .notEnoughData: return border
        }
    }

    /// Fill behind a per-measurement flag chip.
    static func bg(for flag: MeasurementFlag) -> Color {
        switch flag {
        case .high:   return statusRedBg
        case .low:    return accentBg
        case .normal: return statusGreenBg
        case .none:   return surfaceCard
        }
    }

    /// Hairline border for a per-measurement flag chip.
    static func border(for flag: MeasurementFlag) -> Color {
        switch flag {
        case .high:   return statusRedBorder
        case .low:    return accentBorder
        case .normal: return statusGreenBorder
        case .none:   return border
        }
    }
}

extension Color {
    /// Convenience accessor so call-sites read `Color.span.statusRed`.
    static let span = SpanColor.self
}
