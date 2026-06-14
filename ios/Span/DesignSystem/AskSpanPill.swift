//
//  AskSpanPill.swift
//  Span — the floating "Ask Span" entry. A circular blurred FAB (Material) that
//  sits above the tab bar on the Today and Systems tabs, on a plane above content.
//  Tapping launches the voice consultant as a full-screen cover.
//

import SwiftUI

struct AskSpanPill: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SpanColor.onPrimary)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(SpanColor.primaryBright)
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(Circle().stroke(SpanColor.onPrimary.opacity(0.15), lineWidth: 1))
                .shadow(color: SpanColor.primary.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Span")
        .accessibilityHint("Opens the voice consultant")
    }
}

/// A wider labelled variant ("🎙 Ask Span about my Metabolic health") used inline
/// on System Detail screens.
struct AskSpanInlineButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpanSpacing.xs) {
                Image(systemName: "mic.fill")
                Text(title)
                    .font(SpanFont.body.weight(.medium))
            }
            .foregroundStyle(SpanColor.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SpanColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .stroke(SpanColor.primary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        SpanColor.background.ignoresSafeArea()
        VStack { AskSpanInlineButton(title: "Ask Span about my Metabolic health") {} }.padding()
        AskSpanPill {}.padding(24)
    }
}
