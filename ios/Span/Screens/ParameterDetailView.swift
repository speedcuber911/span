//
//  ParameterDetailView.swift
//  Span — Screen 10. Parameter Detail (Swift Charts centerpiece).
//
//  Faithful to hba1c-trend.png. Chart layers (back → front):
//   1. clinical reference band  (gray RectangleMark)
//   2. optimal band             (light-green RectangleMark + green stroke) — only if present
//   3. line mark connecting numeric points
//   4. flag-colored point marks (High=red, Low=blue, Normal=green)
//   5. annotated markers for value==null readings
//  Plus window controls (28d / 1y / All), baseline toggle, the natural-frequency
//  "how unusual is this?" icon grid, the readings table, "About", and citations.
//

import SwiftUI
import Charts

struct ParameterDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let parameterID: String
    @State private var model: ParameterDetailModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    VStack(spacing: SpanSpacing.gutter) {
                        SkeletonBlock(height: 80)
                        SkeletonBlock(height: 220)
                    }
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let dto):
                    content(dto)
                }
                DisclaimerFooter()
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
        .citationSheet($citation)
        .task {
            if model == nil { model = ParameterDetailModel(api: env.api, parameterID: parameterID) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    @ViewBuilder
    private func content(_ dto: ParameterDetailDTO) -> some View {
        if let model {
            ParameterContent(dto: dto, model: model) { citation = $0 }
        }
    }
}

// MARK: - Real content split into a child view so `model` is non-optional

private struct ParameterContent: View {
    let dto: ParameterDetailDTO
    @Bindable var model: ParameterDetailModel
    let onCitation: (Source) -> Void

    private var points: [TrendPoint] { model.windowedPoints(dto.points) }

    var body: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.lg) {
            header
            windowControls
            chartCard
            bandLegend
            if let freq = dto.stat?.naturalFreq { howUnusual(freq) }
            readingsTable
            if let about = dto.about { aboutCard(about) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dto.displayName)
                .font(SpanFont.displayLarge)
                .foregroundStyle(SpanColor.textPrimary)
            if let full = dto.fullName {
                Text(full.uppercased())
                    .spanSectionHeaderStyle()
            }
            HStack(spacing: 6) {
                Text("Latest:")
                    .font(SpanFont.callout)
                    .foregroundStyle(SpanColor.textSecondary)
                Text("\(dto.latestValue.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")\(dto.unit.map { " \($0)" } ?? "")")
                    .font(SpanFont.headline)
                    .foregroundStyle(SpanColor.textPrimary)
                ZoneBadge(flag: dto.latestFlag)
            }
            if let date = dto.latestDate, let lab = dto.latestLab {
                Text("As of \(date.formatted(.dateTime.day().month().year())) · \(lab)")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
            }
        }
    }

    private var windowControls: some View {
        HStack(spacing: SpanSpacing.xs) {
            ForEach(ParameterDetailModel.Window.allCases) { window in
                Button {
                    model.window = window
                } label: {
                    Text(window.rawValue)
                        .font(SpanFont.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(model.window == window ? SpanColor.onPrimary : SpanColor.textSecondary)
                        .background(model.window == window ? SpanColor.primary : SpanColor.surface,
                                    in: Capsule())
                        .overlay(Capsule().stroke(SpanColor.outlineVariant.opacity(0.6), lineWidth: model.window == window ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Toggle(isOn: $model.baselineFirst) {
                Text("Baseline")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
            }
            .toggleStyle(.button)
            .tint(SpanColor.primary)
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("Trend History").spanSectionHeaderStyle()
            Chart {
                // 1. clinical reference band
                if let ref = dto.refBand, let low = ref.low, let high = ref.high {
                    RectangleMark(
                        xStart: .value("Start", points.first?.date ?? Date()),
                        xEnd: .value("End", points.last?.date ?? Date()),
                        yStart: .value("Ref low", low),
                        yEnd: .value("Ref high", high)
                    )
                    .foregroundStyle(SpanColor.clinicalBand)
                }
                // 2. optimal band (only if present)
                if let opt = dto.optimalBand {
                    let lo = opt.low ?? (dto.refBand?.low ?? 0)
                    let hi = opt.high ?? (dto.refBand?.high ?? 0)
                    RectangleMark(
                        xStart: .value("Start", points.first?.date ?? Date()),
                        xEnd: .value("End", points.last?.date ?? Date()),
                        yStart: .value("Opt low", lo),
                        yEnd: .value("Opt high", hi)
                    )
                    .foregroundStyle(SpanColor.optimalFill)
                }
                // 3. line
                ForEach(points.filter { $0.value != nil }) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value ?? 0)
                    )
                    .foregroundStyle(SpanColor.textSecondary)
                    .interpolationMethod(.catmullRom)
                }
                // 4. flag-colored points
                ForEach(points) { point in
                    if let value = point.value {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(point.flag.color)
                        .symbolSize(80)
                        .accessibilityLabel(point.date.formatted(.dateTime.day().month().year()))
                        .accessibilityValue("\(value.formatted()) \(point.unit ?? ""), \(point.flag.label)")
                    } else {
                        // 5. value==null annotated marker at ref-low
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", dto.refBand?.low ?? 0)
                        )
                        .symbol(.diamond)
                        .foregroundStyle(SpanColor.textTertiary)
                        .annotation(position: .top) {
                            Text(point.valueText ?? "—")
                                .font(SpanFont.caption2)
                                .foregroundStyle(SpanColor.textTertiary)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(SpanColor.clinicalBand)
                    AxisValueLabel(format: .dateTime.year())
                        .font(SpanFont.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(SpanColor.clinicalBand)
                    AxisValueLabel().font(SpanFont.caption2)
                }
            }
        }
        .spanCard()
    }

    private var yDomain: ClosedRange<Double> {
        let values = dto.points.compactMap(\.value)
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let ref = dto.refBand { lo = min(lo, ref.low ?? lo); hi = max(hi, ref.high ?? hi) }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    private var bandLegend: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            if let ref = dto.refBand, let low = ref.low, let high = ref.high {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(SpanColor.clinicalBand).frame(width: 16, height: 12)
                    Text("Clinical range: \(low.formatted())–\(high.formatted())\(dto.unit.map { " \($0)" } ?? "")")
                        .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                }
                ForEach(dto.citations.filter { $0.id == ref.sourceId }) { src in
                    CitationChip(source: src, onTap: onCitation)
                }
            }
            if let opt = dto.optimalBand {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(SpanColor.optimalFill)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(SpanColor.optimalBorder, lineWidth: 1))
                        .frame(width: 16, height: 12)
                    Text(opt.label)
                        .font(SpanFont.footnote).foregroundStyle(SpanColor.textSecondary)
                }
                ForEach(dto.citations.filter { $0.id == opt.sourceId }) { src in
                    CitationChip(source: src, onTap: onCitation)
                }
            }
        }
    }

    // MARK: How unusual

    private func howUnusual(_ freq: NaturalFrequency) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("How unusual is this?").spanSectionHeaderStyle()
            Text(freq.comparatorDesc)
                .font(SpanFont.body)
                .foregroundStyle(SpanColor.textPrimary)
            NaturalFrequencyGrid(count: freq.count, denom: freq.denom)
            if let caveat = freq.caveat {
                Text(caveat)
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
        .spanCard()
    }

    // MARK: Readings table

    private var readingsTable: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("Recent Readings").spanSectionHeaderStyle()
            ForEach(dto.points.sorted { $0.date > $1.date }) { point in
                HStack {
                    Text(point.date.formatted(.dateTime.day().month().year()))
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                    Text(point.lab ?? "—")
                        .font(SpanFont.caption2)
                        .foregroundStyle(SpanColor.textTertiary)
                    Text(point.value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? (point.valueText ?? "—"))
                        .font(SpanFont.footnote.weight(.medium))
                        .foregroundStyle(point.flag.color)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .spanCard()
    }

    private func aboutCard(_ about: String) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("About \(dto.displayName)").spanSectionHeaderStyle()
            Text(about)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
            ForEach(dto.citations.filter { $0.tier == .tier1 }) { src in
                CitationChip(source: src, onTap: onCitation)
            }
        }
        .spanCard()
    }
}

#Preview {
    NavigationStack {
        ParameterDetailView(parameterID: "hba1c")
    }
    .environment(AppEnvironment.preview)
}
