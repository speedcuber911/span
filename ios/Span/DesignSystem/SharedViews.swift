//
//  SharedViews.swift
//  Span — small shared UI building blocks used across screens.
//

import SwiftUI

// MARK: - Persistent disclaimer footer (appended in code on every content screen)

struct DisclaimerFooter: View {
    var text: String = "Educational only · discuss any result with your clinician."

    var body: some View {
        Text(text)
            .spanDisclaimerStyle()
            .padding(.vertical, SpanSpacing.lg)
            .padding(.horizontal, SpanSpacing.md)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Primary button

struct SpanPrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SpanFont.body.weight(.semibold))
            .foregroundStyle(SpanColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: SpanSpacing.touchTarget)
            .background(
                (enabled ? SpanColor.primary : SpanColor.outlineVariant),
                in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension View {
    func spanPrimaryButton(enabled: Bool = true) -> some View {
        buttonStyle(SpanPrimaryButtonStyle(enabled: enabled)).disabled(!enabled)
    }
}

// MARK: - Section header row

struct SectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).spanSectionHeaderStyle()
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Loading skeleton

struct SkeletonBlock: View {
    var height: CGFloat = 80
    var body: some View {
        RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
            .fill(SpanColor.surfaceHigh)
            .frame(height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

// MARK: - Inline error with retry

struct LoadFailureView: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: SpanSpacing.gutter) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(SpanColor.textTertiary)
            Text(message)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .spanPrimaryButton()
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(SpanSpacing.xl)
    }
}

// MARK: - Natural-frequency icon grid (10×10 "X of 100 people")

/// A 10×10 grid of person glyphs; `count` of them filled to convey a natural
/// frequency — never a bare percentage (Gigerenzer; DESIGN_SYSTEM.md).
struct NaturalFrequencyGrid: View {
    let count: Int
    var denom: Int = 100
    var tint: Color = SpanColor.statusRed

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<denom, id: \.self) { idx in
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(idx < count ? tint : SpanColor.surfaceHighest)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count) out of \(denom) people highlighted")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            SectionHeader("Readings")
            SkeletonBlock()
            NaturalFrequencyGrid(count: 23)
            Button("Continue") {}.spanPrimaryButton()
            DisclaimerFooter()
        }
        .padding()
    }
    .background(SpanColor.background)
}
