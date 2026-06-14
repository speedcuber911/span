//
//  SignInWithAppleView.swift
//  Span — Screen 1. Sign in with Apple (sole entry point).
//
//  Dark "Health Intelligence" revamp (v2-overview.jpeg / HTML screen 1):
//  "HEALTH INTELLIGENCE" eyebrow, a huge bold "Span" wordmark with a purple
//  underline accent, "Your lab reports, finally legible." headline, the value
//  subtext, a white "Sign in with Apple" button, and the Terms · Privacy /
//  India-only footer. The Made-in-India badge is kept, restyled for dark.
//
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
        VStack(spacing: 0) {
            Spacer(minLength: SpanSpacing.xl)

            // Eyebrow
            Text("Health Intelligence")
                .font(.system(size: 11, weight: .semibold))
                .kerning(6)
                .textCase(.uppercase)
                .foregroundStyle(SpanColor.textTertiary)
                .padding(.bottom, SpanSpacing.md)

            // Wordmark — huge bold, very tight tracking
            Text("Span")
                .font(.system(size: 80, weight: .heavy))
                .kerning(-4)
                .foregroundStyle(SpanColor.textPrimary)

            // Purple underline accent
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(SpanColor.accent.opacity(0.7))
                .frame(width: 40, height: 1.5)
                .padding(.top, 22)
                .padding(.bottom, 26)

            // Headline
            Text("Your lab reports,\nfinally legible.")
                .font(.system(size: 22, weight: .semibold))
                .kerning(-0.5)
                .lineSpacing(4)
                .foregroundStyle(SpanColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            // Subtext
            Text("8 organ systems. Trend lines across every result. Prep for every doctor visit.")
                .font(.system(size: 14))
                .lineSpacing(7)
                .foregroundStyle(SpanColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            Spacer()

            // Made in India badge — restyled for dark
            IndianFlagBadge()
                .padding(.bottom, SpanSpacing.md)

            // Sign in with Apple — white button
            if isWorking {
                ProgressView()
                    .tint(SpanColor.textPrimary)
                    .frame(height: 50)
                    .padding(.horizontal, SpanSpacing.lg)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, SpanSpacing.lg)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.statusRed)
                    .padding(.top, SpanSpacing.xs)
            }

            // Legal / India-only footer
            VStack(spacing: 0) {
                (Text("Agree to our ")
                 + Text("Terms").foregroundColor(SpanColor.accent)
                 + Text(" · ")
                 + Text("Privacy Policy").foregroundColor(SpanColor.accent))
                    .font(.system(size: 10))
                Text("India only · Data stored ap-south-1")
                    .font(.system(size: 10))
            }
            .foregroundStyle(SpanColor.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(7)
            .padding(.top, 14)

            Spacer(minLength: SpanSpacing.xl)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
/// Restyled for the dark theme (surface fill + hairline border).
struct IndianFlagBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            TricolourFlag()
                .frame(width: 22, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(SpanColor.borderStrong.opacity(0.6), lineWidth: 0.5)
                )
            Text("Made in India")
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(SpanColor.surfaceCard))
        .overlay(Capsule().stroke(SpanColor.border, lineWidth: SpanSpacing.hairline))
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
        .preferredColorScheme(.dark)
}
