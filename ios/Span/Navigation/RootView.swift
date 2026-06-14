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
    @State private var cgmPath: [Route] = []
    @State private var showingVoice = false

    init() {
        // Dark "Health Intelligence" chrome: blurred dark tab bar with a purple
        // active tab, and the matching dark nav-bar appearance. Styling only —
        // navigation logic is unchanged.
        SpanTabBarStyle.apply()
        SpanNavBarStyle.apply()
    }

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
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(AppTab.today)

                NavigationStack(path: $systemsPath) {
                    SystemsOverviewView(path: $systemsPath)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $systemsPath)
                        }
                }
                .tabItem { Label("Systems", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.systems)

                NavigationStack(path: $checkinPath) {
                    CheckInView()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $checkinPath)
                        }
                }
                .tabItem { Label("Check-in", systemImage: "checklist") }
                .tag(AppTab.checkin)

                NavigationStack(path: $prepPath) {
                    DoctorVisitPrepView()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $prepPath)
                        }
                }
                .tabItem { Label("Prep", systemImage: "stethoscope") }
                .tag(AppTab.prep)

                // Isolated CGM diagnostic probe — its own NavigationStack even
                // though it has no drill-downs yet (matches the other tabs).
                NavigationStack(path: $cgmPath) {
                    CGMView()
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, path: $cgmPath)
                        }
                }
                .tabItem { Label("CGM", systemImage: "drop.fill") }
                .tag(AppTab.cgm)
            }
            .tint(SpanColor.accent)

            if showAskSpan {
                AskSpanPill { showingVoice = true }
                    .padding(.trailing, SpanSpacing.md)
                    .padding(.bottom, 64) // clears the tab bar
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .background(SpanColor.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingVoice) {
            AskSpanView()
        }
        .preferredColorScheme(.dark)
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
