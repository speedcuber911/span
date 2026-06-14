//
//  AddReportsView.swift
//  Span — Screens 11 (Upload / Ingest) + 12 (Self-confirm Review).
//
//  Dark "Health Intelligence" revamp, faithful to span_screens_v2.html screens 11/12.
//   • Two purple-iconed `.cta` entry rows: "Select from Files / Drive" and
//     "Scan a paper report".
//   • A "Recent" list whose rows reflect ingestion-job status (done / parsing with a
//     thin purple progress bar / needs-review with a "Review" pill / duplicate).
//   • Tapping "Review" presents the Self-confirm Review sheet ("we read this as
//     HbA1c 6.7 — correct?") with the cropped value, the extracted-values table, and
//     Correct / Edit / Skip actions over a progress bar.
//
//  Consumes the same IngestionModel / [IngestionJob] DTOs unchanged.
//

import SwiftUI

struct AddReportsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: IngestionModel?
    @State private var showFilePicker = false
    @State private var showScanner = false
    @State private var reviewJob: IngestionJob?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                // Entry CTAs (.cta)
                CTARow(icon: "doc.badge.arrow.up.fill",
                       title: "Select from Files / Drive",
                       subtitle: "PDF, image, or scan") { showFilePicker = true }
                CTARow(icon: "camera.fill",
                       title: "Scan a paper report",
                       subtitle: "Camera · auto-corrected") { showScanner = true }

                SpanSectionLabel("Recent")
                    .padding(.top, SpanSpacing.xs)

                switch model?.state ?? .idle {
                case .idle, .loading:
                    ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 56) }
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let jobs):
                    VStack(spacing: 0) {
                        ForEach(jobs) { job in
                            UploadRow(job: job) { reviewJob = job }
                            if job.id != jobs.last?.id {
                                Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
                            }
                        }
                    }
                }

                Text("Stored securely in India · used only to generate your health trends.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
                    .padding(.top, SpanSpacing.xs)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.gutter)
        }
        .background(SpanColor.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Add reports")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Real impl: .fileImporter for files, VNDocumentCameraViewController for scan.
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.pdf, .image, .commaSeparatedText],
                      allowsMultipleSelection: true) { _ in }
        .sheet(item: $reviewJob) { job in
            SelfConfirmReviewSheet(job: job)
        }
        .task {
            if model == nil { model = IngestionModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }
}

// MARK: - Entry CTA row (.cta)

/// A dark CTA row: tinted surface, hairline border, large purple SF Symbol, title +
/// secondary subtitle. Matches `.cta` in the comp.
private struct CTARow: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpanSpacing.gutter) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(SpanColor.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SpanColor.textPrimary)
                    Text(subtitle)
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.vertical, 15)
            .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent upload row

private struct UploadRow: View {
    let job: IngestionJob
    var onReview: () -> Void

    var body: some View {
        HStack(spacing: SpanSpacing.gutter) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                Text(job.filename)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SpanColor.textPrimary)
                    .lineLimit(1)
                if let detail = job.detail {
                    Text(statusPrefix + detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }
                if (job.status == .parsing || job.status == .uploading), let progress = job.progress {
                    ThinProgressBar(value: progress)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if job.status == .needsReview {
                Button(action: onReview) {
                    StatusBadge(text: "Review", style: .monitor)
                }
                .buttonStyle(.plain)
            } else if job.status == .failed || job.status == .quarantined {
                StatusBadge(text: "Retry", style: .high)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.filename), \(job.detail ?? job.status.rawValue)")
    }

    private var iconTile: some View {
        Image(systemName: iconName)
            .font(.system(size: 18))
            .foregroundStyle(accentColor)
            .frame(width: 36, height: 36)
            .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
            )
    }

    private var iconName: String {
        switch job.status {
        case .committed, .extracted:           return "checkmark.circle.fill"
        case .parsing, .uploading, .uploaded,
             .enqueued, .intentCreated:        return "arrow.triangle.2.circlepath"
        case .needsReview:                     return "exclamationmark.triangle.fill"
        case .failed, .quarantined:            return "xmark.circle.fill"
        case .duplicate:                       return "doc.on.doc"
        }
    }

