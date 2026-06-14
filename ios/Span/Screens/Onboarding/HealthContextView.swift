//
//  HealthContextView.swift
//  Span — Screen 5. Onboarding profile step 3 (Conditions / Meds / Goals).
//
//  Faithful to health-context.png: "Medical Profile", Step 3 of 3 ("Almost
//  done"), Chronic Conditions chip multi-select, Medications & Supplements
//  (names only — no doses), and a single-select Primary Goal. Finishes onboarding.
//

import SwiftUI

struct HealthContextView: View {
    @Bindable var draft: OnboardingDraft
    var onComplete: () -> Void

    private let conditionOptions = ["Diabetes Type 2", "Hypertension", "PCOS",
                                    "Hypothyroidism", "Insulin Resistance"]
    private let goals = ["Optimize Energy Levels", "Manage Metabolic Health",
                         "Improve Sleep Quality", "General Longevity"]

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(step: 3, total: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medical Profile").font(SpanFont.title2).foregroundStyle(SpanColor.textPrimary)
                        Text("Help us contextualize your data to provide more accurate insights.")
                            .font(SpanFont.callout).foregroundStyle(SpanColor.textSecondary)
                    }

                    // Chronic conditions
                    VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                        Text("Chronic Conditions").font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
                        Text("Select any diagnosed conditions.").font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                        FlowTags {
                            ForEach(conditionOptions, id: \.self) { condition in
                                ConditionChip(text: condition, selected: draft.conditions.contains(condition)) {
                                    if draft.conditions.contains(condition) { draft.conditions.remove(condition) }
                                    else { draft.conditions.insert(condition) }
                                }
                            }
                            ConditionChip(text: "+ Other", selected: false) {}
                        }
                    }
                    .spanCard()

                    // Medications & supplements (names only)
                    VStack(alignment: .leading, spacing: SpanSpacing.xs) {
                        Text("Medications & Supplements").font(SpanFont.headline).foregroundStyle(SpanColor.textPrimary)
                        Text("List current meds (names only).").font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                        ForEach(draft.medications, id: \.self) { med in
                            HStack {
                                Text(med).font(SpanFont.body).foregroundStyle(SpanColor.textPrimary)
                                Spacer()
                                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(SpanColor.textTertiary)
                            }
                            .padding(SpanSpacing.gutter)
                            .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.small))
                        }
                        Text("Add medication/supplement")
                            .font(SpanFont.callout).foregroundStyle(SpanColor.textTertiary)
                            .padding(SpanSpacing.gutter)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.small))
                    }
                    .spanCard()

                    // Primary goal
                    SelectCard(title: "Primary Goal", options: goals, selection: $draft.primaryGoal)
                }
                .padding(SpanSpacing.md)
            }
            Button("Complete Profile", action: onComplete).spanPrimaryButton().padding(SpanSpacing.md)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConditionChip: View {
    let text: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(SpanFont.footnote)
                .foregroundStyle(selected ? SpanColor.onPrimary : SpanColor.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? SpanColor.primary : SpanColor.surfaceLow, in: Capsule())
                .overlay(Capsule().stroke(SpanColor.outlineVariant.opacity(0.6), lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HealthContextView(draft: OnboardingDraft()) {} }
}
