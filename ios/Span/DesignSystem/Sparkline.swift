//
//  Sparkline.swift
//  Span — a tiny auto-scaled bar/line sparkline of the lead marker's recent
//  readings. No axes. Respects Reduce Motion (no implicit animation here).
//
//  The Today comps render the sparkline as a small row of bars whose final bars
//  pick up the zone color; we mirror that.
//

import SwiftUI

struct Sparkline: View {
    let points: [Double]
    /// Zone color applied to the most recent bars.
    var tint: Color = SpanColor.statusGreen
    var barStyle: Bool = true

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

    private func barView(in size: CGSize) -> some View {
        let norm = normalized()
        let count = norm.count
        let gap: CGFloat = 2
        let barWidth = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(norm.enumerated()), id: \.offset) { idx, v in
                let isRecent = idx >= count - 3
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isRecent ? tint.opacity(idx == count - 1 ? 1 : 0.5) : SpanColor.surfaceHighest)
                    .frame(width: barWidth, height: max(3, size.height * CGFloat(0.15 + v * 0.85)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func lineView(in size: CGSize) -> some View {
        let norm = normalized()
        return Path { path in
            for (idx, v) in norm.enumerated() {
                let x = size.width * CGFloat(idx) / CGFloat(norm.count - 1)
                let y = size.height * (1 - CGFloat(v))
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

#Preview {
    HStack(spacing: 20) {
        Sparkline(points: [5.6, 5.8, 6.0, 6.2, 6.4, 6.7, 6.9], tint: SpanColor.statusRed)
            .frame(width: 60, height: 32)
        Sparkline(points: [78, 80, 82, 83, 84, 85, 86], tint: SpanColor.statusGreen, barStyle: false)
            .frame(width: 60, height: 32)
    }
    .padding()
    .background(SpanColor.surface)
}