    /// Status word prefix shown before the detail line, matching the comp
    /// ("Done · 42 measurements saved", "Parsing · usually <2 min").
    private var statusPrefix: String {
        switch job.status {
        case .committed, .extracted: return job.detail?.lowercased().hasPrefix("done") == true ? "" : "Done · "
        case .parsing, .uploading:   return job.detail?.lowercased().contains("parsing") == true ? "" : "Parsing · "
        case .needsReview:           return job.detail?.lowercased().contains("review") == true ? "" : "Review · "
        case .duplicate:             return job.detail?.lowercased().contains("already") == true ? "" : "Duplicate · "
        default:                     return ""
        }
    }

    private var accentColor: Color {
        switch job.status {
        case .committed, .extracted:           return SpanColor.statusGreen
        case .parsing, .uploading, .uploaded,
             .enqueued, .intentCreated:        return SpanColor.statusYellow
        case .needsReview:                     return SpanColor.statusYellow
        case .failed, .quarantined:            return SpanColor.statusRed
        case .duplicate:                       return SpanColor.textTertiary
        }
    }
}

/// A 2px ingest progress bar (the comp's `.pbar` + `.pbf`).
private struct ThinProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SpanColor.border)
                Capsule().fill(SpanColor.accent)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Self-confirm Review (Screen 12)

/// "We read this as HbA1c 6.7 — please confirm." A cropped value over the report
/// image, the extracted-value table, and Correct / Edit / Skip actions over a
/// review-progress bar.
private struct SelfConfirmReviewSheet: View {
    let job: IngestionJob
    @Environment(\.dismiss) private var dismiss

    // Illustrative extraction for the in-review job (the DTO carries no detail —
    // the live screen would hydrate this from the extraction record).
    private let reviewedIndex = 2
    private let reviewedTotal = 4
    private let extractedValue = "6.7"
    private let rows: [(String, String)] = [
        ("Parameter", "HbA1c"),
        ("Value", "6.7"),
        ("Unit", "%"),
        ("Date", "14 Mar 2026"),
        ("Lab", "Thyrocare")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    Text("Found this value in your report — please confirm.")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)

                    extractionCard

                    Text("Is this correct?")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SpanColor.textPrimary)
                        .padding(.top, SpanSpacing.xs)

                    HStack(spacing: 9) {
                        Button { dismiss() } label: {
                            Label("Correct", systemImage: "checkmark")
                        }
                        .spanPrimaryButton()

                        Button { dismiss() } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .spanGhostButton()
                    }

                    Button { dismiss() } label: {
                        Label("Skip this extraction", systemImage: "xmark")
                    }
                    .spanGhostButton(tint: SpanColor.statusRed, border: SpanColor.statusRedBorder)

                    VStack(spacing: 6) {
                        ThinProgressBar(value: Double(reviewedIndex) / Double(reviewedTotal))
                            .frame(height: 3)
                        Text("\(reviewedIndex) of \(reviewedTotal) reviewed")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, SpanSpacing.md)
                }
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
            }
            .background(SpanColor.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Confirm extraction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .tint(SpanColor.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(reviewedIndex) of \(reviewedTotal)")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var extractionCard: some View {
        VStack(spacing: 0) {
            // Cropped report image with the highlighted extraction box.
            ZStack {
                Rectangle().fill(SpanColor.surfaceCard)
                Text("[ Report image crop ]")
                    .font(SpanFont.footnote.italic())
                    .foregroundStyle(SpanColor.borderStrong)
                Text(extractedValue)
                    .font(SpanFont.mono(20, weight: .bold))
                    .foregroundStyle(SpanColor.statusYellow)
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(SpanColor.statusYellowBg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(SpanColor.statusYellow, lineWidth: 2)
                    )
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)

            // Extracted values table.
            VStack(alignment: .leading, spacing: 0) {
                Text("Extracted values")
                    .spanSectionHeaderStyle()
                    .padding(.bottom, 10)
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack {
                        Text(row.0)
                            .font(.system(size: 11))
                            .foregroundStyle(SpanColor.textTertiary)
                        Spacer()
                        Text(row.1)
                            .font(row.0 == "Value" ? SpanFont.mono(17, weight: .bold)
                                                   : .system(size: 13, weight: .medium))
                            .foregroundStyle(SpanColor.textPrimary)
                    }
                    .padding(.vertical, 6)
                    if idx != rows.count - 1 {
                        Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
                    }
                }
            }
            .padding(SpanSpacing.md)
            .overlay(alignment: .top) {
                Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
            }
        }
        .background(SpanColor.surface, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
    }
}

#Preview {
    NavigationStack { AddReportsView() }
        .environment(AppEnvironment.preview)
}
