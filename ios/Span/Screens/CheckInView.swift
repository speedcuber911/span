//
//  CheckInView.swift
//  Span — Screen 13. Check-In (WHO-5 wellbeing).
//
//  Dark "Health Intelligence" revamp, faithful to span_screens_v2.html screen 13.
//   • A purple-accented prompt card ("WHO-5 Wellbeing Index" eyebrow + italic item).
//   • The `.who5g` 3-column grid of `.wo` cells: a big number (0–5) over a wrapped
//     label; the selected cell turns purple.
//   • A thin progress bar + "N of 5 · takes about 2 minutes".
//   • On completion: a 0–100 wellbeing readout with a tinted bar and a SOFT nudge
//     for low scores ("a good moment to discuss how you've been feeling" — never the
//     word "depression"). Always framed as a picture, never a diagnosis.
//
//  Consumes the same CheckinInstrument / CheckinItem DTOs unchanged.
//

import SwiftUI

struct CheckInView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var instrument: CheckinInstrument?
    @State private var index = 0
    @State private var responses: [Int] = []
    @State private var completed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                if completed {
                    resultCard
                } else if let instrument, index < instrument.items.count {
                    questionCard(instrument, item: instrument.items[index])
                } else {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 100) }
                }
                DisclaimerFooter()
                    .padding(.horizontal, -SpanSpacing.screenH)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
        }
        .background(SpanColor.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            if let instrument, !completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(index + 1) of \(instrument.items.count)")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
        }
        .task {
            if instrument == nil { instrument = try? await env.api.checkinNext() }
        }
    }

    // MARK: Question (WHO-5 grid)

    private func questionCard(_ instrument: CheckinInstrument, item: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            // Purple-accented prompt card.
            VStack(alignment: .leading, spacing: 6) {
                Text(instrument.instrumentName == "WHO-5"
                     ? "WHO-5 Wellbeing Index" : instrument.instrumentName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SpanColor.accent)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text("“\(item.prompt)”")
                    .font(.system(size: 14).italic())
                    .foregroundStyle(SpanColor.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SpanSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(SpanColor.accent).frame(width: 2.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
                    .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous))

            // .who5g — 3-column grid of .wo cells, high→low.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                      spacing: 7) {
                ForEach(Array(item.scaleLabels.enumerated()), id: \.offset) { offset, label in
                    let value = item.scaleMax - offset
                    WHO5Cell(value: value, label: label) {
                        advance(with: value, total: instrument.items.count)
                    }
                }
            }
            .padding(.top, 2)

            // Progress.
            VStack(spacing: 7) {
                CheckinProgressBar(fraction: Double(index + 1) / Double(instrument.items.count))
                Text("\(index + 1) of \(instrument.items.count) · takes about 2 minutes")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, SpanSpacing.xs)
        }
    }

    // MARK: Result

    private var resultCard: some View {
        let score = computedScore
        let low = score <= 50
        return VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Your wellbeing today")
                .spanSectionHeaderStyle()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(score)")
                    .font(SpanFont.mono(56, weight: .heavy))
                    .foregroundStyle(low ? SpanColor.statusYellow : SpanColor.statusGreen)
                    .kerning(-2)
                Text("/ 100")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpanColor.surfaceRaised)
                    Capsule().fill(low ? SpanColor.statusYellow : SpanColor.statusGreen)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)

            // Soft nudge for low scores — never "depression"; always "discuss".
            if low {
                HStack(alignment: .top, spacing: SpanSpacing.xs) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 15))
                        .foregroundStyle(SpanColor.accent)
                    Text("Your responses suggest this might be a good moment to discuss how you’ve been feeling with someone you trust or your clinician.")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                        .lineSpacing(2)
                }
                .padding(SpanSpacing.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SpanColor.accentBg, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
                        .strokeBorder(SpanColor.accentBorder, lineWidth: SpanSpacing.hairline)
                )
            }

            Text("This is a general picture of how you’ve been feeling, based on your responses. It is not a diagnosis.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
                .lineSpacing(2)

            Button("Done") { } .spanPrimaryButton()
                .padding(.top, SpanSpacing.xs)
        }
        .spanCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your wellbeing today is \(score) of 100")
    }

    // MARK: Scoring

    /// WHO-5 raw sum × 4 → 0..100. (Backend computes for real; this is local preview
    /// math only since the mock check-in is not POSTed.)
    private var computedScore: Int {
        guard !responses.isEmpty else { return 56 }
        let raw = responses.reduce(0, +)
        // WHO-5 items are 0..5; raw 0..25 → ×4. Generalize to any item count/scale.
        let maxRaw = responses.count * 5
        return Int((Double(raw) / Double(max(maxRaw, 1))) * 100)
    }

    private func advance(with value: Int, total: Int) {
        responses.append(value)
        if index + 1 >= total {
            withAnimation { completed = true }
        } else {
            withAnimation { index += 1 }
        }
    }
}

// MARK: - .wo cell

/// One WHO-5 response cell: big number over a wrapped label. Selected = purple.
private struct WHO5Cell: View {
    let value: Int
    let label: String
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
        } label: {
            VStack(spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(pressed ? SpanColor.accent : SpanColor.textPrimary)
                    .kerning(-0.5)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(pressed ? SpanColor.accent : SpanColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 5)
            .padding(.vertical, 11)
            .background(pressed ? SpanColor.accentBg : SpanColor.surfaceCard,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(pressed ? SpanColor.accentBorder : SpanColor.border,
                                  lineWidth: SpanSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value), \(label)")
    }
}

/// A 3px check-in progress bar (the comp's `.pbar` + purple `.pbf`).
private struct CheckinProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SpanColor.border)
                Capsule().fill(SpanColor.accent)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { CheckInView() }
        .environment(AppEnvironment.preview)
}
