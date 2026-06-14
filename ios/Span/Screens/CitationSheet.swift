//
//  CitationSheet.swift
//  Span — Screen 18. The Citation Detail modal every citation chip leads to.
//
//  Dark "Health Intelligence" revamp, faithful to span_screens_v2 screen 18:
//   • a dark bottom sheet with a grabber, "Source" title and an × close
//   • a tier badge pill (glowing dot + uppercase label), colored by tier — Tier 1
//     consensus = green, Tier 2 research = purple, Tier 3 contested = amber
//   • the full title + bibliographic line
//   • "This source supports:" → the claim in a raised card
//   • the conflict-of-interest disclosure (Tier 3 contested framing, preserved)
//   • an "Open source" primary button (when a URL is present)
//   • the "Evidence tiers" reference at the bottom.
//

import SwiftUI

struct CitationSheet: View {
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var isContested: Bool { source.tier == .tier3 }

    var body: some View {
        ZStack {
            SpanColor.surfaceCard.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: SpanSpacing.md) {
                        tierBadge

                        Text(source.title)
                            .font(.system(size: 19, weight: .bold))
                            .kerning(-0.4)
                            .foregroundStyle(SpanColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(source.citationText)
                            .font(SpanFont.callout)
                            .foregroundStyle(SpanColor.textSecondary)

                        if isContested, let conflict = source.conflictDisclosure {
                            conflictBlock(conflict)
                        }

                        if let claim = source.claimSupported {
                            claimBlock(claim)
                        }

                        if let urlString = source.url, let url = URL(string: urlString) {
                            Button {
                                openURL(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Open source")
                                }
                            }
                            .spanPrimaryButton()
                        }

                        evidenceTiers
                    }
                    .padding(.horizontal, SpanSpacing.screenH)
                    .padding(.bottom, SpanSpacing.lg)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(SpanColor.surfaceCard)
        .preferredColorScheme(.dark)
    }

    // MARK: Header (grabber + title + ×)

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(SpanColor.borderStrong)
                .frame(width: 34, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 7)

            HStack {
                Text("Source")
                    .font(.system(size: 19, weight: .bold))
                    .kerning(-0.4)
                    .foregroundStyle(SpanColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SpanColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.bottom, SpanSpacing.md)
        }
    }

    // MARK: Tier badge (glowing dot + uppercase label)

    private var tierBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tierColor)
                .frame(width: 6, height: 6)
                .spanGlow(tierColor, radius: 5, opacity: 0.5)
            Text(source.tier.longLabel)
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.9)
                .textCase(.uppercase)
        }
        .foregroundStyle(tierColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(tierBg, in: RoundedRectangle(cornerRadius: SpanRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.badge, style: .continuous)
                .strokeBorder(tierBorder, lineWidth: SpanSpacing.hairline)
        )
    }

    private var tierColor: Color {
        switch source.tier {
        case .tier1: return SpanColor.statusGreen
        case .tier2: return SpanColor.accent
        case .tier3: return SpanColor.statusYellow
        }
    }
    private var tierBg: Color {
        switch source.tier {
        case .tier1: return SpanColor.statusGreenBg
        case .tier2: return SpanColor.accentBg
        case .tier3: return SpanColor.statusYellowBg
        }
    }
    private var tierBorder: Color {
        switch source.tier {
        case .tier1: return SpanColor.statusGreenBorder
        case .tier2: return SpanColor.accentBorder
        case .tier3: return SpanColor.statusYellowBorder
        }
    }

    // MARK: Claim card

    private func claimBlock(_ claim: String) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("This source supports:")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(1)
                .textCase(.uppercase)
                .foregroundStyle(SpanColor.textTertiary)
            Text(claim)
                .font(.system(size: 14))
                .foregroundStyle(SpanColor.textPrimary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpanSpacing.md)
                .background(SpanColor.surfaceRaised, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                        .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
                )
        }
    }

    // MARK: Conflict / contested block

    private func conflictBlock(_ conflict: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Contested · relevant conflict of interest", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpanColor.statusYellow)
            Text(conflict)
                .font(.system(size: 12.5))
                .foregroundStyle(SpanColor.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpanSpacing.gutter)
        .background(SpanColor.statusYellowBg, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                .strokeBorder(SpanColor.statusYellowBorder, lineWidth: SpanSpacing.hairline)
        )
    }

    // MARK: Evidence tier reference

    private var evidenceTiers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Evidence tiers")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(SpanColor.textSecondary)
                .padding(.bottom, SpanSpacing.xs)
            ForEach(tierRows, id: \.0) { row in
                HStack(alignment: .top, spacing: SpanSpacing.gutter) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SpanColor.textSecondary)
                        .frame(width: 46, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11))
                        .foregroundStyle(SpanColor.textTertiary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.top, SpanSpacing.md)
        .overlay(alignment: .top) {
            Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
        }
    }

    private var tierRows: [(String, String)] {
        [("Tier 1", "Consensus guidelines — WHO, ADA, ACC/AHA"),
         ("Tier 2", "Peer-reviewed research with human outcomes"),
         ("Tier 3", "Expert opinion / contested / no RCT")]
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
    .preferredColorScheme(.dark)
}

#Preview("Contested") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CitationSheet(source: MockSpanAPI.nmnSource)
    }
    .preferredColorScheme(.dark)
}
