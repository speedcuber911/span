//
//  CheckInView.swift
//  Span — Screen 13. Check-In (daily QoL).
//
//  WHO-5 card stack: one prompt per card with a 6-point response set; advances on
//  tap; shows a well-being result band on completion. Framed as a picture of how
//  you've been feeling, never a diagnosis. (Gated behind a feature flag in prod
//  pending WHO-5 commercial licensing — see SCREENS.md §13.)
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
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                if completed {
                    resultCard
                } else if let instrument, index < instrument.items.count {
                    questionCard(instrument, item: instrument.items[index])
                } else {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 100) }
                }
                DisclaimerFooter()
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if instrument == nil { instrument = try? await env.api.checkinNext() }
        }
    }

    private func questionCard(_ instrument: CheckinInstrument, item: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            HStack {
                Text("\(index + 1) of \(instrument.items.count)")
                    .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                Spacer()
                ProgressView(value: Double(index + 1), total: Double(instrument.items.count))
                    .frame(width: 120).tint(SpanColor.primary)
            }
            Text(item.prompt)
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            VStack(spacing: SpanSpacing.xs) {
                ForEach(Array(item.scaleLabels.enumerated()), id: \.offset) { offset, label in
                    let value = item.scaleMax - offset
                    Button {
                        advance(with: value, total: instrument.items.count)
                    } label: {
                        HStack {
                            Text(label).font(SpanFont.body).foregroundStyle(SpanColor.textPrimary)
                            Spacer()
                            Text("\(value)").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                        }
                        .padding(SpanSpacing.gutter)
                        .frame(maxWidth: .infinity)
                        .background(SpanColor.surfaceLow, in: RoundedRectangle(cornerRadius: SpanRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .spanCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Check-in complete")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            Text("Your well-being today")
                .font(SpanFont.headline)
                .foregroundStyle(SpanColor.textSecondary)
            let score = computedScore
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(score)").font(SpanFont.displayLarge).foregroundStyle(SpanColor.textPrimary)
                Text("/ 100").font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpanColor.surfaceHigh)
                    Capsule().fill(score > 50 ? SpanColor.statusGreen : SpanColor.statusYellow)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }.frame(height: 6)
            Text("This is a general picture of how you have been feeling, based on your responses. It is not a diagnosis.")
                .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
        }
        .spanCard()
    }

    private var computedScore: Int {
        // WHO-5 raw sum × 4 → 0..100. (Backend computes for real; this is local
        // preview math only since the mock check-in is not POSTed.)
        guard !responses.isEmpty else { return 56 }
        let raw = responses.reduce(0, +)
        let maxRaw = responses.count * 5
        return Int(Double(raw) / Double(max(maxRaw, 1)) * 100)
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

#Preview {
    NavigationStack { CheckInView() }
        .environment(AppEnvironment.preview)
}
