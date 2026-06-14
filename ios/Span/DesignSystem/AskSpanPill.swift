//
//  AskSpanPill.swift
//  Span — the floating "Ask Span" entry (#ask in the comp).
//
//  A purple, blurred, bordered pill that sits bottom-right above the tab bar on the
//  Today and Systems tabs. Mic glyph + "Ask Span". Tapping launches the voice
//  consultant. Matches the comp: accentBg fill, accentBorder hairline, blur(8px),
//  height 36, purple text.
//

import SwiftUI

struct AskSpanPill: View {
    var title: String = "Ask Span"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(SpanColor.accent)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .background(SpanColor.accentBg, in: Capsule())
            .overlay(Capsule().strokeBorder(SpanColor.accentBorder, lineWidth: SpanSpacing.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Span")
        .accessibilityHint("Opens the voice consultant")
    }
}

/// A wider full-width labelled variant used inline on System Detail screens.
struct AskSpanInlineButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpanSpacing.xs) {
                Image(systemName: "mic.fill")
                Text(title)
                    .font(SpanFont.body.weight(.semibold))
            }
            .foregroundStyle(SpanColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SpanColor.accentBg, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .strokeBorder(SpanColor.accentBorder, lineWidth: SpanSpacing.hairline)
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
