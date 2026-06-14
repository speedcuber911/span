//
//  SpanAPI.swift
//  Span — the network boundary.
//
//  Screens depend ONLY on the `SpanAPI` protocol, never on a concrete client, so
//  every screen previews against `MockSpanAPI` with no backend, and swaps to
//  `LiveSpanAPI` (EC2, /v1) at runtime.
//

import Foundation

protocol SpanAPI: Sendable {
    func overview() async throws -> OverviewDTO
    func systemDetail(_ key: SystemKey) async throws -> SystemDetailDTO
    func parameterDetail(_ id: String) async throws -> ParameterDetailDTO
    func bioAge() async throws -> BioAgeResult
    func citation(_ id: String) async throws -> Source
    func ingestionJobs() async throws -> [IngestionJob]
    func checkinNext() async throws -> CheckinInstrument
    func prepReport() async throws -> PrepReport
}

enum SpanAPIError: Error, LocalizedError {
    case notImplemented
    case unauthorized
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "This endpoint is not wired up yet."
        case .unauthorized:   return "Please sign in again."
        case .transport(let m): return m
        }
    }
}
