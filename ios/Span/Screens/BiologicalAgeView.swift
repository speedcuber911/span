//
//  BiologicalAgeView.swift
//  Span — Screen 15. Biological Age (opt-in, secondary).
//
//  Faithful to biological-age.png. Secondary by design — reached only via the
//  Today link. "About this estimate" with the fluctuates-day-to-day +
//  NHANES-US-not-calibrated-for-India caveats; a PhenoAge trend chart; the age
//  variance vs chronological; and the 9 inputs used. When any input is missing,
//  shows the not-computable checklist (no imputation).
//

import SwiftUI
import Charts

struct BiologicalAgeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: BioAgeModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.lg) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    VStack(spacing: SpanSpacing.gutter) { SkeletonBlock(height: 120); SkeletonBlock(height: 200) }
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
            }
            .padding(.horizontal, SpanSpacing.md)
            .padding(.top, SpanSpacing.xs)
        }
        .background(SpanColor.background)
        .navigationTitle("Biological Age")
        .navigationBarTitleDisplayMode(.inline)
        .citationSheet($citation)
        .task {
            if model == nil { model = BioAgeModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    // MARK: Computable

    @ViewBuilder
    private func computableContent(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Phenotypic Age")
                .font(SpanFont.displayLarge)
                .foregroundStyle(SpanColor.textPrimary)
            Text("A biochemical estimate of biological aging based on recent lab panels.")
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
        }

        // About this estimate
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Label("Reference Context", systemImage: "info.circle")
                .font(SpanFont.footnote.weight(.semibold))
                .foregroundStyle(SpanColor.primary)
            Text("This is a rough estimate using the PhenoAge formula (Levine, 2018). It fluctuates with each lab draw and is directional only — not a clinical diagnosis.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
            Text("Based on US reference data (NHANES). May not be calibrated for Indian populations.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textTertiary)
            if let source = result.source {
                CitationChip(source: source) { citation = $0 }
            }
        }
        .spanCard()

        // Age variance + trend chart
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Age Variance").spanSectionHeaderStyle()
                    if let delta = result.deltaYears {
                        Text("\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) Years")
                            .font(SpanFont.displayLarge)
                            .foregroundStyle(delta <= 0 ? SpanColor.statusGreen : SpanColor.textPrimary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let chrono = result.chronoAge {
                        Text("Chronological: \(Int(chrono))")
                            .font(SpanFont.caption2).foregroundStyle(SpanColor.textSecondary)
                    }
                    if let value = result.valueYears {
                        Text("Phenotypic: \(value.formatted(.number.precision(.fractionLength(1))))")
                            .font(SpanFont.caption2).foregroundStyle(SpanColor.textSecondary)
                    }
                }
            }

            Chart(result.trend) { point in
                LineMark(x: .value("Date", point.date), y: .value("PhenoAge", point.valueYears))
                    .foregroundStyle(SpanColor.primary)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("PhenoAge", point.valueYears))
                    .foregroundStyle(SpanColor.primary)
                    .symbolSize(60)
            }
            .frame(height: 180)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.year()).font(SpanFont.caption2) } }
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(SpanFont.caption2) } }

            if let caption = result.confidenceCaption {
                Text(caption)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
        .spanCard()

        // 9 inputs used
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("The 9 Inputs Used").spanSectionHeaderStyle()
            ForEach(result.inputsUsed) { input in
                HStack {
                    Image(systemName: input.found ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(input.found ? SpanColor.statusGreen : SpanColor.statusRed)
                        .font(.system(size: 14))
                    Text(input.parameter)
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                    if let value = input.value {
                        Text("\(value.formatted(.number.precision(.fractionLength(0...2)))) \(input.unit ?? "")")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
            Text("Each input comes from your most recent uploaded lab report.")
                .font(SpanFont.caption2)
                .foregroundStyle(SpanColor.textTertiary)
        }
        .spanCard()

        // What this is not
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            Text("What This Is Not").spanSectionHeaderStyle()
            ForEach(["Not a diagnosis", "Not a prediction of lifespan",
                     "Not comparable between different people or methods",
                     "Not a reason to change any medication or supplement"], id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundStyle(SpanColor.textTertiary)
                    Text(line).font(SpanFont.callout).foregroundStyle(SpanColor.textPrimary)
                }
            }
        }
        .spanCard()
    }

    // MARK: Not computable (no imputation — hard rule)

    private func notComputableContent(_ result: BioAgeResult) -> some View {
        VStack(alignment: .leading, spacing: SpanSpacing.md) {
            Text("Biological age is not yet computable for you.")
                .font(SpanFont.title2)
                .foregroundStyle(SpanColor.textPrimary)
            Text("All 9 inputs are needed:")
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
            ForEach(result.inputsUsed) { input in
                HStack {
                    Image(systemName: input.found ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(input.found ? SpanColor.statusGreen : SpanColor.statusRed)
                    Text(input.parameter + (input.found ? " (found)" : " (not in your reports yet)"))
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                }
            }
        }
        .spanCard()
    }
}

#Preview {
    NavigationStack { BiologicalAgeView() }
        .environment(AppEnvironment.preview)
}
