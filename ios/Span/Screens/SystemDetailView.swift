//
//  SystemDetailView.swift
//  Span — Screen 9. System Detail.
//
//  Dark "Health Intelligence" revamp, faithful to the comp's screen 9:
//   • a sticky ".nb" header: back chevron ("Systems") + right-aligned system name.
//   • a status-tinted gradient header band: glowing dot + zone word + count basis,
//     the "why this matters" prose, the ontology tags, and citation chips.
//   • compact biomarker rows (glowing dot · name · inline sparkline · big mono
//     value + unit · status badge).
//   • the inline "Ask Span about my [system]" button + persistent footer.
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
        VStack(spacing: 0) {
            SpanNavBar(title: navTitle, backTitle: "Systems",
                       onBack: { if !path.isEmpty { path.removeLast() } },
                       titleAlignment: .trailing)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch model?.state ?? .idle {
                    case .idle, .loading:
                        VStack(spacing: SpanSpacing.gutter) {
                            SkeletonBlock(height: 120)
                            SkeletonBlock(height: 52)
                            SkeletonBlock(height: 52)
                            SkeletonBlock(height: 52)
                        }
                        .padding(.horizontal, SpanSpacing.screenH)
                        .padding(.top, SpanSpacing.md)
                    case .failed(let message):
                        LoadFailureView(message: message) { Task { await model?.load() } }
                    case .loaded(let detail):
                        content(detail)
                    }

                    DisclaimerFooter()
                        .padding(.top, SpanSpacing.lg)
                }
            }
        }
        .background(SpanColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .citationSheet($citation)
        .fullScreenCover(isPresented: $showVoice) { AskSpanView() }
        .task {
            if model == nil { model = SystemDetailModel(api: env.api, key: key) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    private var navTitle: String {
        model?.state.value?.displayName ?? key.displayName
    }

    @ViewBuilder
    private func content(_ detail: SystemDetailDTO) -> some View {
        whyBand(detail)

        // Biomarker rows
        VStack(alignment: .leading, spacing: 0) {
            ForEach(detail.members) { member in
                Button {
                    if member.latestValue != nil {
                        path.append(.parameterDetail(parameterID: member.canonicalParamId))
                    }
                } label: {
                    SystemMemberRow(member: member)
                        .spanBottomHairline()
                }
                .buttonStyle(.plain)
                .disabled(member.latestValue == nil)
            }
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.top, 4)

        AskSpanInlineButton(title: "Ask Span about my \(detail.displayName) health") {
            showVoice = true
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.top, SpanSpacing.md)
    }

    // MARK: Status-tinted "why this matters" header band

    private func whyBand(_ detail: SystemDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: SpanSpacing.xs) {
                TrafficLightDot(status: detail.status, diameter: 8)
                Text(zoneHeadline(detail))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(detail.status.color)
            }

            if let subtitle = detail.subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(SpanColor.textTertiary)
            }

            Text(detail.whyItMatters)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(SpanColor.textSecondary)

            if detail.horseman != nil || !detail.hallmark.isEmpty {
                FlowLayout(spacing: 6) {
                    if let horseman = detail.horseman {
                        PlainTagChip(text: "Four Horsemen · \(horseman)", systemImage: "books.vertical")
                    }
                    ForEach(detail.hallmark, id: \.self) { hallmark in
                        PlainTagChip(text: hallmark, systemImage: nil)
                    }
                }
            }

            if !detail.whyCitations.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(detail.whyCitations) { source in
                        CitationChip(source: source) { citation = $0 }
                    }
                }
            }
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.vertical, SpanSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [detail.status.color.opacity(0.08), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(detail.status.color.opacity(0.2))
                .frame(height: SpanSpacing.hairline)
        }
    }

    /// "Attention — 1 red · 2 yellow of 8 measured" style headline.
    private func zoneHeadline(_ detail: SystemDetailDTO) -> String {
        "\(detail.status.label) — \(detail.statusBasis)"
    }
}

// MARK: - Compact biomarker row (dot · name · sparkline · value+unit · badge)

struct SystemMemberRow: View {
    let member: SystemMember

    private var valueColor: Color {
        member.latestValue == nil ? SpanColor.textTertiary : member.zoneStatus.color
    }

    private var badge: (text: String, style: StatusBadgeStyle)? {
        guard member.latestValue != nil else { return nil }
        switch member.flag {
        case .high:   return ("High ↑", .high)
        case .low:    return ("Low ↓", .info)
        case .normal:
            // Within range; distinguish optimal vs monitor via the zone.
            return member.zoneStatus == .onTrack ? ("Optimal", .optimal) : ("Monitor", .monitor)
        case .none:   return nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            TrafficLightDot(status: member.zoneStatus, diameter: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SpanColor.textPrimary)
                if member.latestValue == nil, let note = member.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(SpanColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if member.sparklinePoints.count >= 2 {
                Sparkline(points: member.sparklinePoints, tint: member.zoneStatus.color)
                    .frame(width: 48, height: 16)
            }

            if member.latestValue != nil {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(member.displayValue)
                        .font(SpanFont.mono(14, weight: .bold))
                        .foregroundStyle(valueColor)
                    if let unit = member.unit {
                        Text(" \(unit)")
                            .font(.system(size: 9))
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                }
            }

            if let badge {
                StatusBadge(text: badge.text, style: badge.style)
            } else if member.latestValue == nil {
                StatusBadge(text: "Not tested", style: .neutral)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if member.latestValue == nil {
            return "\(member.displayName), not tested. \(member.note ?? "")"
        }
        let badgeWord = badge?.text ?? member.flag.label
        return "\(member.displayName), \(member.displayValue) \(member.unit ?? ""), \(badgeWord), \(member.direction.label)."
    }
}

#Preview {
    NavigationStack {
        SystemDetailView(key: .metabolic, path: .constant([.systemDetail(.metabolic)]))
    }
    .environment(AppEnvironment.preview)
}
