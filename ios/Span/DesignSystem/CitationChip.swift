//
//  CitationChip.swift
//  Span — small caption-2 chip under any claim ("Tier 1 · ADA 2024 ↗").
//  Tapping presents the Citation Detail sheet (Screen 18).
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
            HStack(spacing: 6) {
                if isContested {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                }
                Text(chipText)
                    .font(SpanFont.caption2)
                    .lineLimit(1)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isContested ? SpanColor.statusYellow.opacity(0.95) : SpanColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SpanColor.surfaceLow, in: Capsule())
            .overlay(Capsule().stroke(SpanColor.outlineVariant.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.tier.label) source: \(source.title). Opens source details.")
    }

    private var chipText: String {
        let qualifier = isContested ? " · expert opinion" : ""
        return "\(source.tier.label)\(qualifier) · \(source.title)"
    }
}

/// Chip with custom inline label text (e.g. "Peter Attia · Four Horsemen").
struct PlainTagChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10))
            }
            Text(text).font(SpanFont.caption2)
        }
        .foregroundStyle(SpanColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(SpanColor.surfaceLow, in: Capsule())
        .overlay(Capsule().stroke(SpanColor.outlineVariant.opacity(0.6), lineWidth: 1))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        CitationChip(source: MockSpanAPI.adaSource)
        CitationChip(source: MockSpanAPI.attiaSource)
        PlainTagChip(text: "Peter Attia · Four Horsemen", systemImage: "books.vertical")
    }
    .padding()
    .background(SpanColor.background)
}
