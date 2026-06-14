//
//  SystemDetailView.swift
//  Span — Screen 9. System Detail.
//
//  Faithful to metabolic-detail.png: title + subtitle, an "Why this matters"
//  card (Four Horsemen + Hallmarks tags), then "Key Biomarkers" rows (name,
//  subtitle, sparkline placeholder, value + flag badge + trend), and the
//  "Ask Span about my [system]" inline button. Persistent footer.
//

import SwiftUI

struct SystemDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let key: SystemKey
    @Binding var path: [Route]
    @State private var model: SystemDetailModel?
    @State private var citation: Source?
    @State private var showVoice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    VStack(spacing: SpanSpacing.gutter) {
                        SkeletonBlock(height: 120)
                        SkeletonBlock(height: 90)
                        SkeletonBlock(height: 90)
                    }
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let detail):
                    content(detail)
                }
                DisclaimerFooter()
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
        .citationSheet($citation)
        .fullScreenCover(isPresented: $showVoice) { AskSpanView() }
        .task {
            if model == nil { model = SystemDetailModel(api: env.api, key: key) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    @ViewBuilder
    private func content(_ detail: SystemDetailDTO) -> some View {
        // Header
        HStack(spacing: SpanSpacing.gutter) {
            ZStack {
                Circle().fill(detail.status.color.opacity(0.12)).frame(width: 44, height: 44)
                Image(systemName: detail.key.symbolName)
                    .font(.system(size: 20))
                    .foregroundStyle(detail.status.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.displayName)
                    .font(SpanFont.displayLarge)
                    .foregroundStyle(SpanColor.textPrimary)
                if let subtitle = detail.subtitle {
                    Text(subtitle)
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)
                }
            }
            Spacer()
        }
        ZoneIndicator(status: detail.status, basis: detail.statusBasis)

        // Why this matters
        whyCard(detail)

        // Key biomarkers
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("Key Biomarkers")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            ForEach(detail.members) { member in
                Button {
                    if member.latestValue != nil {
                        path.append(.parameterDetail(parameterID: member.canonicalParamId))
                    }
                } label: {
                    SystemMemberRow(member: member)
                }
                .buttonStyle(.plain)
                .disabled(member.latestValue == nil)
            }
        }

        AskSpanInlineButton(title: "Ask Span about my \(detail.displayName) health") {
            showVoice = true
        }
    }

    private func whyCard(_ detail: SystemDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(SpanColor.primary)
                Text("Why this matters")
                    .font(SpanFont.headline)
                    .foregroundStyle(SpanColor.textPrimary)
            }
            Text(detail.whyItMatters)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
            FlowTags {
                if let horseman = detail.horseman {
                    PlainTagChip(text: "Peter Attia · Four Horsemen", systemImage: "books.vertical")
                    PlainTagChip(text: horseman, systemImage: "circle.fill")
                }
                ForEach(detail.hallmark, id: \.self) { hallmark in
                    PlainTagChip(text: hallmark)
                }
            }
            ForEach(detail.whyCitations) { source in
                CitationChip(source: source) { citation = $0 }
            }
        }
        .spanCard()
    }
}

/// One biomarker row (name + subtitle + sparkline + value + flag badge + trend).
struct SystemMemberRow: View {
    let member: SystemMember

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(SpanFont.headline)
                        .foregroundStyle(SpanColor.textPrimary)
                    if let subtitle = member.subtitle {
                        Text(subtitle)
                            .font(SpanFont.caption2)
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if member.latestValue != nil {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(member.displayValue)
                                .font(SpanFont.title2)
                                .foregroundStyle(SpanColor.textPrimary)
                            if let unit = member.unit {
                                Text(unit).font(SpanFont.caption2).foregroundStyle(SpanColor.textTertiary)
                            }
                        }
                        ZoneBadge(flag: member.flag)
                    } else {
                        Text(member.note ?? "not tested")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                }
            }
            if !member.sparklinePoints.isEmpty {
                HStack(spacing: SpanSpacing.xs) {
                    Sparkline(points: member.sparklinePoints, tint: member.zoneStatus.color)
                        .frame(height: 24)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: member.direction.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(member.direction.label)
                            .font(SpanFont.caption2)
                    }
                    .foregroundStyle(member.direction.color)
                }
            } else if let note = member.note, member.latestValue != nil {
                Text(note).font(SpanFont.caption2).foregroundStyle(SpanColor.textTertiary)
            }
        }
        .spanCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.displayName) \(member.displayValue) \(member.unit ?? ""), flagged \(member.flag.label), \(member.direction.label)")
    }
}

/// Lightweight wrapping flow layout for tag chips (iOS 17 Layout protocol).
struct FlowTags: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([]); x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let height = rows.reduce(0) { acc, row in
            acc + (row.map(\.height).max() ?? 0) + spacing
        } - spacing
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: max(height, 0))
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
    NavigationStack {
        SystemDetailView(key: .metabolic, path: .constant([]))
    }
    .environment(AppEnvironment.preview)
}
