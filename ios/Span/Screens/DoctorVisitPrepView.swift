//
//  DoctorVisitPrepView.swift
//  Span — Screen 14. Doctor-Visit Prep Sheet.
//
//  Faithful to doctor-visit-prep.png. Three phases:
//   • entry      — "Generate prep sheet" CTA
//   • generating — progress bar + "Reviewing your lab trends…" copy
//   • ready       — Raise This First / Key Markers at a Glance / Questions to Ask
//                   (tickable) / Lifestyle & Supplements / Gaps clinician missed
//   The closing disclaimer is the fixed, code-appended prep-sheet disclaimer.
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
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Prep")
        .navigationBarTitleDisplayMode(.large)
        .citationSheet($citation)
        .task { if model == nil { model = PrepModel(api: env.api) } }
    }

    // MARK: Entry

    private var entryState: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Your next doctor's appointment is a chance to discuss what your data shows.")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            Button("Generate prep sheet") { Task { await model?.generate() } }
                .spanPrimaryButton()
            Text("Takes about 30–60 seconds. Based on your most recent lab results.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
            Divider()
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
            ProgressView(value: progress).tint(SpanColor.primary)
            Text("\(Int(progress * 100))%")
                .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Label("Reviewing your lab trends.", systemImage: "chart.line.uptrend.xyaxis")
                Label("Identifying questions to ask.", systemImage: "questionmark.circle")
                Label("Adding citations.", systemImage: "text.book.closed")
            }
            .font(SpanFont.footnote)
            .foregroundStyle(SpanColor.textSecondary)
        }
        .spanCard()
    }

    // MARK: Ready

    @ViewBuilder
    private func readyState(_ report: PrepReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doctor-Visit Prep")
                    .font(SpanFont.title2)
                    .foregroundStyle(SpanColor.textPrimary)
                Text("Generated \(report.generatedAt.formatted(.dateTime.day().month().year()))")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up").foregroundStyle(SpanColor.primary)
        }

        // Raise this first
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Label("RAISE THIS FIRST", systemImage: "exclamationmark.circle.fill")
                .font(SpanFont.footnote.weight(.semibold))
                .foregroundStyle(SpanColor.statusRed)
            Text(report.raiseFirst.body)
                .font(SpanFont.body)
                .foregroundStyle(SpanColor.textPrimary)
            ForEach(report.raiseFirst.citations) { CitationChip(source: $0) { citation = $0 } }
        }
        .spanCard()

        // Glance table
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("Key Markers at a Glance").spanSectionHeaderStyle()
            ForEach(report.glanceTable) { row in
                HStack {
                    Text(row.marker).font(SpanFont.callout).foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                    Text(row.value).font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(row.reference).font(SpanFont.caption2).foregroundStyle(SpanColor.textTertiary)
                        .frame(width: 56, alignment: .trailing)
                    if row.flag == .none {
                        Text("—").font(SpanFont.caption2).foregroundStyle(SpanColor.textTertiary).frame(width: 24)
                    } else {
                        FlagDot(flag: row.flag).frame(width: 24)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .spanCard()

        // Questions to ask (tickable)
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("Questions to Ask").spanSectionHeaderStyle()
            ForEach(report.questions) { group in
                VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                    Text(group.system)
                        .font(SpanFont.headline)
                        .foregroundStyle(SpanColor.textPrimary)
                    ForEach(group.questions, id: \.self) { q in
                        let key = "\(group.system)|\(q)"
                        Button {
                            toggle(key)
                        } label: {
                            HStack(alignment: .top, spacing: SpanSpacing.xs) {
                                Image(systemName: (model?.checkedQuestions.contains(key) ?? false) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle((model?.checkedQuestions.contains(key) ?? false) ? SpanColor.primary : SpanColor.textTertiary)
                                Text(q)
                                    .font(SpanFont.callout)
                                    .foregroundStyle(SpanColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Tick the questions that matter most to you before your visit. It is normal to feel a bit anxious writing these down.")
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textTertiary)
        }
        .spanCard()

        // Lifestyle & supplements
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("Lifestyle & Supplements to Discuss").spanSectionHeaderStyle()
            ForEach(report.lifestyleSupplements) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.item).font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
                    Text(row.why).font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                    if let caution = row.caution {
                        Text("Caution: \(caution)").font(SpanFont.footnote).foregroundStyle(SpanColor.statusYellow.opacity(0.9))
                    }
                    Text("Verdict: \(row.verdict)").font(SpanFont.footnote.weight(.medium)).foregroundStyle(SpanColor.textPrimary)
                    ForEach(row.citations) { CitationChip(source: $0) { citation = $0 } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                Divider()
            }
        }
        .spanCard()

        // Gaps
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("Gaps Your Clinician Likely Missed").spanSectionHeaderStyle()
            ForEach(report.gapsClinicianMissed, id: \.self) { gap in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundStyle(SpanColor.textTertiary)
                    Text(gap).font(SpanFont.callout).foregroundStyle(SpanColor.textPrimary)
                }
            }
        }
        .spanCard()

        prepDisclaimer
    }

    private var prepDisclaimer: some View {
        Text("Span is not a medical device. This sheet is educational only. All information must be discussed with a qualified clinician. Do not start, stop, or adjust any medication or supplement based on this sheet alone.\nGenerated by AI · Not clinically validated · Educational only.")
            .font(SpanFont.footnote)
            .foregroundStyle(SpanColor.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.vertical, SpanSpacing.md)
    }

    private func toggle(_ key: String) {
        guard let model else { return }
        if model.checkedQuestions.contains(key) { model.checkedQuestions.remove(key) }
        else { model.checkedQuestions.insert(key) }
    }
}

#Preview("Entry") {
    NavigationStack { DoctorVisitPrepView() }
        .environment(AppEnvironment.preview)
}
