//
//  CitationChip.swift
//  Span — the `.cc` citation chip ("Tier 1 · ADA 2024 ↗").
//
//  Muted surface chip (surfaceCard fill, b2 hairline, t2 text) with a leading
//  external-link icon. Tier 3 / contested sources carry a warning glyph and amber
//  text. Tapping presents the Citation Detail sheet (Screen 18).
//

import SwiftUI

struct CitationChip: View {
    let source: Source
    /// Tapping opens the citation sheet for this source.
    var onTap: (Source) -> Void = { _ in }

    private var isContested: Bool { source.tier == .tier3 }

    var body: some View {
        Button {
            onTap(source)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isContested ? "exclamationmark.triangle.fill" : "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(chipText)
                    .font(SpanFont.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isContested ? SpanColor.statusYellow : SpanColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(SpanColor.borderStrong, lineWidth: SpanSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.tier.label) source: \(source.title). Opens source details.")
    }

    private var chipText: String {
        let qualifier = isContested ? " · contested" : ""
        return "\(source.tier.label)\(qualifier) · \(source.title)"
    }
}

/// Chip with custom inline label text (e.g. a free-text source tag).
struct PlainTagChip: View {
    let text: String
    var systemImage: String? = "arrow.up.right"

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(SpanFont.caption).lineLimit(1)
        }
        .foregroundStyle(SpanColor.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SpanColor.borderStrong, lineWidth: SpanSpacing.hairline)
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        CitationChip(source: MockSpanAPI.adaSource)
        CitationChip(source: MockSpanAPI.attiaSource)
        PlainTagChip(text: "Tier 2 · Optimal")
    }
    .padding(40)
    .background(SpanColor.background)
}
