//
//  SpanApp.swift
//  Span — app entry point.
//
//  Wires the dependency container (MockSpanAPI for now; swap to LiveSpanAPI once
//  the EC2 backend is live) and gates on Sign in with Apple before showing the
//  root tab experience.
//

import SwiftUI

@main
struct SpanApp: App {
    // Using `BundledSpanAPI()` — renders real parsed lab data from the bundled
    // sample-data.json offline. Swap to `MockSpanAPI()` for the old hardcoded
    // sample, or `LiveSpanAPI()` to talk to the EC2 backend.
    @State private var env = AppEnvironment(api: BundledSpanAPI())
    @State private var session = SessionState()

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.phase {
                case .signedOut:
                    SignInWithAppleView(session: session)
                case .onboarding:
                    OnboardingFlowView(session: session)
                case .signedIn:
                    RootView()
                }
            }
            .environment(env)
            .tint(SpanColor.primary)
        }
    }
}

/// Top-level session / onboarding gate.
@MainActor @Observable
final class SessionState {
    enum Phase { case signedOut, onboarding, signedIn }
    var phase: Phase = .signedOut

    func didSignIn(firstTime: Bool) {
        phase = firstTime ? .onboarding : .signedIn
    }

    func finishOnboarding() { phase = .signedIn }
    func skipToApp() { phase = .signedIn }
}
