//
//  ViewModels.swift
//  Span — @Observable view models (Observation framework).
//
//  Each model owns a `Loadable<T>` for the screen's primary DTO and loads it from
//  the injected SpanAPI. No medical logic here — purely fetch + present.
//

import SwiftUI
import Observation

/// Generic async-load state used across screens for skeleton / error handling.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        if case .idle = self { return true }
        return false
    }
}

@MainActor @Observable
final class OverviewModel {
    private let api: SpanAPI
    var state: Loadable<OverviewDTO> = .idle

    init(api: SpanAPI) { self.api = api }

    func load() async {
        state = .loading
        do { state = .loaded(try await api.overview()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

@MainActor @Observable
final class SystemDetailModel {
    private let api: SpanAPI
    let key: SystemKey
    var state: Loadable<SystemDetailDTO> = .idle

    init(api: SpanAPI, key: SystemKey) { self.api = api; self.key = key }

    func load() async {
        state = .loading
        do { state = .loaded(try await api.systemDetail(key)) }
        catch { state = .failed(error.localizedDescription) }
    }
}

@MainActor @Observable
final class ParameterDetailModel {
    private let api: SpanAPI
    let parameterID: String
    var state: Loadable<ParameterDetailDTO> = .idle

    /// Chart window control.
    enum Window: String, CaseIterable, Identifiable {
        case d28 = "28d", y1 = "1y", all = "All"
        var id: String { rawValue }
    }
    var window: Window = .all
    var baselineFirst: Bool = false

    init(api: SpanAPI, parameterID: String) { self.api = api; self.parameterID = parameterID }

    func load() async {
        state = .loading
        do { state = .loaded(try await api.parameterDetail(parameterID)) }
        catch { state = .failed(error.localizedDescription) }
    }

    /// Points filtered by the selected window (purely view-side filtering of the
    /// already-fetched series; the live backend also honors ?window=).
    func windowedPoints(_ all: [TrendPoint]) -> [TrendPoint] {
        guard let cutoff = window.cutoffDate else { return all }
        return all.filter { $0.date >= cutoff }
    }
}

extension ParameterDetailModel.Window {
    var cutoffDate: Date? {
        let cal = Calendar.current
        switch self {
        case .d28: return cal.date(byAdding: .day, value: -28, to: Date())
        case .y1:  return cal.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}

@MainActor @Observable
final class BioAgeModel {
    private let api: SpanAPI
    var state: Loadable<BioAgeResult> = .idle

    init(api: SpanAPI) { self.api = api }

    func load() async {
        state = .loading
        do { state = .loaded(try await api.bioAge()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

@MainActor @Observable
final class IngestionModel {
    private let api: SpanAPI
    var state: Loadable<[IngestionJob]> = .idle

    init(api: SpanAPI) { self.api = api }

    func load() async {
        state = .loading
        do { state = .loaded(try await api.ingestionJobs()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

@MainActor @Observable
final class PrepModel {
    private let api: SpanAPI

    enum Phase: Equatable {
        case entry
        case generating(progress: Double)
        case ready(PrepReport)
        case failed(String)
    }
    var phase: Phase = .entry
    /// Local-only ticked question checkboxes (never synced to server).
    var checkedQuestions: Set<String> = []

    init(api: SpanAPI) { self.api = api }

    /// Simulated async generation with progress, matching the spec's progress UI.
    func generate() async {
        phase = .generating(progress: 0)
        for step in stride(from: 0.2, through: 1.0, by: 0.2) {
            try? await Task.sleep(for: .milliseconds(350))
            phase = .generating(progress: step)
        }
        do { phase = .ready(try await api.prepReport()) }
        catch { phase = .failed(error.localizedDescription) }
    }
}

@MainActor @Observable
final class VoiceConsultantModel {
    enum AgentState: String {
        case idle, listening, thinking, speaking, escalated
    }
    var disclosureAccepted = false
    var agentState: AgentState = .idle
    var textMode = false
    /// Caption / chat turns shown in the live caption view.
    var turns: [VoiceTurn] = VoiceTurn.sampleConversation

    func acceptDisclosure() {
        disclosureAccepted = true
        agentState = .speaking
    }
}

struct VoiceTurn: Identifiable, Hashable {
    enum Speaker { case span, user }
    let id = UUID()
    let speaker: Speaker
    let text: String

    static let sampleConversation: [VoiceTurn] = [
        VoiceTurn(speaker: .span, text: "Hello. I've reviewed your latest lipid panel results. Your LDL cholesterol has improved since the last test, dropping to 95 mg/dL, placing it in the optimal range."),
        VoiceTurn(speaker: .span, text: "Would you like to discuss the dietary changes that contributed to this, or review your other markers?")
    ]
}
