//
//  Route.swift
//  Span — type-safe Hashable routes for NavigationStack drill-down.
//
//  Tab roots own a NavigationStack bound to a [Route] path; every push uses one
//  of these cases. Modal surfaces (citation sheet, voice cover) are presented as
//  .sheet / .fullScreenCover, not pushed.
//

import Foundation

enum Route: Hashable {
    case systemDetail(SystemKey)
    case parameterDetail(parameterID: String)
    case bioAge
    case addReports
    case checkin
    case prepSheet
}

/// The persistent tabs (Today · Systems · Check-in · Prep · CGM). "Ask Span" is a
/// floating button, not a tab. `cgm` is an isolated diagnostic probe.
enum AppTab: Hashable {
    case today, systems, checkin, prep, cgm
}
