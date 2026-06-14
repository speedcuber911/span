//
//  AboutYouView.swift
//  Span — Screen 3. Onboarding profile step 1 (Demographics).
//
//  Dark revamp (HTML screen 3): progress dots header ("Step 1 of 3"), "Tell us
//  about yourself" heading, a DOB date field, a Male/Female segmented control,
//  Height & Weight .inp cards with big mono values, a green BMI reassurance band,
//  and Continue + "Skip for now". BMI is computed for display only.
//

import SwiftUI

struct AboutYouView: View {
    @Bindable var draft: OnboardingDraft
    var onContinue: () -> Void

    private var sexIndex: Int {
        get { draft.sex == "female" ? 1 : 0 }
        nonmutating set { draft.sex = newValue == 1 ? "female" : "male" }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 1, total: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tell us about yourself")
                        .font(.system(size: 22, weight: .bold))
                        .kerning(-0.5)
                        .foregroundStyle(SpanColor.textPrimary)
                        .padding(.bottom, 5)
                    Text("We use this to apply the right reference ranges.")
                        .font(.system(size: 13))
                        .foregroundStyle(SpanColor.textSecondary)
                        .padding(.bottom, SpanSpacing.md)

                    // Date of birth
                    SpanSectionLabel("Date of birth")
                        .padding(.bottom, SpanSpacing.xs)
                    HStack {
                        DatePicker("", selection: $draft.dob, displayedComponents: .date)
                            .labelsHidden()
                            .tint(SpanColor.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
                        .strokeBorder(SpanColor.borderStrong, lineWidth: SpanSpacing.hairline))
                    .padding(.bottom, SpanSpacing.md)

                    // Biological sex
                    SpanSectionLabel("Biological sex")
                        .padding(.bottom, SpanSpacing.xs)
                    SpanSegmentedControl(
                        options: ["Male", "Female"],
                        selection: Binding(get: { sexIndex }, set: { sexIndex = $0 })
                    )
                    .padding(.bottom, SpanSpacing.md)

                    // Height & weight
                    SpanSectionLabel("Height & weight")
                        .padding(.bottom, SpanSpacing.xs)
                    HStack(spacing: SpanSpacing.xs) {
                        ValueInputCard(label: "Height", text: $draft.heightCm, unit: "cm")
                        ValueInputCard(label: "Weight", text: $draft.weightKg, unit: "kg")
                    }
                    .padding(.bottom, SpanSpacing.gutter)

                    if let bmi = draft.bmi {
                        BMIBand(bmi: bmi)
                            .padding(.bottom, SpanSpacing.md)
                    }

                    Text("Sex is used only to apply sex-specific reference ranges. Not used for any other purpose.")
                        .font(.system(size: 10.5))
                        .lineSpacing(3)
                        .foregroundStyle(SpanColor.textTertiary)
                }
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
            }

            VStack(spacing: SpanSpacing.xs) {
                Button("Continue", action: onContinue).spanPrimaryButton()
                Button("Skip for now", action: onContinue).spanGhostButton()
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.vertical, SpanSpacing.gutter)
        }
        .background(SpanColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

// MARK: - Shared onboarding building blocks

/// Progress dots header (the comp's `.progdots`): a filled accent bar for the
/// current step, green bars for completed steps, a muted bar for upcoming steps,
/// plus a "Step N of M" label.
struct ProgressHeader: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(barColor(for: i))
                    .frame(width: i == step ? 24 : 18, height: 3)
            }
            Text("Step \(step) of \(total)")
                .font(.system(size: 10))
                .foregroundStyle(SpanColor.textSecondary)
                .padding(.leading, 1)
            Spacer()
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.vertical, 10)
        .spanBottomHairline()
    }

    private func barColor(for i: Int) -> Color {
        if i == step { return SpanColor.accent }
        if i < step { return SpanColor.statusGreen }
        return SpanColor.borderStrong
    }
}

/// A `.inp`-style value card: small uppercase label over a big mono number + unit.
struct ValueInputCard: View {
    let label: String
    @Binding var text: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(SpanColor.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("0", text: $text)
                    .font(SpanFont.mono(28, weight: .bold))
                    .foregroundStyle(SpanColor.textPrimary)
                    .keyboardType(.numberPad)
                    .fixedSize()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(SpanColor.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
            .strokeBorder(SpanColor.borderStrong, lineWidth: SpanSpacing.hairline))
    }
}

/// A row label + trailing content (kept for grouped form rows in onboarding).
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

/// The green "BMI … in the healthy range" reassurance band.
private struct BMIBand: View {
    let bmi: Double

    private var healthy: Bool { bmi >= 18.5 && bmi < 25 }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: healthy ? "checkmark" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(healthy ? SpanColor.statusGreen : SpanColor.statusYellow)
            (Text("BMI ")
             + Text(bmi.formatted(.number.precision(.fractionLength(1)))).font(SpanFont.mono(13, weight: .bold))
             + Text(healthy ? " — in the healthy range" : " — outside the healthy range"))
                .font(.system(size: 12.5))
                .foregroundStyle(SpanColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background((healthy ? SpanColor.statusGreenBg : SpanColor.statusYellowBg),
                    in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
            .strokeBorder(healthy ? SpanColor.statusGreenBorder : SpanColor.statusYellowBorder,
                          lineWidth: SpanSpacing.hairline))
    }
}

#Preview {
    NavigationStack { AboutYouView(draft: OnboardingDraft()) {} }
        .preferredColorScheme(.dark)
}
