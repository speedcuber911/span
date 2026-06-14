//
//  AboutYouView.swift
//  Span — Screen 3. Onboarding profile step 1 (Demographics).
//
//  Faithful to about-you.png: "Demographics" nav title, "Step 1 of 3" / 33%
//  progress, "Let's set your baseline" heading, a grouped card of DOB / Biological
//  Sex / Height / Weight, a "Data encrypted & stored securely" reassurance chip,
//  and Continue + "Skip for now". BMI is computed for display only.
//

import SwiftUI

struct AboutYouView: View {
    @Bindable var draft: OnboardingDraft
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 1, total: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    VStack(spacing: 2) {
                        Text("Let's set your baseline")
                            .font(SpanFont.title2)
                            .foregroundStyle(SpanColor.textPrimary)
                        Text("This helps us tailor your clinical insights and standard ranges.")
                            .font(SpanFont.callout)
                            .foregroundStyle(SpanColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        FieldRow(label: "Date of Birth") {
                            DatePicker("", selection: $draft.dob, displayedComponents: .date)
                                .labelsHidden()
                        }
                        Divider()
                        FieldRow(label: "Biological Sex") {
                            Picker("", selection: $draft.sex) {
                                Text("Select").tag(String?.none)
                                Text("Male").tag(String?.some("male"))
                                Text("Female").tag(String?.some("female"))
                            }
                            .labelsHidden()
                            .tint(SpanColor.textPrimary)
                        }
                        Divider()
                        FieldRow(label: "Height") {
                            HStack {
                                TextField("0", text: $draft.heightCm)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                Text("cm").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                            }
                        }
                        Divider()
                        FieldRow(label: "Weight") {
                            HStack {
                                TextField("0", text: $draft.weightKg)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                Text("kg").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                            }
                        }
                    }
                    .spanCard(padding: 0)
                    .padding(.vertical, 4)

                    if let bmi = draft.bmi {
                        Text("BMI: \(bmi.formatted(.number.precision(.fractionLength(1)))) (calculated)")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textSecondary)
                    }
                    Text("Sex is used only to apply sex-specific reference ranges. Not used for any other purpose.")
                        .font(SpanFont.caption2)
                        .foregroundStyle(SpanColor.textTertiary)

                    Label("Data encrypted & stored securely", systemImage: "lock.fill")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(SpanColor.surfaceLow, in: Capsule())
                        .frame(maxWidth: .infinity)
                }
                .padding(SpanSpacing.md)
            }
            VStack(spacing: SpanSpacing.xs) {
                Button("Continue", action: onContinue).spanPrimaryButton()
                Button("Skip for now", action: onContinue)
                    .font(SpanFont.callout).foregroundStyle(SpanColor.textSecondary)
            }
            .padding(SpanSpacing.md)
        }
        .background(SpanColor.background)
        .navigationTitle("Demographics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared onboarding building blocks

struct ProgressHeader: View {
    let step: Int
    let total: Int

    var body: some View {
        VStack(spacing: SpanSpacing.xs) {
            HStack {
                Text("Step \(step) of \(total)")
                    .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                Spacer()
                Text("\(Int(Double(step) / Double(total) * 100))%")
                    .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
            }
            ProgressView(value: Double(step), total: Double(total)).tint(SpanColor.primary)
        }
        .padding(.horizontal, SpanSpacing.md)
        .padding(.top, SpanSpacing.xs)
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(label).font(SpanFont.body).foregroundStyle(SpanColor.textPrimary)
            Spacer()
            content
        }
        .padding(SpanSpacing.md)
    }
}

#Preview {
    NavigationStack { AboutYouView(draft: OnboardingDraft()) {} }
}
