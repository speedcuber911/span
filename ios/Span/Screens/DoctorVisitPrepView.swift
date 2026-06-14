//
//  DoctorVisitPrepView.swift
//  Span — Screen 14. Doctor-Visit Prep Sheet.
//
//  Dark "Health Intelligence" revamp, faithful to span_screens_v2.html screen 14.
//  Three phases (PrepModel): entry → generating (progress) → ready.
//
//  The ready sheet is a dark, structured prep document:
//   • "Raise first" — a red-bordered most-urgent card with an inline citation chip.
//   • "Key markers" — a glance table (Marker / Value / Ref / Status badge), with
//     "Not tested" rows shown as neutral badges (ApoB, Lp(a)).
//   • "Questions to ask" — amber per-system group headers + `.qcb` checkbox rows.
//   • "Supplements to discuss" — Why / Caution / Verdict (NO doses) + citation chips.
//   • "Gaps your clinician likely missed" — bulleted.
//   • The fixed, code-appended educational footer (never AI-generated).
//
//  Consumes the same PrepModel / PrepReport DTOs unchanged.
//

import SwiftUI

struct DoctorVisitPrepView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: PrepModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                switch model?.phase ?? .entry {
                case .entry:
                    entryState
                case .generating(let progress):
                    generatingState(progress)
                case .ready(let report):
                    readyState(report)
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.generate() } }
                }
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
            .padding(.bottom, SpanSpacing.lg)
        }
        .background(SpanColor.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Doctor-visit prep")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            if case .ready = model?.phase {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "square.and.arrow.up") }
                        .tint(SpanColor.accent)
                }
            }
        }
        .citationSheet($citation)
        .task { if model == nil { model = PrepModel(api: env.api) } }
    }

    // MARK: Entry

    private var entryState: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Your next appointment is a chance to discuss what your data shows.")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Generate prep sheet") { Task { await model?.generate() } }
                .spanPrimaryButton()
            Text("Takes about 30–60 seconds. Based on your most recent lab results.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
            Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
            Text("Last generated: 14 Mar 2026")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textTertiary)
        }
        .spanCard()
    }

    // MARK: Generating

    private func generatingState(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Generating your prep sheet…")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            CheckinProgressBarP(fraction: progress)
            Text("\(Int(progress * 100))%")
                .font(SpanFont.mono(12))
                .foregroundStyle(SpanColor.textSecondary)
            VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                Label("Reviewing your lab trends.", systemImage: "chart.line.uptrend.xyaxis")
                Label("Identifying questions to ask.", systemImage: "questionmark.circle")
                Label("Adding citations.", systemImage: "text.book.closed")
            }
            .font(SpanFont.footnote)
            .foregroundStyle(SpanColor.textSecondary)
            .tint(SpanColor.accent)
        }
        .spanCard()
    }

    // MARK: Ready

    @ViewBuilder
    private func readyState(_ report: PrepReport) -> some View {
        // Header
        VStack(alignment: .leading, spacing: 2) {
            Text("Doctor-Visit Prep")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            Text("Generated \(report.generatedAt.formatted(.dateTime.day().month().year()))")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
        }

        raiseFirstSection(report.raiseFirst)
        glanceSection(report.glanceTable)
        questionsSection(report.questions)
        supplementsSection(report.lifestyleSupplements)
        gapsSection(report.gapsClinicianMissed)
        prepDisclaimer
    }

    // Raise first — red urgent card.
    private func raiseFirstSection(_ raise: RaiseFirst) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            SpanSectionLabel("Raise first")
            VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                Text("Most urgent")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SpanColor.statusRed)
                    .textCase(.uppercase)
                    .kerning(0.9)
                Text(raise.body)
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.statusRed.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                FlowChips(raise.citations) { citation = $0 }
            }
            .padding(SpanSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpanColor.statusRedBg, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(SpanColor.statusRed).frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .strokeBorder(SpanColor.statusRedBorder, lineWidth: SpanSpacing.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
        }
    }

    // Key markers glance table.
    private func glanceSection(_ rows: [GlanceRow]) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            SpanSectionLabel("Key markers")
            VStack(spacing: 0) {
                // Header row.
                HStack(spacing: 0) {
                    tableHeader("Marker", alignment: .leading)
                    tableHeader("Value", alignment: .leading).frame(width: 92)
                    tableHeader("Ref", alignment: .leading).frame(width: 64)
                    tableHeader("Status", alignment: .trailing).frame(width: 78)
                }
                .padding(.bottom, 6)
                .spanBottomHairline()

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        Text(row.marker)
                            .font(SpanFont.callout)
                            .foregroundStyle(SpanColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                            .font(SpanFont.mono(13, weight: .bold))
                            .foregroundStyle(SpanColor.textPrimary)
                            .frame(width: 92, alignment: .leading)
                        Text(row.reference)
                            .font(.system(size: 10.5))
                            .foregroundStyle(SpanColor.textTertiary)
                            .frame(width: 64, alignment: .leading)
                        StatusBadge(text: glanceStatusLabel(row.flag),
                                    style: StatusBadgeStyle(flag: row.flag))
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    if row.id != rows.last?.id {
                        Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
                    }
                }
            }
        }
    }

    // Questions to ask — amber group headers + checkbox rows.
    private func questionsSection(_ groups: [QuestionGroup]) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SpanSectionLabel("Questions to ask")
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.system)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(SpanColor.statusYellow)
                        .textCase(.uppercase)
                        .kerning(0.4)
                        .padding(.bottom, 4)
                    ForEach(group.questions, id: \.self) { q in
                        let key = "\(group.system)|\(q)"
                        let checked = model?.checkedQuestions.contains(key) ?? false
                        Button { toggle(key) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                checkbox(checked)
                                Text(q)
                                    .font(SpanFont.callout)
                                    .foregroundStyle(SpanColor.textPrimary)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .spanBottomHairline()
                    }
                }
            }
        }
    }

    // Supplements — Why / Caution / Verdict (no doses) + citation chips.
    private func supplementsSection(_ rows: [SupplementRow]) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            SpanSectionLabel("Supplements to discuss")
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.item)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SpanColor.textPrimary)
                        Spacer()
                        StatusBadge(text: verdictBadge(row.verdict), style: verdictStyle(row.verdict))
                    }
                    Text(row.why)
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution = row.caution {
                        Text("Caution: \(caution)")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.statusYellow.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowChips(row.citations) { citation = $0 }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                if row.id != rows.last?.id {
                    Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
                }
            }
        }
    }

    // Gaps to flag — bulleted.
    private func gapsSection(_ gaps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SpanSectionLabel("Gaps to flag")
                .padding(.bottom, SpanSpacing.xs)
            ForEach(gaps, id: \.self) { gap in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(SpanColor.textTertiary)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(gap)
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .spanBottomHairline()
            }
        }
    }

    private var prepDisclaimer: some View {
        Text("Not a medical device. Educational only. Do not start, stop, or adjust any medication or supplement based on this sheet. Generated by AI · not clinically validated.")
            .spanDisclaimerStyle()
            .padding(SpanSpacing.gutter)
            .frame(maxWidth: .infinity)
            .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
            )
            .padding(.top, SpanSpacing.xs)
    }

    // MARK: Helpers

    private func tableHeader(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(SpanColor.textTertiary)
            .textCase(.uppercase)
            .kerning(0.9)
            .frame(maxWidth: alignment == .leading ? .infinity : nil, alignment: alignment)
    }

    private func checkbox(_ checked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(checked ? SpanColor.accent : SpanColor.borderStrong, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(checked ? SpanColor.accentBg : Color.clear)
            )
            .frame(width: 16, height: 16)
            .overlay {
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SpanColor.accent)
                }
            }
            .padding(.top, 1)
    }

    private func glanceStatusLabel(_ flag: MeasurementFlag) -> String {
        switch flag {
        case .high:   return "High"
        case .low:    return "Low"
        case .normal: return "Normal"
        case .none:   return "Not tested"
        }
    }

    private func verdictBadge(_ verdict: String) -> String {
        let v = verdict.lowercased()
        if v.contains("unproven") || v.contains("contested") { return "Unproven" }
        if v.contains("reasonable") { return "Reasonable" }
        if v.contains("check") { return "Check first" }
        return verdict
    }

    private func verdictStyle(_ verdict: String) -> StatusBadgeStyle {
        let v = verdict.lowercased()
        if v.contains("unproven") || v.contains("contested") { return .monitor }
        if v.contains("reasonable") { return .optimal }
        return .neutral
    }

    private func toggle(_ key: String) {
        guard let model else { return }
        if model.checkedQuestions.contains(key) { model.checkedQuestions.remove(key) }
        else { model.checkedQuestions.insert(key) }
    }
}

// MARK: - Citation chip flow

/// Wrapping row of citation chips (uses the shared FlowLayout).
private struct FlowChips: View {
    let sources: [Source]
    var onTap: (Source) -> Void

    init(_ sources: [Source], onTap: @escaping (Source) -> Void) {
        self.sources = sources
        self.onTap = onTap
    }

    var body: some View {
        if !sources.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(sources) { source in
                    CitationChip(source: source, onTap: onTap)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// A 3px purple progress bar for the generating phase.
private struct CheckinProgressBarP: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SpanColor.border)
                Capsule().fill(SpanColor.accent)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

#Preview("Entry") {
    NavigationStack { DoctorVisitPrepView() }
        .environment(AppEnvironment.preview)
}
