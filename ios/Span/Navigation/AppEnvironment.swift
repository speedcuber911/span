//
//  AppEnvironment.swift
//  Span — dependency container injected through the SwiftUI Environment.
//
//  Holds the SpanAPI implementation (Mock for previews/dev, Live for the EC2
//  backend). Screens read `@Environment(AppEnvironment.self)` and build their
//  @Observable models from `env.api`.
//

import SwiftUI
import Observation

@MainActor @Observable
final class AppEnvironment {
    let api: SpanAPI

    init(api: SpanAPI) {
        self.api = api
    }

    /// Preview / development default — no backend required.
    static let preview = AppEnvironment(api: MockSpanAPI())
}
