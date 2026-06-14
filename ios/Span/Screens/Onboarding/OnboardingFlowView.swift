//
//  OnboardingFlowView.swift
//  Span — onboarding stack driver.
//
//  Order (SCREENS.md Screens 2–6): Data & Consent → About You (demographics) →
//  Clinical Flags → Health Context → finish into the app. A shared @Observable
//  draft holds the in-progress profile; each step is its own view.
//

import SwiftUI

@MainActor @Observable
final class OnboardingDraft {
    // Demographics
    var dob: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    var sex: String?
    var heightCm: String = ""
    var weightKg: String = ""

    // Clinical flags
    var smoking: String?
    var bpSystolic: String = ""
    var bpTreated: Bool = false
    var diabetes: String?

    // Health context
    var conditions: Set<String> = []
    var medications: [String] = ["Levothyroxine"]
    var primaryGoal: String?

    var bmi: Double? {
        guard let h = Double(heightCm), let w = Double(weightKg), h > 0 else { return nil }
        let m = h / 100
        return w / (m * m)
    }
}

struct OnboardingFlowView: View {
    @Bindable var session: SessionState
    @State private var draft = OnboardingDraft()
    @State private var path: [OnboardingStep] = []

    enum OnboardingStep: Hashable { case aboutYou, clinicalFlags, healthContext }

    var body: some View {
        NavigationStack(path: $path) {
            DataConsentView { path.append(.aboutYou) }
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .aboutYou:
                        AboutYouView(draft: draft) { path.append(.clinicalFlags) }
                    case .clinicalFlags:
                        ClinicalFlagsView(draft: draft) { path.append(.healthContext) }
                    case .healthContext:
                        HealthContextView(draft: draft) { session.finishOnboarding() }
                    }
                }
        }
        .tint(SpanColor.primary)
    }
}

#Preview {
    OnboardingFlowView(session: SessionState())
}
