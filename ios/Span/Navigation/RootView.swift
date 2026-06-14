//
//  RootView.swift
//  Span — the root TabView (Today · Systems · Check-in · Prep) with the floating
//  "Ask Span" mic button overlaid above the tab bar on the Today and Systems tabs.
//
//  Each tab owns its own NavigationStack + path so drill-downs stay tab-local.
//  Ask Span launches the voice consultant as a .fullScreenCover.
//

import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selectedTab: AppTab = .today
    @State private var todayPath: [Route] = []
    @State private var systemsPath: [Route] = []
    @State private var checkinPath: [Route] = []
    @State private var prepPath: [Route] = []
    @State private var showingVoice = false

    private var showAskSpan: Bool {
        selectedTab == .today || selectedTab == .systems
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $todayPath) {
                    TodayView(path: $todayPath)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $todayPath)
                        }
                }
                .tabItem { Label("Today", systemImage: "house") }
                .tag(AppTab.today)

                NavigationStack(path: $systemsPath) {
                    SystemsOverviewView(path: $systemsPath)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $systemsPath)
                        }
                }
                .tabItem { Label("Systems", systemImage: "square.grid.2x2") }
                .tag(AppTab.systems)

                NavigationStack(path: $checkinPath) {
                    CheckInView()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $checkinPath)
                        }
                }
                .tabItem { Label("Check-in", systemImage: "checkmark.circle") }
                .tag(AppTab.checkin)

                NavigationStack(path: $prepPath) {
                    DoctorVisitPrepView()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $prepPath)
                        }
                }
                .tabItem { Label("Prep", systemImage: "list.clipboard") }
                .tag(AppTab.prep)
            }
            .tint(SpanColor.primary)

            if showAskSpan {
                AskSpanPill { showingVoice = true }
                    .padding(.trailing, SpanSpacing.md)
                    .padding(.bottom, 64) // clears the tab bar
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showingVoice) {
            AskSpanView()
        }
    }
}

/// Resolves a Route to its destination view. Centralized so every tab's stack
/// shares identical wiring.
struct RouteDestination: View {
    let route: Route
    @Binding var path: [Route]

    var body: some View {
        switch route {
        case .systemDetail(let key):
            SystemDetailView(key: key, path: $path)
        case .parameterDetail(let id):
            ParameterDetailView(parameterID: id)
        case .bioAge:
            BiologicalAgeView()
        case .addReports:
            AddReportsView()
        case .checkin:
            CheckInView()
        case .prepSheet:
            DoctorVisitPrepView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview)
}
