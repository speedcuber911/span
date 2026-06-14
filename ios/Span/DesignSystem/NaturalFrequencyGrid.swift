//
//  NaturalFrequencyGrid.swift
//  Span — the 10×10 "X in 100" natural-frequency dot grid (see v2-param.jpeg).
//
//  `count` filled, glowing, status-colored dots out of `denom`; the rest are muted
//  empty dots. Conveys "about 23 in 100 people …" as a natural frequency — never a
//  bare percentage (Gigerenzer; medical stance). The comp uses red glowing circles
//  for the filled portion and rgba(255,255,255,.06) for the empties.
//

import SwiftUI

struct NaturalFrequencyGrid: View {
    let count: Int
    var denom: Int = 100
    var tint: Color = SpanColor.statusRed
    /// Dot diameter; the grid lays out 10 per row.
    var dot: CGFloat = 18
    var spacing: CGFloat = 3

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 10)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<denom, id: \.self) { idx in
                let filled = idx < count
                Circle()
                    .fill(filled ? tint : SpanColor.textPrimary.opacity(0.06))
                    .frame(height: dot)
                    .spanGlow(tint, radius: 4, opacity: filled ? 0.35 : 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("About \(count) out of \(denom) people highlighted")
    }
}

#Preview {
    VStack(spacing: 16) {
        NaturalFrequencyGrid(count: 23)
        Text("About 23 in 100 people your age and sex have HbA1c this high.")
            .font(SpanFont.callout)
            .foregroundStyle(SpanColor.textSecondary)
    }
    .padding(24)
    .background(SpanColor.surfaceCard)
}
