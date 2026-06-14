//
//  SignInWithAppleView.swift
//  Span — Screen 1. Sign in with Apple (sole entry point).
//
//  Faithful to sign-in-with-apple.png: centered Span wordmark, one-line value
//  prop, the native Sign in with Apple button, and the legal / India-only footer.
//  No username/password. The Apple identity token is exchanged server-side and
//  never persisted (see LiveSpanAPI.exchangeApple).
//

import SwiftUI
import AuthenticationServices

struct SignInWithAppleView: View {
    @Bindable var session: SessionState
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Spacer()
            // Wordmark
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SpanColor.primary)
                Text("Span")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(SpanColor.primary)
            }
            Text("Your health data, clearly.")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
                .padding(.top, SpanSpacing.md)
            Text("Understand trends. Prepare for your next visit.")
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SpanSpacing.xl)

            Spacer()

            if isWorking {
                ProgressView().padding(.bottom, SpanSpacing.md)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: SpanRadius.small))
                .padding(.horizontal, SpanSpacing.md)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.statusRed)
                    .padding(.top, SpanSpacing.xs)
            }

            // Legal footer
            VStack(spacing: SpanSpacing.xs) {
                (Text("By signing in you agree to our ")
                 + Text("Terms of Service").foregroundColor(SpanColor.primary)
                 + Text(" and ")
                 + Text("Privacy Policy").foregroundColor(SpanColor.primary)
                 + Text("."))
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
                    .multilineTextAlignment(.center)
                Text("INDIA ONLY · DATA STORED IN INDIA")
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
                Text("© 2026 Span Health · Clinical data powered by evidence-based research.")
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(SpanSpacing.md)
            .frame(maxWidth: .infinity)
            .background(SpanColor.surfaceLow)
        }
        .background(SpanColor.background.ignoresSafeArea())
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            // Real impl: send identityToken/authorizationCode/nonce to /v1/auth/apple.
            isWorking = true
            errorMessage = nil
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                session.didSignIn(firstTime: true)
            }
        case .failure(let error):
            // Apple cancel is silent; surface real transport errors only.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Something went wrong. Please try again."
            }
        }
    }
}

#Preview {
    SignInWithAppleView(session: SessionState())
}
