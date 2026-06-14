//
//  CitationSheet.swift
//  Span — Screen 18. The Citation Detail modal every citation chip leads to.
//
//  Shows the full tiered source metadata: tier, title, body, the claim it
//  supports, an external link, and (for Tier 3) the conflict disclosure + a
//  contested warning. Presented as a .sheet.
//

import SwiftUI

struct CitationSheet: View {
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var isContested: Bool { source.tier == .tier3 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    // Tier banner
                    HStack(spacing: 6) {
                        if isContested {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SpanColor.statusYellow)
                        }
                        Text(source.tier.longLabel)
                            .font(SpanFont.footnote.weight(.semibold))
                            .foregroundStyle(isContested ? SpanColor.statusYellow : SpanColor.textSecondary)
                    }

                    Text(source.title)
                        .font(SpanFont.title2)
                        .foregroundStyle(SpanColor.textPrimary)

                    Text(source.citationText)
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)

                    if let conflict = source.conflictDisclosure {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relevant conflict of interest")
                                .font(SpanFont.footnote.weight(.semibold))
                                .foregroundStyle(SpanColor.onErrorContainer)
                            Text(conflict)
                                .font(SpanFont.footnote)
                                .foregroundStyle(SpanColor.textPrimary)
                        }
                        .padding(SpanSpacing.gutter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SpanColor.errorContainer, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
                    }

                    if let claim = source.claimSupported {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This source supports:")
                                .font(SpanFont.footnote.weight(.semibold))
                                .foregroundStyle(SpanColor.textSecondary)
                            Text(claim)
                                .font(SpanFont.body)
                                .foregroundStyle(SpanColor.textPrimary)
                        }
                    }

                    if let urlString = source.url, let url = URL(string: urlString) {
                        Button {
                            openURL(url)
                        } label: {
                            HStack {
                                Text("Open source")
                                Image(systemName: "arrow.up.forward.square")
                            }
                        }
                        .spanPrimaryButton()
                    }

                    Divider().padding(.vertical, SpanSpacing.xs)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidence tiers")
                            .font(SpanFont.footnote.weight(.semibold))
                            .foregroundStyle(SpanColor.textSecondary)
                        Text("Tier 1 = consensus guidelines\nTier 2 = peer-reviewed research\nTier 3 = expert opinion / contested")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                }
                .padding(SpanSpacing.md)
            }
            .background(SpanColor.background)
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Modifier helper: present a citation sheet bound to an optional Source.
extension View {
    func citationSheet(_ source: Binding<Source?>) -> some View {
        sheet(item: source) { CitationSheet(source: $0) }
    }
}

#Preview("Tier 1") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CitationSheet(source: MockSpanAPI.adaSource)
    }
}

#Preview("Contested") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CitationSheet(source: MockSpanAPI.nmnSource)
    }
}
