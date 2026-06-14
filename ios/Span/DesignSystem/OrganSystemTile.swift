//
//  OrganSystemTile.swift
//  Span — the signature organ-system tile.
//
//  White rounded card · SF Symbol with zone tint · system name · status dot ·
//  trend arrow · count-basis subtitle (NEVER a percentage, NEVER a composite
//  score) · mini sparkline. Two-column grid on Today, taller row on Systems.
//

import SwiftUI

/// Grid tile used on the Today screen (2-column fluid grid).
struct OrganSystemTile: View {
    let rollup: SystemRollup

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            HStack {
                HStack(spacing: SpanSpacing.xs) {
                    Image(systemName: rollup.key.symbolName)
                        .font(.system(size: 18))
                        .foregroundStyle(rollup.status.color)
                        .frame(width: 24)
                    Text(rollup.key.displayName)
                        .font(SpanFont.body.weight(.medium))
                        .foregroundStyle(SpanColor.textPrimary)
                }
                Spacer()
                Image(systemName: rollup.leadDirection.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(rollup.leadDirection.color)
            }

            // Lead marker + count basis (count, never percent).
            VStack(alignment: .leading, spacing: 2) {
                Text(rollup.leadParameter)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
                Text(rollup.statusBasis)
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
                    .lineLimit(2)
            }

            Sparkline(points: rollup.sparklinePoints, tint: rollup.status.color)
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
        .overlay(alignment: .top) {
            // Colored zone indicator on the top edge.
            RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                .trim(from: 0.0, to: 0.0001) // keep shape, draw only a top accent below
                .hidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rollup.key.displayName), \(rollup.status.label). Lead marker \(rollup.leadParameter), \(rollup.leadDirection.label). \(rollup.statusBasis).")
    }
}

/// Taller row used on the dedicated Systems tab.
struct OrganSystemRow: View {
    let rollup: SystemRollup

    var body: some View {
        HStack(spacing: SpanSpacing.md) {
            ZStack {
                Circle()
                    .fill(rollup.status.color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: rollup.key.symbolName)
                    .font(.system(size: 18))
                    .foregroundStyle(rollup.status.color)
            }
            .overlay(alignment: .topTrailing) {
                TrafficLightDot(status: rollup.status, diameter: 9)
                    .overlay(Circle().stroke(SpanColor.surface, lineWidth: 1.5))
                    .offset(x: 2, y: -2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rollup.key.displayName)
                    .font(SpanFont.headline)
                    .foregroundStyle(SpanColor.textPrimary)
                HStack(spacing: 6) {
                    Text(rollup.leadParameter)
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)
                    Image(systemName: rollup.leadDirection.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rollup.leadDirection.color)
                }
                Text(rollup.statusBasis)
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
            }

            Spacer()

            Sparkline(points: rollup.sparklinePoints, tint: rollup.status.color)
                .frame(width: 48, height: 28)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpanColor.textTertiary)
        }
        .spanCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rollup.key.displayName), \(rollup.status.label). \(rollup.leadParameter) \(rollup.leadDirection.label). \(rollup.statusBasis).")
    }
}

#Preview("Tile") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        OrganSystemTile(rollup: MockSpanAPI.sampleOverview.systems[0])
        OrganSystemTile(rollup: MockSpanAPI.sampleOverview.systems[2])
    }
    .padding()
    .background(SpanColor.background)
}

#Preview("Row") {
    VStack(spacing: 12) {
        OrganSystemRow(rollup: MockSpanAPI.sampleOverview.systems[0])
        OrganSystemRow(rollup: MockSpanAPI.sampleOverview.systems[2])
    }
    .padding()
    .background(SpanColor.background)
}
