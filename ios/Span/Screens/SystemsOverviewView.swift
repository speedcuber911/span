//
//  SystemsOverviewView.swift
//  Span — Screen 8. The Systems tab: 8 organ-system rows.
//
//  Dark "Health Intelligence" revamp, faithful to the comp's screen 8: a sticky
//  ".nb" header titled "Systems", then a full-width list of rows — each a glowing
//  status dot · the system name + "lead marker · status basis" subtitle · an inline
//  status-colored sparkline · a chevron. Same /v1/overview data as Today.
//

import SwiftUI

struct SystemsOverviewView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: [Route]
    @State private var model: OverviewModel?

    var body: some View {
        VStack(spacing: 0) {
            SpanNavBar(title: "Systems")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch model?.state ?? .idle {
                    case .idle, .loading:
                        VStack(spacing: SpanSpacing.gutter) {
                            ForEach(0..<8, id: \.self) { _ in SkeletonBlock(height: 52) }
                        }
                        .padding(.horizontal, SpanSpacing.screenH)
                        .padding(.top, SpanSpacing.gutter)
                    case .failed(let message):
                        LoadFailureView(message: message) { Task { await model?.load() } }
                    case .loaded(let overview):
                        ForEach(overview.systems) { rollup in
                            Button {
                                path.append(.systemDetail(rollup.key))
                            } label: {
                                SystemDetailRow(rollup: rollup)
                                    .padding(.horizontal, SpanSpacing.screenH)
                                    .spanBottomHairline()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DisclaimerFooter()
                        .padding(.top, SpanSpacing.md)
                }
            }
        }
        .background(SpanColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
