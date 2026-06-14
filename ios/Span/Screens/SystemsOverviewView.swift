//
//  SystemsOverviewView.swift
//  Span — Screen 8. The Systems tab: 8 organ-system rows.
//
//  Faithful to systems-overview.png: a large "Systems" title, then a list of
//  rows (icon in a tinted circle + zone dot, name, lead marker + arrow, count
//  basis, sparkline, chevron). Same /v1/overview data as Today.
//

import SwiftUI

struct SystemsOverviewView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: [Route]
    @State private var model: OverviewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
                Text("Systems")
                    .font(SpanFont.displayLarge)
                    .foregroundStyle(SpanColor.textPrimary)
                    .padding(.top, SpanSpacing.xs)

                switch model?.state ?? .idle {
                case .idle, .loading:
                    ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 84) }
                case .failed(let message):
                    LoadFailureView(message: message) { Task { await model?.load() } }
                case .loaded(let overview):
                    ForEach(overview.systems) { rollup in
                        Button {
                            path.append(.systemDetail(rollup.key))
                        } label: {
                            OrganSystemRow(rollup: rollup)
                        }
                        .buttonStyle(.plain)
                    }
                }

                DisclaimerFooter()
            }
            .padding(.horizontal, SpanSpacing.md)
        }
        .background(SpanColor.background)
        .navigationTitle("Span Health")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = OverviewModel(api: env.api) }
            if model?.state.value == nil { await model?.load() }
        }
    }
}

#Preview {
    NavigationStack {
        SystemsOverviewView(path: .constant([]))
    }
    .environment(AppEnvironment.preview)
}
