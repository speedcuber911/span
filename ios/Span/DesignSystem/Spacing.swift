//
//  Spacing.swift
//  Span — spacing & shape tokens for the dark "Health Intelligence" theme.
//
//  Base unit 4. Horizontal content margin 20 (matches the comp's .sc padding).
//  Cards radius 12–16, chips/pills full. Cards are flat fills with a 0.5px hairline
//  border — never drop shadows (the comp uses borders, not shadows).
//

import SwiftUI

enum SpanSpacing {
    /// 4 — base rhythm unit.
    static let base: CGFloat = 4
    /// 6
    static let xxs: CGFloat = 6
    /// 8
    static let xs: CGFloat = 8
    /// 12 — inter-card gutter.
    static let gutter: CGFloat = 12
    /// 16 — card padding.
    static let md: CGFloat = 16
    /// 20 — horizontal screen margin (the comp's .sc / .nb padding).
    static let screenH: CGFloat = 20
    /// 24
    static let lg: CGFloat = 24
    /// 32
    static let xl: CGFloat = 32

    /// Minimum HIG touch target.
    static let touchTarget: CGFloat = 44
    /// Hairline width used throughout (the comp's 0.5px scaled up to a crisp 1px on @2x/@3x).
    static let hairline: CGFloat = 0.75
}

enum SpanRadius {
    /// Cards / tiles.
    static let card: CGFloat = 14
    /// Larger cards / sheets.
    static let cardLarge: CGFloat = 16
    /// Small chips / inputs / segmented control.
    static let small: CGFloat = 10
    /// Status badge pill radius.
    static let badge: CGFloat = 9
    /// Pill.
    static let pill: CGFloat = 999
}

extension View {
    /// A card on the dark surface: flat `surfaceCard` fill + 0.5px hairline border,
    /// never a drop shadow.
    func spanCard(padding: CGFloat = SpanSpacing.md,
                  radius: CGFloat = SpanRadius.card,
                  fill: Color = SpanColor.surfaceCard,
                  border: Color = SpanColor.border) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: SpanSpacing.hairline)
            )
    }

    /// Standard horizontal screen margin.
    func spanHorizontalMargin() -> some View {
        self.padding(.horizontal, SpanSpacing.screenH)
    }

    /// A bottom hairline divider (the comp's `border-bottom:.5px solid var(--b1)`).
    func spanBottomHairline(_ color: Color = SpanColor.border) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(color)
                .frame(height: SpanSpacing.hairline)
        }
    }
}
