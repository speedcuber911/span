//
//  TodayView.swift
//  Span — Screen 7. Whole-person overview (home tab).
//
//  Faithful to today.png: a top "Span Health" bar, the "How you're feeling"
//  PROMIS Physical/Mental cards (value / 100 + progress bar + band label), the
//  light-red attention rail, the 8 organ-system tiles, a collapsed biological-age
//  link, and the persistent disclaimer footer. NO single composite score.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: [Route]
    @State private var model: OverviewModel?
    @State private var citation: Source?

    private let columns = [GridItem(.flexible(), spacing: SpanSpacing.gutter),
                           GridItem(.flexible(), spacing: SpanSpacing.gutter)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    loadingSkeleton
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let overview):
                    content(overview)
                }

                DisclaimerFooter()
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(SpanColor.textSecondary)
            }
        }
        .citationSheet($citation)
        .task {
            if model == nil { model = OverviewModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    // MARK: Loaded content

    @ViewBuilder
    private func content(_ overview: OverviewDTO) -> some View {
        // Greeting
        HStack {
            Text(greeting(overview.greetingName))
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            Spacer()
            Text(overview.asOf, format: .dateTime.day().month().year())
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
        }

        // PROMIS bands — only when a check-in exists.
        if let promis = overview.promis {
            promisSection(promis)
        } else {
            startCheckinCard
        }

        // Attention rail — omitted entirely when there is nothing out of range.
        AttentionRail(items: overview.attention) { item in
            path.append(.parameterDetail(parameterID: item.canonicalParamId))
        }

        // Organ-system tiles
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SectionHeader("System Overview")
            LazyVGrid(columns: columns, spacing: SpanSpacing.gutter) {
                ForEach(overview.systems) { rollup in
                    Button {
                        path.append(.systemDetail(rollup.key))
                    } label: {
                        OrganSystemTile(rollup: rollup)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Collapsed biological-age link (only if available, never above the fold).
        if overview.bioageAvailable {
            Button {
                path.append(.bioAge)
            } label: {
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundStyle(SpanColor.textSecondary)
                    Text("Your biological age trend (optional)")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpanColor.textTertiary)
                }
                .spanCard()
            }
            .buttonStyle(.plain)
        }
    }

    private func promisSection(_ promis: PromisDTO) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("How you're feeling")
                .font(SpanFont.headline)
                .foregroundStyle(SpanColor.textPrimary)
            HStack(spacing: SpanSpacing.gutter) {
                PromisGauge(title: "Physical", score: promis.gphTScore, band: promis.gphBand)
                PromisGauge(title: "Mental", score: promis.gmhTScore, band: promis.gmhBand)
            }
            HStack {
                PlainTagChip(text: "PROMIS Global-10")
                Spacer()
                Button("Update") { path.append(.checkin) }
                    .font(SpanFont.footnote.weight(.medium))
                    .foregroundStyle(SpanColor.primary)
            }
            Text("Compared with the general population (50 = average). Based on your check-in on \(promis.basedOnDate.formatted(.dateTime.day().month().year())).")
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textTertiary)
        }
    }

    private var startCheckinCard: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("How are you feeling overall?")
                .font(SpanFont.headline)
                .foregroundStyle(SpanColor.textPrimary)
            Text("A 2-minute check-in gives you a whole-person health picture.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
            Button("Start check-in") { path.append(.checkin) }
                .spanPrimaryButton()
                .padding(.top, SpanSpacing.xs)
        }
        .spanCard()
    }

    private var loadingSkeleton: some View {
        VStack(spacing: SpanSpacing.gutter) {
            SkeletonBlock(height: 90)
            SkeletonBlock(height: 70)
            LazyVGrid(columns: columns, spacing: SpanSpacing.gutter) {
                ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 120) }
            }
        }
    }

    private func greeting(_ name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return "\(part), \(name)"
    }
}

/// A PROMIS band gauge: value / 100 + progress bar tinted by band + label.
struct PromisGauge: View {
    let title: String
    let score: Double
    let band: String

    private var tint: Color {
        switch score {
        case ..<40: return SpanColor.statusRed
        case 40..<45: return SpanColor.statusYellow
        case 45..<55: return SpanColor.statusYellow
        default: return SpanColor.statusGreen
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text(title.uppercased())
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
                .kerning(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score.formatted(.number.precision(.fractionLength(0))))
                    .font(SpanFont.displayLarge)
                    .foregroundStyle(SpanColor.textPrimary)
                Text("/ 100")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpanColor.surfaceHigh)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(max(score, 0), 100) / 100))
                }
            }
            .frame(height: 6)
            Text(band)
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) health \(Int(score)) of 100, \(band)")
    }
}

#Preview {
    NavigationStack {
        TodayView(path: .constant([]))
    }
    .environment(AppEnvironment.preview)
}
