//
//  ClinicalFlagsView.swift
//  Span — Screen 4. Onboarding profile step 2 (Clinical Flags).
//
//  Dark revamp (HTML screen 4): progress dots (Step 2 of 3), "A few clinical
//  details" heading, a Smoking radio group, a Systolic BP .inp value card with an
//  "On treatment" toggle, and a Diabetes / IFG radio group. All optional; these
//  are model inputs (NAFLD-FS / CV risk), never diagnoses.
//

import SwiftUI

struct ClinicalFlagsView: View {
    @Bindable var draft: OnboardingDraft
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 2, total: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("A few clinical details")
                        .font(.system(size: 22, weight: .bold))
                        .kerning(-0.5)
                        .foregroundStyle(SpanColor.textPrimary)
                        .padding(.bottom, 5)
                    Text("These unlock additional risk estimates. All fields are optional.")
                        .font(.system(size: 13))
                        .foregroundStyle(SpanColor.textSecondary)
                        .padding(.bottom, SpanSpacing.md)

                    // Smoking
                    SpanSectionLabel("Smoking")
                        .padding(.bottom, SpanSpacing.xs)
                    RadioGroupCard(options: ["Never smoked", "Former smoker", "Current smoker"],
                                   selection: $draft.smoking)
                        .padding(.bottom, SpanSpacing.md)

                    // Blood pressure
                    SpanSectionLabel("Blood pressure")
                        .padding(.bottom, SpanSpacing.xs)
                    HStack(spacing: SpanSpacing.gutter) {
                        ValueInputCard(label: "Systolic", text: $draft.bpSystolic, unit: "mmHg")
                        Button {
                            draft.bpTreated.toggle()
                        } label: {
                            HStack(spacing: 7) {
                                SpanToggle(isOn: $draft.bpTreated)
                                    .allowsHitTesting(false)
                                Text("On treatment")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SpanColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, SpanSpacing.md)

                    // Diabetes / IFG
                    SpanSectionLabel("Diabetes / IFG")
                        .padding(.bottom, SpanSpacing.xs)
                    RadioGroupCard(options: ["No known diabetes or IFG", "Impaired fasting glucose", "Type 2 diabetes"],
                                   selection: $draft.diabetes)
                }
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
            }

            Button("Continue", action: onContinue)
                .spanPrimaryButton()
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.vertical, SpanSpacing.gutter)
        }
        .background(SpanColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// A grouped radio card (single-select) matching the comp's `radio()`: a filled
/// purple ring on the selected row, hairline-bordered card with row dividers.
struct RadioGroupCard: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                let active = selection == option
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle()
                                .strokeBorder(active ? SpanColor.accent : SpanColor.borderStrong,
                                              lineWidth: active ? 5 : SpanSpacing.hairline)
                                .frame(width: 18, height: 18)
                        }
                        Text(option)
                            .font(.system(size: 13))
                            .foregroundStyle(active ? SpanColor.textPrimary : SpanColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if idx < options.count - 1 {
                            Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
            .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline))
    }
}

/// Backwards-compatible single-select card used elsewhere in onboarding
/// (title label above a dark radio group).
struct SelectCard: View {
    let title: String
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            SpanSectionLabel(title)
            RadioGroupCard(options: options, selection: $selection)
        }
    }
}

#Preview {
    NavigationStack { ClinicalFlagsView(draft: OnboardingDraft()) {} }
        .preferredColorScheme(.dark)
}
