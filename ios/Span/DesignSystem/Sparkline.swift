//
//  Sparkline.swift
//  Span — a tiny auto-scaled line sparkline of the lead marker's recent readings.
//
//  No axes. The comp renders these as a thin status-colored polyline (1.5px,
//  rounded caps) — see v2-today.jpeg. A bar variant is kept for cases that want it.
//  Respects Reduce Motion (no implicit animation here).
//

import SwiftUI

struct Sparkline: View {
    let points: [Double]
    /// Status color of the line.
    var tint: Color = SpanColor.statusGreen
    /// Stroke width.
    var lineWidth: CGFloat = 1.5
    /// When true, render as bars instead of a line.
    var barStyle: Bool = false

    var body: some View {
        GeometryReader { geo in
            if points.count < 2 {
                EmptyView()
            } else if barStyle {
                barView(in: geo.size)
            } else {
                lineView(in: geo.size)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalized() -> [Double] {
        guard let lo = points.min(), let hi = points.max(), hi > lo else {
            return points.map { _ in 0.5 }
        }
        return points.map { ($0 - lo) / (hi - lo) }
    }

    private func lineView(in size: CGSize) -> some View {
        let norm = normalized()
        // Match the comp's vertical inset: line uses 82% of height, centered.
        let topPad = size.height * 0.09
        let usable = size.height * 0.82
        return Path { path in
            for (idx, v) in norm.enumerated() {
                let x = size.width * CGFloat(idx) / CGFloat(norm.count - 1)
                let y = topPad + usable * (1 - CGFloat(v))
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func barView(in size: CGSize) -> some View {
        let norm = normalized()
        let count = norm.count
        let gap: CGFloat = 2
        let barWidth = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(norm.enumerated()), id: \.offset) { idx, v in
                let isRecent = idx >= count - 3
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isRecent ? tint.opacity(idx == count - 1 ? 1 : 0.5) : SpanColor.borderStrong)
                    .frame(width: barWidth, height: max(3, size.height * CGFloat(0.15 + v * 0.85)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

#Preview {
    HStack(spacing: 20) {
        Sparkline(points: [5.2, 5.5, 6.1, 6.5, 6.9], tint: SpanColor.statusRed)
            .frame(width: 60, height: 18)
        Sparkline(points: [68, 72, 76, 80, 82], tint: SpanColor.statusGreen)
            .frame(width: 60, height: 18)
        Sparkline(points: [5.2, 5.5, 6.1, 6.5, 6.9], tint: SpanColor.statusRed, barStyle: true)
            .frame(width: 60, height: 24)
    }
    .padding(40)
    .background(SpanColor.surface)
}
