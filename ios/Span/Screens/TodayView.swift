//
//  TodayView.swift
//  Span — Screen 7. Whole-person overview (home tab).
//
//  Dark "Health Intelligence" revamp, faithful to v2-today.jpeg:
//   • date label + "Good morning, Anoop." two-line greeting + bell.
//   • WELLBEING: two arc rings (Physical / Mental) tinted by T-score band — shown
//     only when a PROMIS check-in exists.
//   • the red "Discuss with your clinician" attention rail (AttentionRail).
//   • SYSTEMS section rendered as ROWS (glowing dot · UPPERCASE name · inline
//     status-colored sparkline · big mono lead value · tiny unit/marker label).
//   • a collapsed biological-age link row (only if available).
//
//  NO single composite score. The floating purple "Ask Span" pill and the bottom
//  tab bar are owned by RootView, not this screen.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: [Route]
    @State private var model: OverviewModel?
    @State private var citation: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    loadingSkeleton
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                        .padding(.horizontal, SpanSpacing.screenH)
                case .loaded(let overview):
                    content(overview)
                }

                DisclaimerFooter()
                    .padding(.top, SpanSpacing.xs)
            }
        }
        .background(SpanColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .citationSheet($citation)
        .task {
            if model == nil { model = OverviewModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }

    // MARK: Loaded content

    @ViewBuilder
    private func content(_ overview: OverviewDTO) -> some View {
        greeting(overview)

        if let promis = overview.promis {
            wellbeingSection(promis)
        }

        // Attention rail — omitted entirely when there is nothing out of range.
        if !overview.attention.isEmpty {
            AttentionRail(items: overview.attention) { item in
                path.append(.parameterDetail(parameterID: item.canonicalParamId))
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.vertical, SpanSpacing.gutter)
            .spanBottomHairline()
        }

        systemsSection(overview)

        if overview.bioageAvailable {
            bioAgeRow
        }
    }

    // MARK: Greeting

    private func greeting(_ overview: OverviewDTO) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(overview.asOf, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(SpanColor.textTertiary)
                Text(greetingText(overview.greetingName))
                    .font(.system(size: 26, weight: .bold))
                    .kerning(-0.7)
                    .lineSpacing(1)
                    .foregroundStyle(SpanColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "bell")
                .font(.system(size: 21))
                .foregroundStyle(SpanColor.textTertiary)
                .padding(.top, 4)
                .accessibilityLabel("Notifications")
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Wellbeing arcs

    private func wellbeingSection(_ promis: PromisDTO) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Wellbeing")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(SpanColor.textTertiary)

            HStack(spacing: SpanSpacing.xs) {
                WellbeingArc(label: "Physical health", tScore: promis.gphTScore)
                WellbeingArc(label: "Mental health", tScore: promis.gmhTScore)
            }

            HStack(spacing: 4) {
                Text("Check-in \(promis.basedOnDate.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.system(size: 10))
                    .foregroundStyle(SpanColor.textTertiary)
                Button {
                    path.append(.checkin)
                } label: {
                    Text("· Update →")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SpanColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.bottom, 14)
        .spanBottomHairline()
    }

    // MARK: Systems

    private func systemsSection(_ overview: OverviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Systems")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(SpanColor.textTertiary)
                .padding(.top, 14)
                .padding(.bottom, 2)

            ForEach(overview.systems) { rollup in
                Button {
                    path.append(.systemDetail(rollup.key))
                } label: {
                    SystemRow(rollup: rollup,
                              value: leadValue(rollup),
                              unit: rollup.leadParameter)
                    .spanBottomHairline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SpanSpacing.screenH)
    }

    /// The big lead value = the most recent sparkline reading, formatted compactly.
    private func leadValue(_ rollup: SystemRollup) -> String {
        guard let v = rollup.sparklinePoints.last else { return "—" }
        return v.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: Biological-age link row

    private var bioAgeRow: some View {
        Button {
            path.append(.bioAge)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Biological age")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundStyle(SpanColor.textTertiary)
                    Text("View your biological-age trend (optional)")
                        .font(.system(size: 11))
                        .foregroundStyle(SpanColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpanColor.textTertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SpanSpacing.screenH)
    }

    // MARK: Loading

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SkeletonBlock(height: 64)
            HStack(spacing: SpanSpacing.xs) {
                SkeletonBlock(height: 92)
                SkeletonBlock(height: 92)
            }
            SkeletonBlock(height: 58)
            ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 44) }
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .padding(.top, 18)
    }

    private func greetingText(_ name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return "\(part),\n\(name)."
    }
}

// MARK: - Wellbeing arc ring (a PROMIS T-score gauge)

/// A half-circle arc gauge tinted by the PROMIS T-score band (matches the comp's
/// `arc()` helper: a 6px arc over a faint track, the band word, and the T-value).
/// Population mean is 50; the ring fills proportionally from T 30…70.
struct WellbeingArc: View {
    let label: String
    let tScore: Double

    /// Fraction of the half-arc that is filled (T 30 = empty, T 70 = full).
    private var progress: Double {
        min(0.99, max(0.01, (tScore - 30) / 40))
    }

    private var tint: Color {
        switch tScore {
        case 55...:    return SpanColor.statusGreen
        case 45..<55:  return SpanColor.textSecondary
        case 40..<45:  return SpanColor.statusYellow
        default:       return SpanColor.statusRed
        }
    }

    private var band: String {
        switch tScore {
        case 55...:    return "Above avg"
        case 45..<55:  return "Average"
        case 40..<45:  return "Mild"
        default:       return "Low"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(SpanColor.textSecondary)

            ZStack {
                // Faint full-arc track.
                ArcShape(progress: 1)
                    .stroke(Color.white.opacity(0.06),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // Tinted fill.
                ArcShape(progress: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            .frame(height: 38)
            .padding(.vertical, 1)

            Text(band)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text("T \(Int(tScore))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpanColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(band), T-score \(Int(tScore)) of 100, where 50 is the population average.")
    }
}

/// A bottom half-circle arc, swept left→right by `progress` (0…1). Matches the
/// comp's 180° arc from the lower-left to the lower-right.
private struct ArcShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height * 2) / 2 - 3
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        // 180° (left) → 0° (right). Sweep the filled fraction starting from the left.
        let start = Angle.degrees(180)
        let end = Angle.degrees(180 - 180 * progress)
        path.addArc(center: center, radius: radius,
                    startAngle: start, endAngle: end, clockwise: true)
        return path
    }
}

#Preview {
    NavigationStack {
        TodayView(path: .constant([]))
    }
    .environment(AppEnvironment.preview)
}
