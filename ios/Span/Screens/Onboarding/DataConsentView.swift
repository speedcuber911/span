//
//  DataConsentView.swift
//  Span — Screen 2. Onboarding consent (DPDP + Educational Disclaimer).
//
//  Faithful to data-and-consent.png: "Data Consent" title, a DPDP intro, three
//  granular scope rows each with a toggle (Data Ingestion / Biomarker Extraction
//  / Algorithmic Profiling), the standalone Educational Disclaimer card, and the
//  "I understand — continue" primary button (active only with base scopes on).
//

import SwiftUI

struct DataConsentView: View {
    var onContinue: () -> Void

    @State private var ingestion = true
    @State private var extraction = true
    @State private var profiling = true

    private var canContinue: Bool { ingestion && extraction }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    Text("Data Consent")
                        .font(SpanFont.displayLarge)
                        .foregroundStyle(SpanColor.textPrimary)
                    Text("Under the Digital Personal Data Protection Act (DPDP Act 2023), we require your explicit consent to process your health data. You maintain complete control over how your information is used.")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)

                    ConsentScope(icon: "tray.and.arrow.down", title: "Data Ingestion",
                                 detail: "Allow Span to securely collect and store your lab reports, PDF documents, and connected device data in our encrypted vaults.",
                                 isOn: $ingestion)
                    ConsentScope(icon: "doc.text.magnifyingglass", title: "Biomarker Extraction",
                                 detail: "Permit our clinical algorithms to read, extract, and structure individual biomarkers (e.g. HbA1c, LDL) from your unstructured documents.",
                                 isOn: $extraction)
                    ConsentScope(icon: "wand.and.stars", title: "Algorithmic Profiling",
                                 detail: "Enable the creation of personalized longevity and risk profiles based on extracted data to provide tailored health insights.",
                                 isOn: $profiling)

                    // Educational disclaimer (standalone)
                    VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                        Label("Educational Disclaimer", systemImage: "exclamationmark.shield")
                            .font(SpanFont.headline)
                            .foregroundStyle(SpanColor.textPrimary)
                        Text("Span Health provides clinical data interpretation and evidence-based literature retrieval. We do not provide medical diagnosis, treatment, or professional medical advice. The insights generated are for informational and educational purposes only. Always consult a qualified healthcare provider before making any decisions regarding your health or medical conditions based on the information provided by this application.")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textSecondary)
                        Text("Source: DPDP Act 2023 Sec 4 · NMC Guidelines 2023")
                            .font(SpanFont.caption2)
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                    .spanCard()
                    .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.card))

                    if !canContinue {
                        Text("Span requires data ingestion and biomarker extraction consent to process lab reports. You can delete your account at any time in Settings.")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.statusRed)
                    }
                }
                .padding(SpanSpacing.md)
            }
            Button("I understand — continue", action: onContinue)
                .spanPrimaryButton(enabled: canContinue)
                .padding(SpanSpacing.md)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConsentScope: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SpanSpacing.gutter) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(SpanColor.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
                Text(detail).font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
            }
            Toggle("", isOn: $isOn).labelsHidden().tint(SpanColor.primary)
        }
        .spanCard()
    }
}

#Preview {
    NavigationStack { DataConsentView {} }
}
