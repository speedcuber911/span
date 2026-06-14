//
//  ParameterDetailView.swift
//  Span — Screen 10. Parameter Detail (Swift Charts centerpiece).
//
//  Dark "Health Intelligence" revamp, faithful to v2-param.jpeg:
//   • nav bar "‹ Metabolic   source"
//   • a huge mono lab value (6.9%) colored by flag + "High ↑" badge
//   • "Mar 2026 · Thyrocare · +0.4% since Sep 2025" subline
//   • 28d / 1y / All segmented control (bound to model.window)
//   • a Swift Charts trend: gradient area fill under the line, a dashed clinical
//     threshold rule, an optimal rule, an annotated "Crossed threshold" point,
//     flag-colored points + a glowing latest point
//   • the "How unusual is this?" card with the red/gray natural-frequency dot grid
//   • citation chips, the readings table, and the educational "About" card.
//
//  Consumes the SAME ParameterDetailDTO / ParameterDetailModel as before — only the
//  visual presentation changed.
//

import SwiftUI
import Charts

struct ParameterDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let parameterID: String
    @State private var model: ParameterDetailModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    VStack(spacing: SpanSpacing.gutter) {
                        SkeletonBlock(height: 120)
                        SkeletonBlock(height: 220)
                        SkeletonBlock(height: 160)
                    }
                    .padding(.horizontal, SpanSpacing.screenH)
                    .padding(.top, SpanSpacing.md)
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let dto):
                    content(dto)
                }
                DisclaimerFooter()
                    .padding(.top, SpanSpacing.lg)
            }
        }
        .background(SpanColor.background)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) { navBar }
        .citationSheet($citation)
        .task {
            if model == nil { model = ParameterDetailModel(api: env.api, parameterID: parameterID) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    // MARK: Nav bar — "‹ Metabolic   source"

    private var navBar: some View {
        SpanNavBar(title: "", backTitle: model?.state.value?.category ?? "Back",
                   onBack: { dismiss() }) {
            if let dto = model?.state.value, let src = topSource(dto) {
                Button { citation = src } label: {
                    Text("source")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SpanColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func topSource(_ dto: ParameterDetailDTO) -> Source? {
        dto.citations.first { $0.tier == .tier1 } ?? dto.citations.first
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

    private var windowOptions: [String] { ParameterDetailModel.Window.allCases.map(\.rawValue) }
    private var windowSelection: Binding<Int> {
        Binding(
            get: { ParameterDetailModel.Window.allCases.firstIndex(of: model.window) ?? 2 },
            set: { model.window = ParameterDetailModel.Window.allCases[$0] }
        )
    }

    /// Points in the selected window, oldest → newest, only numeric values.
    private var points: [TrendPoint] {
        model.windowedPoints(dto.points).sorted { $0.date < $1.date }
    }
    private var numericPoints: [TrendPoint] { points.filter { $0.value != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.md)
                .padding(.bottom, SpanSpacing.md)
                .spanBottomHairline()

            SpanSegmentedControl(options: windowOptions, selection: windowSelection)
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.vertical, SpanSpacing.gutter)
                .spanBottomHairline()

            chart
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.vertical, SpanSpacing.md)
                .spanBottomHairline()

            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                if let freq = dto.stat?.naturalFreq { howUnusual(freq) }
                citationRow
                readingsTable
                if let about = dto.about { aboutCard(about) }
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
        }
    }

    // MARK: Header — uppercase full name, huge mono value, badge, subline

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((dto.fullName ?? dto.displayName).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(SpanColor.textTertiary)

            HStack(alignment: .center, spacing: 10) {
                valueText
                StatusBadge(text: badgeText, style: StatusBadgeStyle(flag: dto.latestFlag),
                            systemImage: badgeArrow, prominent: true)
            }

            Text(subline)
                .font(.system(size: 11.5))
                .foregroundStyle(SpanColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: some View {
        let flagColor = dto.latestFlag.color
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(formattedLatest)
                .font(.system(size: 64, weight: .heavy, design: .monospaced))
                .kerning(-3)
                .foregroundStyle(flagColor)
            if let unit = dto.unit {
                Text(unit)
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(flagColor.opacity(0.85))
            }
        }
        .spanGlow(flagColor, radius: 14, opacity: dto.latestFlag == .high ? 0.35 : 0.18)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var formattedLatest: String {
        dto.latestValue.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
    }

    private var badgeText: String {
        switch dto.latestFlag {
        case .high: return "High"
        case .low: return "Low"
        case .normal: return "Optimal"
        case .none: return "Not tested"
        }
    }
    private var badgeArrow: String? {
        switch dto.latestFlag {
        case .high: return "arrow.up"
        case .low: return "arrow.down"
        default: return nil
        }
    }

    /// "Mar 2026 · Thyrocare · +0.4% since Sep 2025" (computed from the real series).
    private var subline: String {
        var parts: [String] = []
        if let date = dto.latestDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).year()))
        }
        if let lab = dto.latestLab { parts.append(lab) }
        if let change = changeSincePrior { parts.append(change) }
        return parts.joined(separator: " · ")
    }

    private var changeSincePrior: String? {
        let numeric = dto.points.compactMap { p -> (Date, Double)? in
            p.value.map { (p.date, $0) }
        }.sorted { $0.0 < $1.0 }
        guard numeric.count >= 2, let latest = numeric.last else { return nil }
        let prior = numeric[numeric.count - 2]
        let delta = latest.1 - prior.1
        let sign = delta >= 0 ? "+" : ""
        let unit = dto.unit ?? ""
        let date = prior.0.formatted(.dateTime.month(.abbreviated).year())
        return "\(sign)\(delta.formatted(.number.precision(.fractionLength(0...1))))\(unit) since \(date)"
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            // optimal band (subtle green fill) — only if present
            if let opt = dto.optimalBand {
                let lo = opt.low ?? (dto.refBand?.low ?? yDomain.lowerBound)
                let hi = opt.high ?? (dto.refBand?.high ?? yDomain.upperBound)
                RectangleMark(
                    xStart: .value("Start", domainStart),
                    xEnd: .value("End", domainEnd),
                    yStart: .value("Opt low", lo),
                    yEnd: .value("Opt high", hi)
                )
                .foregroundStyle(SpanColor.statusGreen.opacity(0.045))
            }

            // gradient area fill under the line
            ForEach(numericPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", yDomain.lowerBound),
                    yEnd: .value("Value", point.value ?? 0)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.catmullRom)
            }

            // clinical threshold rule (dashed)
            if let threshold = thresholdValue {
                RuleMark(y: .value("Threshold", threshold))
                    .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [5, 4]))
                    .foregroundStyle(SpanColor.statusRed.opacity(0.35))
                    .annotation(position: .top, alignment: .leading) {
                        Text(thresholdLabel)
                            .font(.system(size: 8.5))
                            .foregroundStyle(SpanColor.statusRed.opacity(0.55))
                    }
            }

            // optimal rule line
            if let opt = dto.optimalBand, let optEdge = opt.high ?? opt.low {
                RuleMark(y: .value("Optimal", optEdge))
                    .lineStyle(StrokeStyle(lineWidth: 0.75))
                    .foregroundStyle(SpanColor.statusGreen.opacity(0.30))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text(opt.label)
                            .font(.system(size: 8.5))
                            .foregroundStyle(SpanColor.statusGreen.opacity(0.5))
                    }
            }

            // the trend line, gradient-colored by zone
            ForEach(numericPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value ?? 0)
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineColor)
                .interpolationMethod(.catmullRom)
            }

            // flag-colored points; glowing emphasis on the latest
            ForEach(numericPoints) { point in
                let isLatest = point.id == numericPoints.last?.id
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value ?? 0)
                )
                .symbolSize(isLatest ? 150 : 70)
                .foregroundStyle(point.flag.color)
                .annotation(position: .top, spacing: 6) {
                    if isLatest, let v = point.value {
                        Text("\(v.formatted(.number.precision(.fractionLength(0...1))))\(dto.unit ?? "")")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(point.flag.color)
                    } else if point.id == crossingPoint?.id {
                        Text("Crossed\nthreshold")
                            .font(.system(size: 8))
                            .italic()
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(SpanColor.textPrimary.opacity(0.28))
                    }
                }
                .accessibilityLabel(point.date.formatted(.dateTime.month().year()))
                .accessibilityValue("\((point.value ?? 0).formatted()) \(dto.unit ?? ""), \(point.flag.label)")
            }

            // non-numeric readings → diamond markers at the floor
            ForEach(points.filter { $0.value == nil }) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", yDomain.lowerBound)
                )
                .symbol(.diamond)
                .foregroundStyle(SpanColor.textTertiary)
                .annotation(position: .top) {
                    Text(point.valueText ?? "—")
                        .font(.system(size: 8))
                        .foregroundStyle(SpanColor.textTertiary)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .frame(height: 210)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(SpanColor.border.opacity(0.6))
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(.system(size: 8.5))
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(SpanColor.border.opacity(0.4))
                AxisValueLabel()
                    .font(.system(size: 8.5))
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
    }

    private var lineColor: Color {
        dto.latestFlag.color
    }

    private var areaGradient: LinearGradient {
        let base = dto.latestFlag.color
        return LinearGradient(
            colors: [base.opacity(0.40), base.opacity(0.05), base.opacity(0.0)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Clinical diagnostic threshold = top of the reference band.
    private var thresholdValue: Double? { dto.refBand?.high }
    private var thresholdLabel: String {
        guard let t = thresholdValue else { return "" }
        let label = dto.refBand?.refSourceLabel ?? "clinical range"
        return "\(t.formatted(.number.precision(.fractionLength(0...1))))\(dto.unit ?? "") — \(label)"
    }

    /// First numeric point that crossed above the threshold (for the annotation).
    private var crossingPoint: TrendPoint? {
        guard let t = thresholdValue else { return nil }
        return numericPoints.dropLast().first { ($0.value ?? 0) > t }
    }

    private var domainStart: Date { points.first?.date ?? Date() }
    private var domainEnd: Date { points.last?.date ?? Date() }

    private var yDomain: ClosedRange<Double> {
        let values = points.compactMap(\.value)
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let ref = dto.refBand {
            if let l = ref.low { lo = min(lo, l) }
            if let h = ref.high { hi = max(hi, h) }
        }
        if let opt = dto.optimalBand {
            if let l = opt.low { lo = min(lo, l) }
            if let h = opt.high { hi = max(hi, h) }
        }
        let pad = max((hi - lo) * 0.18, 0.1)
        return (lo - pad)...(hi + pad)
    }

    // MARK: How unusual

    private func howUnusual(_ freq: NaturalFrequency) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            Text("How unusual is this?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SpanColor.textPrimary)
            naturalFreqSentence(freq)
            NaturalFrequencyGrid(count: freq.count, denom: freq.denom,
                                 tint: dto.latestFlag == .normal ? SpanColor.statusGreen : SpanColor.statusRed)
            if let caveat = freq.caveat {
                Text(caveat)
                    .font(.system(size: 9.5))
                    .foregroundStyle(SpanColor.textTertiary)
                    .lineSpacing(1)
            }
        }
        .spanCard()
    }

    /// "About 23 in 100 people …" with the count bolded in primary text.
    private func naturalFreqSentence(_ freq: NaturalFrequency) -> some View {
        let count = Text("\(freq.count) in \(freq.denom)")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(SpanColor.textPrimary)
        let rest = Text(suffix(of: freq.comparatorDesc))
            .font(.system(size: 13))
            .foregroundColor(SpanColor.textSecondary)
        return (Text("About ").font(.system(size: 13)).foregroundColor(SpanColor.textSecondary) + count + rest)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Strip a leading "About N of M …" so we can re-render the count with emphasis.
    private func suffix(of desc: String) -> String {
        if let range = desc.range(of: #"^About\s+\d+\s+(of|in)\s+\d+"#, options: .regularExpression) {
            return desc[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
                ? "."
                : " " + desc[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return " " + desc
    }

    private var citationRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(dto.citations) { src in
                CitationChip(source: src, onTap: onCitation)
            }
        }
    }

    // MARK: Readings table

    private var readingsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpanSectionLabel("All readings")
                .padding(.bottom, SpanSpacing.xs)
            HStack {
                Text("DATE").frame(maxWidth: .infinity, alignment: .leading)
                Text("VALUE").frame(width: 64, alignment: .leading)
                Text("LAB").frame(maxWidth: .infinity, alignment: .leading)
                Text("STATUS").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 8.5, weight: .semibold))
            .kerning(0.9)
            .foregroundStyle(SpanColor.textTertiary)
            .padding(.vertical, 6)
            .spanBottomHairline()

            ForEach(dto.points.sorted { $0.date > $1.date }) { point in
                HStack {
                    Text(point.date.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.system(size: 12))
                        .foregroundStyle(SpanColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(readingValue(point))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(SpanColor.textPrimary)
                        .frame(width: 64, alignment: .leading)
                    Text(point.lab ?? "—")
                        .font(.system(size: 12))
                        .foregroundStyle(SpanColor.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StatusBadge(text: statusWord(point.flag), style: StatusBadgeStyle(flag: point.flag))
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.vertical, 9)
                .spanBottomHairline()
            }
        }
    }

    private func readingValue(_ point: TrendPoint) -> String {
        if let v = point.value {
            return "\(v.formatted(.number.precision(.fractionLength(0...1))))\(dto.unit ?? "")"
        }
        return point.valueText ?? "—"
    }

    private func statusWord(_ flag: MeasurementFlag) -> String {
        switch flag {
        case .high: return "High"
        case .low: return "Low"
        case .normal: return "Optimal"
        case .none: return "—"
        }
    }

    private func aboutCard(_ about: String) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("About \(dto.displayName)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SpanColor.textPrimary)
            Text(about)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
                .lineSpacing(2)
            FlowLayout(spacing: 6) {
                ForEach(dto.citations.filter { $0.tier == .tier1 }) { src in
                    CitationChip(source: src, onTap: onCitation)
                }
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
    .preferredColorScheme(.dark)
}
