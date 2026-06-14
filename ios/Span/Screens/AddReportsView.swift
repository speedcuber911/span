//
//  AddReportsView.swift
//  Span — Screen 11. Ingestion / Upload.
//
//  Faithful to add-reports.png: "Upload Data" title, two large entry cards
//  (Select files from Files · Scan a paper report), then a "Recent Uploads" list
//  whose rows reflect ingestion job status (done / parsing+progress / needs
//  review + Review button / duplicate). Gmail is intentionally absent.
//

import SwiftUI

struct AddReportsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: IngestionModel?
    @State private var showFilePicker = false
    @State private var showScanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload Data")
                        .font(SpanFont.displayLarge)
                        .foregroundStyle(SpanColor.textPrimary)
                    Text("Securely add your lab results and medical documents for analysis.")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)
                }

                EntryCard(icon: "folder.fill", title: "Select files from Files",
                          subtitle: "PDFs, Images, CSVs · multiple files") {
                    showFilePicker = true
                }
                EntryCard(icon: "doc.viewfinder", title: "Scan a paper report",
                          subtitle: "Use your camera · auto-enhanced") {
                    showScanner = true
                }

                VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
                    Text("Recent Uploads").spanSectionHeaderStyle()
                    switch model?.state ?? .idle {
                    case .idle, .loading:
                        ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 64) }
                    case .failed(let message):
                        LoadFailureView(message: message) { Task { await model?.load() } }
                    case .loaded(let jobs):
                        ForEach(jobs) { job in UploadRow(job: job) }
                    }
                }

                Text("Reports are stored securely in India and are only used to generate your health trends.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
        // Real impl: .fileImporter for files, VNDocumentCameraViewController for scan.
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.pdf, .image, .commaSeparatedText],
                      allowsMultipleSelection: true) { _ in }
        .task {
            if model == nil { model = IngestionModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }
}

private struct EntryCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpanSpacing.xs) {
                ZStack {
                    Circle().fill(SpanColor.primary.opacity(0.10)).frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(SpanColor.primary)
                }
                Text(title)
                    .font(SpanFont.headline)
                    .foregroundStyle(SpanColor.textPrimary)
                Text(subtitle)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpanSpacing.lg)
            .spanCard(padding: 0)
        }
        .buttonStyle(.plain)
    }
}

private struct UploadRow: View {
    let job: IngestionJob

    var body: some View {
        HStack(spacing: SpanSpacing.gutter) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(job.filename)
                    .font(SpanFont.callout.weight(.medium))
                    .foregroundStyle(SpanColor.textPrimary)
                    .lineLimit(1)
                if let detail = job.detail {
                    Text(detail)
                        .font(SpanFont.caption2)
                        .foregroundStyle(detailColor)
                }
                if job.status == .parsing || job.status == .uploading, let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(SpanColor.primary)
                }
            }
            Spacer()
            if job.status == .needsReview {
                Text("Review")
                    .font(SpanFont.footnote.weight(.semibold))
                    .foregroundStyle(SpanColor.primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(SpanColor.primary.opacity(0.1), in: Capsule())
            } else if job.status == .failed {
                Text("Try again")
                    .font(SpanFont.footnote.weight(.semibold))
                    .foregroundStyle(SpanColor.statusRed)
            }
        }
        .spanCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.filename), \(job.detail ?? job.status.rawValue)")
    }

    private var detailColor: Color {
        switch job.status {
        case .committed: return SpanColor.textSecondary
        case .needsReview: return SpanColor.statusRed
        case .failed, .quarantined: return SpanColor.statusRed
        case .duplicate: return SpanColor.textTertiary
        default: return SpanColor.textSecondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .committed:
            badge("checkmark.circle.fill", SpanColor.statusGreen)
        case .needsReview:
            badge("exclamationmark.circle.fill", SpanColor.statusRed)
        case .failed, .quarantined:
            badge("xmark.circle.fill", SpanColor.statusRed)
        case .duplicate:
            badge("doc.on.doc", SpanColor.textTertiary)
        case .parsing, .uploading, .uploaded, .enqueued, .intentCreated, .extracted:
            ProgressView().controlSize(.small).frame(width: 24, height: 24)
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
    }
}

#Preview {
    NavigationStack { AddReportsView() }
        .environment(AppEnvironment.preview)
}
