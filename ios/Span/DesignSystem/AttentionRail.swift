//
//  AttentionRail.swift
//  Span — the calm "markers to discuss" rail.
//
//  Full-width light-red component with a leading alert icon and a header count.
//  Each chip = parameter name + flag dot (Red=High / Blue=Low). Scrolls
//  horizontally when chips overflow. Omitted entirely when there are no
//  out-of-range markers — absence of red is NOT an occasion for praise.
//

import SwiftUI

struct AttentionRail: View {
    let items: [AttentionItem]
    var onTapItem: (AttentionItem) -> Void = { _ in }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
                HStack(spacing: SpanSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SpanColor.statusRed)
                    Text("\(items.count) markers to discuss")
                        .font(SpanFont.headline)
                        .foregroundStyle(SpanColor.onErrorContainer)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpanSpacing.xs) {
                        ForEach(items) { item in
                            Button { onTapItem(item) } label: {
                                AttentionChip(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(SpanSpacing.md)
            .background(SpanColor.errorContainer, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .stroke(SpanColor.statusRed.opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(items.count) markers to discuss with your clinician")
        }
    }
}

private struct AttentionChip: View {
    let item: AttentionItem

    var body: some View {
        HStack(spacing: 6) {
            FlagDot(flag: item.flag, diameter: 8)
            Text(item.parameter)
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textPrimary)
            Image(systemName: item.flag == .low ? "arrow.down" : "arrow.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item.flag.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SpanColor.surface, in: Capsule())
        .overlay(Capsule().stroke(SpanColor.clinicalBand, lineWidth: 1))
        .accessibilityLabel("\(item.parameter), flagged \(item.flag.label)")
    }
}

#Preview {
    AttentionRail(items: MockSpanAPI.sampleOverview.attention)
        .padding()
        .background(SpanColor.background)
}
