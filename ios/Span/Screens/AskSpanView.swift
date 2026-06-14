//
//  AskSpanView.swift
//  Span — Screen 16. Span-Consultant (voice).
//
//  Faithful to ask-span.png. Presented as a full-screen cover. Flow:
//   • AI disclosure gate (shown every session, cannot be skipped)
//   • active session: "AI generated guidance. Not medical advice" pill, live
//     caption bubbles, agent-state indicator, push-to-talk button, switch-to-text
//   Text-mode fallback is the accessibility backstop. No audio is recorded.
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
            .background(SpanColor.background)
            .navigationTitle("Span Consultant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(model.disclosureAccepted ? "End session" : "Close")
                }
            }
        }
    }

    // MARK: Disclosure gate

    private var disclosureGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                Label("AI Disclosure", systemImage: "cpu")
                    .font(SpanFont.headline)
                    .foregroundStyle(SpanColor.textPrimary)
                Text("Span-Consultant is an AI assistant. It is not a doctor and does not give medical advice.")
                    .font(SpanFont.body).foregroundStyle(SpanColor.textPrimary)
                Text("It can only discuss information already in your Span records. It will always ask you to discuss findings with a clinician.")
                    .font(SpanFont.callout).foregroundStyle(SpanColor.textSecondary)
                Text("This session's transcript will be stored in India and linked to your account. Audio is not recorded.")
                    .font(SpanFont.callout).foregroundStyle(SpanColor.textSecondary)
                Text("This is a standalone consent. You may revoke it in Settings.")
                    .font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)

                Button("I understand — start session") { model.acceptDisclosure() }
                    .spanPrimaryButton()
                    .padding(.top, SpanSpacing.xs)
                Button("Not now") { dismiss() }
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(SpanSpacing.md)
            .spanCard()
            .padding(SpanSpacing.md)
        }
    }

    // MARK: Session

    private var sessionView: some View {
        VStack(spacing: 0) {
            // AI pill
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("AI generated guidance. Not medical advice.")
            }
            .font(SpanFont.caption2)
            .foregroundStyle(SpanColor.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(SpanColor.surfaceLow, in: Capsule())
            .padding(.vertical, SpanSpacing.gutter)

            // Caption / chat transcript
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
                    Text("Span Consultant")
                        .font(SpanFont.caption2)
                        .foregroundStyle(SpanColor.textTertiary)
                    ForEach(model.turns) { turn in
                        CaptionBubble(turn: turn)
                    }
                    if model.agentState == .thinking {
                        Text("Span: thinking…").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SpanSpacing.md)
            }

            Spacer(minLength: 0)

            // Agent state + controls
            VStack(spacing: SpanSpacing.gutter) {
                agentStateIndicator
                if model.textMode {
                    textInputBar
                } else {
                    pushToTalk
                    Button {
                        model.textMode = true
                    } label: {
                        Label("Switch to Text", systemImage: "keyboard")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textSecondary)
                    }
                }
            }
            .padding(SpanSpacing.md)
            .background(SpanColor.surface)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var agentStateIndicator: some View {
        HStack(spacing: 8) {
            Text(model.agentState == .listening ? "LISTENING" : "READY")
                .font(SpanFont.caption2.weight(.semibold))
                .foregroundStyle(SpanColor.primary)
            // simple equalizer glyph
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(SpanColor.primary)
                        .frame(width: 3, height: [10, 16, 8, 14][i])
                }
            }
        }
        .accessibilityLabel("Agent state: \(model.agentState.rawValue)")
    }

    private var pushToTalk: some View {
        Button {} label: {
            Label("Hold to Speak", systemImage: "mic.fill")
        }
        .spanPrimaryButton()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.agentState = .listening }
                .onEnded { _ in model.agentState = .thinking }
        )
    }

    private var textInputBar: some View {
        HStack {
            Text("Type your question…")
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.small))
            Button("Send") {}
                .font(SpanFont.callout.weight(.semibold))
                .foregroundStyle(SpanColor.primary)
        }
    }
}

private struct CaptionBubble: View {
    let turn: VoiceTurn

    var body: some View {
        Text(turn.text)
            .font(SpanFont.callout)
            .foregroundStyle(SpanColor.textPrimary)
            .padding(SpanSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                turn.speaker == .span ? SpanColor.surfaceLow : SpanColor.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
            )
            .accessibilityLabel("\(turn.speaker == .span ? "Span" : "You"): \(turn.text)")
    }
}

#Preview {
    AskSpanView()
}
