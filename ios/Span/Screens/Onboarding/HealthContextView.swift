//
//  HealthContextView.swift
//  Span — Screen 5. Onboarding profile step 3 (Conditions / Meds / Goals).
//
//  Dark revamp (HTML screen 5): progress dots (Step 3 of 3), "Almost done"
//  heading, Chronic Conditions / Current Medications / Supplements chip groups
//  (names only — no doses) with a purple "+ Add" chip, and a single-select
//  Primary Focus radio group. Finishes onboarding.
//

import SwiftUI

struct HealthContextView: View {
    @Bindable var draft: OnboardingDraft
    var onComplete: () -> Void

    private let conditionOptions = ["Diabetes Type 2", "Hypertension", "PCOS",
                                    "Hypothyroidism", "Insulin Resistance"]
    private let goals = ["Understanding my lab trends", "Preparing for a doctor visit",
                         "Tracking my metabolic health", "Longevity / healthy ageing"]

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 3, total: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Almost done")
                        .font(.system(size: 22, weight: .bold))
                        .kerning(-0.5)
                        .foregroundStyle(SpanColor.textPrimary)
                        .padding(.bottom, 5)
                    Text("Name only — no doses needed.")
                        .font(.system(size: 13))
                        .foregroundStyle(SpanColor.textSecondary)
                        .padding(.bottom, SpanSpacing.md)

                    // Chronic conditions
                    SpanSectionLabel("Chronic conditions")
                        .padding(.bottom, SpanSpacing.xs)
                    FlowLayout(spacing: 6) {
                        ForEach(conditionOptions, id: \.self) { condition in
                            let selected = draft.conditions.contains(condition)
                            TagChip(text: condition, removable: selected, accent: false) {
                                if selected { draft.conditions.remove(condition) }
                                else { draft.conditions.insert(condition) }
                            }
                        }
                        TagChip(text: "+ Add condition", removable: false, accent: true) {}
                    }
                    .padding(.bottom, SpanSpacing.md)

                    // Current medications (names only)
                    SpanSectionLabel("Current medications")
                        .padding(.bottom, SpanSpacing.xs)
                    FlowLayout(spacing: 6) {
                        ForEach(draft.medications, id: \.self) { med in
                            TagChip(text: med, removable: true, accent: false) {
                                draft.medications.removeAll { $0 == med }
                            }
                        }
                        TagChip(text: "+ Add medication", removable: false, accent: true) {}
                    }
                    .padding(.bottom, SpanSpacing.md)

                    // Supplements (names only)
                    SpanSectionLabel("Supplements")
                        .padding(.bottom, SpanSpacing.xs)
                    FlowLayout(spacing: 6) {
                        ForEach(draft.supplements, id: \.self) { supp in
                            TagChip(text: supp, removable: true, accent: false) {
                                draft.supplements.removeAll { $0 == supp }
                            }
                        }
                        TagChip(text: "+ Add supplement", removable: false, accent: true) {}
                    }
                    .padding(.bottom, SpanSpacing.md)

                    // Primary focus
                    SelectCard(title: "Primary focus", options: goals, selection: $draft.primaryGoal)
                }
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
            }

            Button("Complete profile", action: onComplete)
                .spanPrimaryButton()
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.vertical, SpanSpacing.gutter)
        }
        .background(SpanColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// A pill chip (the comp's `chip()`): purple bg/border for the "+ Add" action,
/// dark surface for selected/listed items with a trailing ✕ when removable.
private struct TagChip: View {
    let text: String
    let removable: Bool
    let accent: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                if removable {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(accent ? SpanColor.accent : SpanColor.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((accent ? SpanColor.accentBg : SpanColor.surfaceCard), in: Capsule())
            .overlay(Capsule().strokeBorder(accent ? SpanColor.accentBorder : SpanColor.borderStrong,
                                            lineWidth: SpanSpacing.hairline))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HealthContextView(draft: OnboardingDraft()) {} }
        .preferredColorScheme(.dark)
}
