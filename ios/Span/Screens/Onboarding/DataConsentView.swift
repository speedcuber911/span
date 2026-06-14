//
//  DataConsentView.swift
//  Span — Screen 2. Onboarding consent (DPDP + Educational Disclaimer).
//
//  Dark revamp (HTML screen 2): a "Data & consent" nav bar, "How Span uses your
//  data" intro with the DPDP / ap-south-1 note, a CONSENTS section of per-scope
//  rows each with a green pill toggle (.tog), a withdraw note, a standalone
//  Educational Disclaimer card, the "I understand — continue" primary button, and
//  the persistent educational footer.
//

import SwiftUI

struct DataConsentView: View {
    var onContinue: () -> Void

    @State private var ingestion = true
    @State private var extraction = true
    @State private var profiling = true

    // Base scopes (lab reports + biomarker extraction) are required to function.
    private var canContinue: Bool { ingestion && extraction }

    var body: some View {
        VStack(spacing: 0) {
            SpanNavBar(title: "Data & consent")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How Span uses your data")
                        .font(.system(size: 19, weight: .bold))
                        .kerning(-0.4)
                        .foregroundStyle(SpanColor.textPrimary)
                        .padding(.bottom, 5)
                    Text("Span stores your lab reports and measurements on servers in India, under the DPDP Act 2023.")
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(SpanColor.textSecondary)
                        .padding(.bottom, SpanSpacing.md)

                    SpanSectionLabel("Consents")
                        .padding(.bottom, SpanSpacing.xs)

                    ConsentRow(title: "Lab reports & extracted data",
                               purpose: "show you trends · India (ap-south-1)",
                               isOn: $ingestion)
                    ConsentRow(title: "Biomarker extraction",
                               purpose: "read HbA1c, LDL, etc. from documents",
                               isOn: $extraction)
                    ConsentRow(title: "Profile (age, sex, conditions)",
                               purpose: "personalise reference ranges",
                               isOn: $profiling)

                    Text("Withdraw any consent at any time in Settings.")
                        .font(.system(size: 10.5))
                        .lineSpacing(3)
                        .foregroundStyle(SpanColor.textTertiary)
                        .padding(.top, SpanSpacing.gutter)
                        .padding(.bottom, SpanSpacing.md)

                    if !canContinue {
                        Text("Lab reports and biomarker extraction are required to process your reports. You can delete your account anytime in Settings.")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.statusRed)
                            .padding(.bottom, SpanSpacing.gutter)
                    }

                    Divider().overlay(SpanColor.border)
                        .padding(.bottom, SpanSpacing.md)

                    // Educational disclaimer (standalone card)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Educational disclaimer")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(SpanColor.textTertiary)
                        Text("Span is not a medical device. It does not diagnose, prescribe, or treat. All results are educational. Discuss everything with a qualified clinician.")
                            .font(.system(size: 12.5))
                            .lineSpacing(5)
                            .foregroundStyle(SpanColor.textSecondary)
                    }
                    .spanCard()
                    .padding(.bottom, SpanSpacing.lg)

                    Button("I understand — continue", action: onContinue)
                        .spanPrimaryButton(enabled: canContinue)
                }
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
            }

            DisclaimerFooter()
        }
        .background(SpanColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// A consent scope row: title + purpose on the left, a green pill toggle right.
private struct ConsentRow: View {
    let title: String
    let purpose: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: SpanSpacing.gutter) {
            SpanToggle(isOn: $isOn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpanColor.textPrimary)
                Text("Purpose: \(purpose)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(SpanColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .spanBottomHairline()
    }
}

#Preview {
    NavigationStack { DataConsentView {} }
        .preferredColorScheme(.dark)
}
