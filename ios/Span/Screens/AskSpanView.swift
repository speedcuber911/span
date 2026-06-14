//
//  AskSpanView.swift
//  Span — Screen 16. Ask Span (voice consultant).
//
//  Dark "Health Intelligence" revamp, faithful to span_screens_v2.html screen 16.
//  Presented as a full-screen cover with its own NavigationStack.
//   • AI disclosure gate (shown every session, cannot be skipped).
//   • Active session: an agent-state eyebrow ("Listening"), the animated purple
//     WAVEFORM (the comp's `.wb` bars / `wv` keyframe), "Ask anything." headline, a
//     transcript card (user bubble in surface, Span bubble purple-tinted with the
//     "Discuss with your clinician" closer), push-to-talk, a text fallback, and the
//     "transcript only, no audio stored" privacy line.
//
//  Consumes the same VoiceConsultantModel / VoiceTurn unchanged.
//

import SwiftUI

struct AskSpanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = VoiceConsultantModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.disclosureAccepted {
                    sessionView
                } else {
                    disclosureGate
                }
            }
            .background(SpanColor.background.ignoresSafeArea())
            .navigationTitle("Ask Span")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .tint(SpanColor.accent)
                        .accessibilityLabel(model.disclosureAccepted ? "End session" : "Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(SpanColor.accent)
    }

    // MARK: Disclosure gate

    private var disclosureGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                HStack(spacing: SpanSpacing.xs) {
                    Image(systemName: "cpu")
                        .foregroundStyle(SpanColor.accent)
                    Text("AI disclosure")
                        .font(SpanFont.headline)
                        .foregroundStyle(SpanColor.textPrimary)
                }
                Text("Ask Span is an AI assistant. It is not a doctor and does not give medical advice.")
                    .font(SpanFont.body)
                    .foregroundStyle(SpanColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It can only discuss information already in your Span records, and will always ask you to discuss findings with a clinician.")
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This session’s transcript is stored in India and linked to your account. Audio is not recorded.")
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is a standalone consent. You may revoke it in Settings.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)

                Button("I understand — start session") { model.acceptDisclosure() }
                    .spanPrimaryButton()
                    .padding(.top, SpanSpacing.xs)
                Button("Not now") { dismiss() }
                    .spanGhostButton()
            }
            .spanCard()
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
        }
    }

    // MARK: Session

    private var sessionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                // Voice hero — agent-state eyebrow + waveform + headline.
                VStack(spacing: 0) {
                    Text(stateLabel)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(SpanColor.accent)
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .padding(.bottom, 22)
                    Waveform(active: model.agentState == .listening || model.agentState == .speaking)
                        .frame(height: 44)
                    Text("Ask anything.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SpanColor.textPrimary)
                        .kerning(-0.3)
                        .padding(.top, 22)
                        .padding(.bottom, 5)
                    Text("Your results. Your trends. Your questions.")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpanSpacing.lg)

                transcriptCard

                // Text fallback.
                Text("Can’t use voice?")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
                textInput

                Text("Sarvam AI · transcript only, no audio stored")
                    .spanDisclaimerStyle()
                    .padding(.top, SpanSpacing.xs)

                DisclaimerFooter()
                    .padding(.horizontal, -SpanSpacing.screenH)
                    .padding(.top, SpanSpacing.xs)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.xs)
        }
        .safeAreaInset(edge: .bottom) { pushToTalkBar }
    }

    private var transcriptCard: some View {
        VStack(spacing: 0) {
            // Header.
            HStack {
                Text("Transcript · \(Date().formatted(.dateTime.day().month().year()))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SpanColor.textTertiary)
                Spacer()
                Text("2:14")
                    .font(SpanFont.mono(10))
                    .foregroundStyle(SpanColor.textTertiary)
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.vertical, 10)
            .background(SpanColor.surfaceCard)
            .spanBottomHairline()

            // Turns.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.turns) { turn in
                    CaptionBubble(turn: turn)
                }
                if model.agentState == .thinking {
                    Text("Span: thinking…")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SpanSpacing.md)
        }
        .background(SpanColor.surface, in: RoundedRectangle(cornerRadius: SpanRadius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.cardLarge, style: .continuous)
                .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpanRadius.cardLarge, style: .continuous))
    }

    private var textInput: some View {
        HStack {
            Text("Type your question…")
                .font(SpanFont.body)
                .foregroundStyle(SpanColor.textTertiary)
            Spacer()
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SpanColor.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
                .strokeBorder(SpanColor.borderStrong, lineWidth: SpanSpacing.hairline)
        )
        .accessibilityLabel("Type your question")
    }

    // Push-to-talk control pinned to the bottom safe area.
    private var pushToTalkBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
            HStack(spacing: SpanSpacing.gutter) {
                Button {} label: {
                    Label("Hold to speak", systemImage: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SpanColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SpanColor.accentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(SpanColor.accentBorder, lineWidth: SpanSpacing.hairline)
                        )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if model.agentState != .listening { model.agentState = .listening } }
                        .onEnded { _ in model.agentState = .thinking }
                )
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.vertical, SpanSpacing.gutter)
            .background(SpanColor.surface)
        }
    }

    private var stateLabel: String {
        switch model.agentState {
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Speaking"
        case .escalated: return "Connecting you to support"
        case .idle:      return "Ready"
        }
    }
}

// MARK: - Caption bubble

private struct CaptionBubble: View {
    let turn: VoiceTurn

    private var isSpan: Bool { turn.speaker == .span }

    var body: some View {
        Text(turn.text)
            .font(SpanFont.callout)
            .foregroundStyle(isSpan ? SpanColor.textPrimary : SpanColor.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSpan ? SpanColor.accentBg : SpanColor.surfaceCard,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSpan ? SpanColor.accentBorder : Color.clear,
                                  lineWidth: SpanSpacing.hairline)
            )
            .accessibilityLabel("\(isSpan ? "Span" : "You"): \(turn.text)")
    }
}

// MARK: - Animated waveform (.wb bars)

/// The comp's animated purple waveform: a row of thin rounded bars that pulse on the
/// `wv` keyframe (scaleY .18 → 1). Respects Reduce Motion (renders static bars).
private struct Waveform: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    // Fixed per-bar base heights + phase delays from the comp.
    private let heights: [CGFloat] = [18, 28, 38, 30, 22, 36, 26, 32, 20, 34,
                                      16, 24, 40, 22, 30, 28, 36, 18, 26, 14]
    private let delays: [Double] = [0, 0.06, 0.12, 0.09, 0.03, 0.15, 0.07, 0.11, 0.05, 0.13,
                                    0.02, 0.08, 0.14, 0.04, 0.10, 0.06, 0.12, 0.03, 0.09, 0.01]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { idx, h in
                Capsule()
                    .fill(SpanColor.accent)
                    .frame(width: 3, height: h)
                    .scaleEffect(x: 1, y: scaleY(idx), anchor: .center)
                    .opacity(active ? 1 : 0.4)
                    .animation(
                        (active && !reduceMotion)
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delays[idx])
                        : .default,
                        value: animate
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }

    private func scaleY(_ idx: Int) -> CGFloat {
        guard active, !reduceMotion else { return 0.55 }
        return animate ? 1.0 : 0.18
    }
}

#Preview {
    AskSpanView()
}
