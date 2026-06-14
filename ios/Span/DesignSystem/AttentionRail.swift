//
//  AttentionRail.swift
//  Span — the "Discuss with your clinician" rail (see v2-today.jpeg).
//
//  A red-tinted card with a 2.5px red left accent bar, a glowing red dot, the
//  "Discuss with your clinician" header in red, and a wrap of inline marker chips
//  (each = trend arrow + parameter + value, colored by flag). Omitted entirely when
//  there are no out-of-range markers — absence of red is NOT an occasion for praise.
//

import SwiftUI

struct AttentionRail: View {
    let items: [AttentionItem]
    var onTapItem: (AttentionItem) -> Void = { _ in }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: SpanSpacing.xs) {
                TrafficLightDot(status: .attention, diameter: 8)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Discuss with your clinician")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SpanColor.statusRed)

                    FlowLayout(spacing: 5) {
                        ForEach(items) { item in
                            Button { onTapItem(item) } label: {
                                AttentionChip(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SpanColor.statusRedBg, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SpanColor.statusRed)
                    .frame(width: 2.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
                    .strokeBorder(SpanColor.statusRedBorder, lineWidth: SpanSpacing.hairline)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(items.count) markers to discuss with your clinician")
        }
    }
}

private struct AttentionChip: View {
    let item: AttentionItem

    private var style: StatusBadgeStyle { StatusBadgeStyle(flag: item.flag) }
    private var arrow: String { item.flag == .low ? "arrow.down" : "arrow.up" }

    private var label: String {
        var s = item.parameter
        if let v = item.latestValue {
            s += " \(v.formatted(.number.precision(.fractionLength(0...1))))"
        }
        return s
    }

    var body: some View {
        StatusBadge(text: label, style: style, systemImage: arrow)
            .accessibilityLabel("\(item.parameter), flagged \(item.flag.label)")
    }
}

// MARK: - Minimal wrap layout (chips flow to the next line)

/// A lightweight flow layout so attention chips wrap (iOS 16+ Layout).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += rowHeight + spacing
                rows.append([])
                x = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    AttentionRail(items: MockSpanAPI.sampleOverview.attention)
        .padding()
        .background(SpanColor.background)
}
