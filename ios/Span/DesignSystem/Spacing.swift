//
//  Spacing.swift
//  Span — spacing & shape tokens from DESIGN_SYSTEM.md.
//
//  Base unit 4px (8pt rhythm). Horizontal content margin 16. Card gaps 12–16.
//  Touch targets ≥44pt (HIG). Card radius ~12, chips are pills.
//

import SwiftUI

enum SpanSpacing {
    /// 4 — base rhythm unit.
    static let base: CGFloat = 4
    /// 8
    static let xs: CGFloat = 8
    /// 12 — inter-card gutter.
    static let gutter: CGFloat = 12
    /// 16 — horizontal content margin / card padding.
    static let md: CGFloat = 16
    /// 24
    static let lg: CGFloat = 24
    /// 32
    static let xl: CGFloat = 32

    /// Minimum HIG touch target.
    static let touchTarget: CGFloat = 44
}

enum SpanRadius {
    /// Cards / tiles — continuous corners.
    static let card: CGFloat = 12
    /// Slightly tighter (chips with square-ish content).
    static let small: CGFloat = 8
    /// Pill.
    static let pill: CGFloat = 999
}

extension View {
    /// White card on the light-gray surface: tonal layering + 1px hairline border,
    /// never a drop shadow (DESIGN_SYSTEM.md).
    func spanCard(padding: CGFloat = SpanSpacing.md) -> some View {
        self
            .padding(padding)
            .background(SpanColor.surface, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .stroke(SpanColor.clinicalBand, lineWidth: 1)
            )
    }

    /// Standard horizontal screen margin.
    func spanHorizontalMargin() -> some View {
        self.padding(.horizontal, SpanSpacing.md)
    }
}
