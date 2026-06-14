//
//  OrganSystemTile.swift
//  Span — the organ-system row (see v2-today.jpeg).
//
//  The dark "Health Intelligence" Today screen lists each system as a single ROW:
//  a glowing status dot · the uppercase system label · an inline status-colored
//  sparkline · the big mono lead value with a small unit suffix. NEVER a percentage,
//  NEVER a composite score. A richer variant (`SystemDetailRow`) is used on the
//  Systems tab with a status-basis subtitle and a chevron.
//
//  `SystemRow` is the canonical name; `OrganSystemTile` / `OrganSystemRow` are kept
//  as aliases so older call-sites keep resolving.
//

import SwiftUI

/// Compact Today-screen row: dot · LABEL · sparkline · value+unit.
struct SystemRow: View {
    let rollup: SystemRollup
    /// The big value to show (lead marker's latest). The DTO doesn't carry it
    /// numerically, so the screen passes the formatted value + unit it already has.
    var value: String? = nil
    var unit: String? = nil

    var body: some View {
        HStack(spacing: SpanSpacing.gutter) {
            TrafficLightDot(status: rollup.status, diameter: 8)

            Text(rollup.key.displayName)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(SpanColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Sparkline(points: rollup.sparklinePoints, tint: rollup.status.color)
                .frame(width: 52, height: 16)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(SpanFont.mono(16, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(rollup.status.color)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rollup.key.displayName), \(rollup.status.label). Lead marker \(rollup.leadParameter). \(rollup.statusBasis).")
    }
}

/// Back-compat alias — the old grid "tile" is now the Today row.
typealias OrganSystemTile = SystemRow

/// Taller row used on the dedicated Systems tab: dot · name + lead + basis ·
/// sparkline · chevron.
struct SystemDetailRow: View {
    let rollup: SystemRollup

    var body: some View {
        HStack(spacing: SpanSpacing.gutter) {
            TrafficLightDot(status: rollup.status, diameter: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(rollup.key.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(SpanColor.textPrimary)
                Text("\(rollup.leadParameter) · \(rollup.statusBasis)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(SpanColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Sparkline(points: rollup.sparklinePoints, tint: rollup.status.color)
                .frame(width: 64, height: 18)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpanColor.textTertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rollup.key.displayName), \(rollup.status.label). \(rollup.leadParameter). \(rollup.statusBasis).")
    }
}

/// Back-compat alias.
typealias OrganSystemRow = SystemDetailRow

#Preview("Today rows") {
    VStack(spacing: 0) {
        SystemRow(rollup: MockSpanAPI.sampleOverview.systems[0], value: "6.9", unit: "% HbA1c")
            .spanBottomHairline()
        SystemRow(rollup: MockSpanAPI.sampleOverview.systems[2], value: "82", unit: "eGFR")
            .spanBottomHairline()
    }
    .padding(.horizontal, 20)
    .background(SpanColor.background)
}

#Preview("Systems rows") {
    VStack(spacing: 0) {
        SystemDetailRow(rollup: MockSpanAPI.sampleOverview.systems[0]).spanBottomHairline()
        SystemDetailRow(rollup: MockSpanAPI.sampleOverview.systems[2]).spanBottomHairline()
    }
    .padding(.horizontal, 20)
    .background(SpanColor.background)
}
