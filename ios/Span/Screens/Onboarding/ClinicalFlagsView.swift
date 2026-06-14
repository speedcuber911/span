//
//  ClinicalFlagsView.swift
//  Span — Screen 4. Onboarding profile step 2 (Clinical Flags).
//
//  Faithful to clinical-details.png: "Clinical Flags" heading, Step 2 of 3, three
//  grouped cards — Smoking Status (single-select), Systolic Blood Pressure (field
//  + "I take BP meds" checkbox), Diabetes Status (single-select). All optional;
//  these are model inputs (NAFLD-FS / CV risk), never diagnoses.
//

import SwiftUI

struct ClinicalFlagsView: View {
    @Bindable var draft: OnboardingDraft
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 2, total: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    VStack(spacing: 2) {
                        Text("Clinical Flags").font(SpanFont.title2).foregroundStyle(SpanColor.textPrimary)
                        Text("Please provide the following baseline markers to calibrate your clinical algorithms.")
                            .font(SpanFont.callout).foregroundStyle(SpanColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    SelectCard(title: "Smoking Status",
                               options: ["Current Smoker", "Former Smoker", "Never Smoked"],
                               selection: $draft.smoking)

                    VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
                        Text("Systolic Blood Pressure").font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
                        HStack {
                            TextField("Recent reading (mmHg)", text: $draft.bpSystolic)
                                .keyboardType(.numberPad)
                            Text("mmHg").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                        }
                        .padding(SpanSpacing.gutter)
                        .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.small))
                        Button {
                            draft.bpTreated.toggle()
                        } label: {
                            HStack(spacing: SpanSpacing.xs) {
                                Image(systemName: draft.bpTreated ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(draft.bpTreated ? SpanColor.primary : SpanColor.textTertiary)
                                Text("I am currently taking medication for high blood pressure")
                                    .font(SpanFont.footnote).foregroundStyle(SpanColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .spanCard()

                    SelectCard(title: "Diabetes Status",
                               options: ["Diagnosed with Diabetes", "Diagnosed with Pre-diabetes", "None"],
                               selection: $draft.diabetes)
                }
                .padding(SpanSpacing.md)
            }
            Button("Continue", action: onContinue).spanPrimaryButton().padding(SpanSpacing.md)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Single-select option card (radio-style rows).
struct SelectCard: View {
    let title: String
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text(title).font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(option).font(SpanFont.body).foregroundStyle(SpanColor.textPrimary)
                        Spacer()
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == option ? SpanColor.primary : SpanColor.textTertiary)
                    }
                    .padding(SpanSpacing.gutter)
                    .background(
                        (selection == option ? SpanColor.primary.opacity(0.06) : SpanColor.surfaceLow),
                        in: RoundedRectangle(cornerRadius: SpanRadius.small)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .spanCard()
    }
}

#Preview {
    NavigationStack { ClinicalFlagsView(draft: OnboardingDraft()) {} }
}
