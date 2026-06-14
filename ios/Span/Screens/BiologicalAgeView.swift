//
//  BiologicalAgeView.swift
//  Span — Screen 15. Biological Age (opt-in, secondary).
//
//  Dark "Health Intelligence" revamp, faithful to v2-bioage.jpeg:
//   • nav bar "‹ Biological age"
//   • an "About this estimate" caveat card (PhenoAge · Levine 2018 · NHANES ·
//     directional only · not validated for Indian populations)
//   • a big GLOWING ring with the bio-age number ("BIOLOGICAL / NN / years") and a
//     "−X years vs chronological age of Y" delta beside it. The ring is GREEN when
//     younger than chronological, AMBER/RED when older (driven by delta sign).
//   • a "trend over time" chart with the chronological-age dashed reference
//   • the "9 required markers — all present" checklist with green checks + mono values
//   • plus "What this is not" and the no-imputation not-computable state.
//
//  Consumes the SAME BioAgeResult / BioAgeModel — only the presentation changed.
//

import SwiftUI
import Charts

struct BiologicalAgeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: BioAgeModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    VStack(spacing: SpanSpacing.gutter) {
                        SkeletonBlock(height: 90)
                        SkeletonBlock(height: 180)
                        SkeletonBlock(height: 200)
                    }
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let result):
                    if result.computable {
                        computableContent(result)
                    } else {
                        notComputableContent(result)
                    }
                }
                DisclaimerFooter()
                    .padding(.top, SpanSpacing.xs)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.gutter)
        }
        .background(SpanColor.background)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            SpanNavBar(title: "Biological age", onBack: { dismiss() })
        }
        .citationSheet($citation)
        .task {
            if model == nil { model = BioAgeModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    /// Ring color is driven by the delta sign: younger = green, older = amber/red.
    private func ringColor(_ result: BioAgeResult) -> Color {
        guard let delta = result.deltaYears else { return SpanColor.statusGreen }
        if delta <= -0.5 { return SpanColor.statusGreen }
        if delta < 1.5 { return SpanColor.statusYellow }
        return SpanColor.statusRed
    }

    // MARK: Computable

    @ViewBuilder
    private func computableContent(_ result: BioAgeResult) -> some View {
        aboutCard(result)
        ringSection(result)
        if result.trend.count >= 2 { trendCard(result) }
        markersChecklist(result)
        whatThisIsNot
    }

    // MARK: About this estimate

    private func aboutCard(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("About this estimate")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpanColor.textPrimary)
            Text("PhenoAge algorithm (Levine 2018, NHANES calibration) using 9 blood markers. Directional only. Not validated for Indian populations.")
                .font(.system(size: 12.5))
                .foregroundStyle(SpanColor.textSecondary)
                .lineSpacing(2)
            if let source = result.source {
                CitationChip(source: source) { citation = $0 }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    // MARK: Ring + delta

    private func ringSection(_ result: BioAgeResult) -> some View {
        let color = ringColor(result)
        return HStack(spacing: SpanSpacing.lg) {
            BioAgeRing(value: result.valueYears, chrono: result.chronoAge, color: color)
                .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 4) {
                if let delta = result.deltaYears {
                    Text(deltaLabel(delta))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(chronoCaption(result))
                    .font(.system(size: 11))
                    .foregroundStyle(SpanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, SpanSpacing.xs)
    }

    private func deltaLabel(_ delta: Double) -> String {
        let rounded = delta.rounded()
        let years = abs(Int(rounded)) == 1 ? "year" : "years"
        if rounded < 0 { return "\(Int(rounded)) \(years)" }       // e.g. "−3 years"
        if rounded > 0 { return "+\(Int(rounded)) \(years)" }
        return "Same as chronological"
    }

    private func chronoCaption(_ result: BioAgeResult) -> String {
        if let chrono = result.chronoAge {
            return "vs chronological\nage of \(Int(chrono.rounded()))"
        }
        return "vs your chronological age"
    }

    // MARK: Trend over time

    private func trendCard(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SpanSectionLabel("Trend over time")

            Chart {
                // chronological-age reference (dashed)
                ForEach(result.trend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Chrono", point.chronoAge),
                        series: .value("Series", "Chronological")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(SpanColor.textPrimary.opacity(0.10))
                }

                // bio-age area fill + line
                ForEach(result.trend) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Floor", trendDomain.lowerBound),
                        yEnd: .value("Bio age", point.valueYears)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [SpanColor.statusGreen.opacity(0.28), SpanColor.statusGreen.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(result.trend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Bio age", point.valueYears),
                        series: .value("Series", "Biological")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .foregroundStyle(SpanColor.statusGreen)
                    .interpolationMethod(.catmullRom)
                }
                ForEach(result.trend) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Bio age", point.valueYears)
                    )
                    .symbolSize(40)
                    .foregroundStyle(SpanColor.statusGreen)
                }
            }
            .chartYScale(domain: trendDomain)
            .frame(height: 96)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.system(size: 7.5))
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)

            if let caption = result.confidenceCaption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    private var trendDomain: ClosedRange<Double> {
        guard let model, case .loaded(let result) = model.state else { return 0...100 }
        let bio = result.trend.map(\.valueYears)
        let chrono = result.trend.map(\.chronoAge)
        let all = bio + chrono
        let lo = (all.min() ?? 0) - 2
        let hi = (all.max() ?? 1) + 2
        return lo...hi
    }

    // MARK: 9 required markers

    private func markersChecklist(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SpanSectionLabel("\(result.inputsUsed.count) required markers — all present")
                .padding(.bottom, SpanSpacing.xs)
            ForEach(result.inputsUsed) { input in
                HStack(spacing: SpanSpacing.xs) {
                    Image(systemName: input.found ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(input.found ? SpanColor.statusGreen : SpanColor.statusRed)
                    Text(input.parameter)
                        .font(.system(size: 13))
                        .foregroundStyle(SpanColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let value = input.value {
                        Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(input.unit ?? "")")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(SpanColor.textSecondary)
                    }
                }
                .padding(.vertical, 9)
                .spanBottomHairline()
            }
        }
    }

    // MARK: What this is not

    private var whatThisIsNot: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("What this is not")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SpanColor.textPrimary)
            ForEach(["Not a diagnosis",
                     "Not a prediction of lifespan",
                     "Not comparable between different people or methods",
                     "Not a reason to change any medication or supplement"], id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Text("·").foregroundStyle(SpanColor.textTertiary)
                    Text(line)
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    // MARK: Not computable (no imputation — hard rule)

    private func notComputableContent(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Biological age is not yet computable for you.")
                    .font(SpanFont.title3)
                    .foregroundStyle(SpanColor.textPrimary)
                Text("All \(result.inputsUsed.count) markers must be present — Span never imputes missing inputs.")
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(result.inputsUsed) { input in
                    HStack(spacing: SpanSpacing.xs) {
                        Image(systemName: input.found ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(input.found ? SpanColor.statusGreen : SpanColor.statusRed)
                        Text(input.parameter)
                            .font(.system(size: 13))
                            .foregroundStyle(SpanColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(input.found ? "found" : "missing")
                            .font(.system(size: 11))
                            .foregroundStyle(input.found ? SpanColor.statusGreen : SpanColor.textTertiary)
                    }
                    .padding(.vertical, 9)
                    .spanBottomHairline()
                }
            }
            .spanCard()
        }
    }
}

// MARK: - Glowing bio-age ring

/// The big circular gauge from v2-bioage.jpeg: a faint track + a glowing colored
/// progress arc (mapped from bio-age within a plausible 20–80y span), with the age
/// number rendered in heavy mono inside.
private struct BioAgeRing: View {
    let value: Double?
    let chrono: Double?
    let color: Color

    /// The arc is a decorative vitality gauge, not a literal age scale (matching the
    /// comp's near-full ring). It fills more when biologically younger than
    /// chronological, and is clamped to a pleasant band so it always reads well —
    /// independent of the absolute age, which may be large in the real data.
    private var fraction: CGFloat {
        guard let value, let chrono, chrono > 0 else { return 0.82 }
        let delta = value - chrono                      // negative = younger
        let normalized = 0.78 - (delta / 20.0)          // younger → higher fill
        return CGFloat(min(0.96, max(0.45, normalized)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SpanColor.textPrimary.opacity(0.05), lineWidth: 14)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .spanGlow(color, radius: 12, opacity: 0.5)

            VStack(spacing: 2) {
                Text("BIOLOGICAL")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(SpanColor.textSecondary)
                Text(valueText)
                    .font(.system(size: 50, weight: .heavy, design: .monospaced))
                    .kerning(-2)
                    .foregroundStyle(SpanColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("years")
                    .font(.system(size: 11))
                    .foregroundStyle(SpanColor.textSecondary)
            }
            .padding(.horizontal, 30)
        }
        .accessibilityElement()
        .accessibilityLabel("Estimated biological age \(valueText) years")
    }

    private var valueText: String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview {
    NavigationStack { BiologicalAgeView() }
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
