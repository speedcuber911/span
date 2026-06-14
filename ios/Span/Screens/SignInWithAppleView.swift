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
            // Wordmark — pulse-into-uptrend mark echoing the app icon
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(SpanColor.primary)
                Text("Span")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(SpanColor.primary)
            }
            Text("Longevity, decoded from your bloodwork.")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, SpanSpacing.md)
                .padding(.horizontal, SpanSpacing.lg)
            Text("AI turns years of lab reports into clear organ-system trends, a biological-age read, and an evidence-backed prep sheet for your next doctor visit.")
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, SpanSpacing.xs)
                .padding(.horizontal, SpanSpacing.xl)

            Spacer()

            // Made in India badge
            IndianFlagBadge()
                .padding(.bottom, SpanSpacing.md)

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

// MARK: - Made in India badge

/// A small "Made in India" pill with a drawn tricolour flag (no image asset).
struct IndianFlagBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            TricolourFlag()
                .frame(width: 22, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(SpanColor.outlineVariant.opacity(0.5), lineWidth: 0.5)
                )
            Text("Made in India")
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(SpanColor.surface)
        )
        .overlay(
            Capsule().stroke(SpanColor.outlineVariant.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made in India")
    }
}

/// The Indian national flag drawn with shapes: saffron, white, green stripes
/// and the navy Ashoka Chakra (24-spoke wheel) centred on the white band.
private struct TricolourFlag: View {
    private let saffron = Color(spanHex: "#FF9933")
    private let green = Color(spanHex: "#138808")
    private let chakra = Color(spanHex: "#0A3A8A")

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            VStack(spacing: 0) {
                saffron
                Color.white
                green
            }
            .overlay(alignment: .center) {
                // Ashoka Chakra: ring + 24 spokes, sized to the white band.
                let d = h / 3 * 0.86
                ZStack {
                    Circle()
                        .stroke(chakra, lineWidth: max(0.6, d * 0.07))
                        .frame(width: d, height: d)
                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill(chakra)
                            .frame(width: max(0.4, d * 0.035), height: d / 2)
                            .offset(y: -d / 4)
                            .rotationEffect(.degrees(Double(i) * 15))
                    }
                }
                .frame(width: w, height: h)
            }
        }
    }
}

#Preview {
    SignInWithAppleView(session: SessionState())
}
