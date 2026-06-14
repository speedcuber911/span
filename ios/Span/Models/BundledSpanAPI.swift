//
//  BundledSpanAPI.swift
//  Span — an offline SpanAPI backed by a bundled JSON snapshot.
//
//  Loads `sample-data.json` (written by the data generator) from the app bundle
//  once at init, decodes it with an ISO-8601 date strategy, and serves every
//  `SpanAPI` method straight from the cached blob — no backend, real parsed data.
//
//  The DTOs declare their own `CodingKeys`, so we deliberately do NOT set a
//  `keyDecodingStrategy`: snake_case mapping already lives in DTOs.swift. Setting
//  `.convertFromSnakeCase` here would double-convert and break those explicit keys.
//
//  Swap in `SpanApp.swift`:  AppEnvironment(api: BundledSpanAPI())
//

import Foundation

/// Errors specific to loading / serving the bundled snapshot.
enum BundledSpanAPIError: Error, LocalizedError {
    case resourceMissing(String)
    case decodeFailed(underlying: Error)
    case notFound(kind: String, id: String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Bundled resource \"\(name)\" was not found in the app bundle. " +
                   "Confirm Span/Resources/\(name) is bundled as a copy resource."
        case .decodeFailed(let underlying):
            return "Failed to decode bundled sample data: \(underlying)"
        case .notFound(let kind, let id):
            return "No \(kind) with id \"\(id)\" in the bundled sample data."
        }
    }
}

/// A `SpanAPI` that renders the bundled JSON snapshot with no network.
///
/// The only stored property is an immutable `let blob` of value-type DTOs, so the
/// class is effectively immutable and safe to share across actors. `SpanAPI`
/// refines `Sendable`; a `final class` with only immutable `Sendable` lets is a
/// valid `Sendable` conformance.
final class BundledSpanAPI: SpanAPI {

    /// Mirror of the top-level JSON object in `sample-data.json`. Each value
    /// decodes into the matching DTO; dicts are keyed exactly as in the file
    /// (systems by `SystemKey.rawValue`, parameters by param id, citations by
    /// source id).
    private struct Container: Decodable {
        let overview: OverviewDTO
        let systems: [String: SystemDetailDTO]
        let parameters: [String: ParameterDetailDTO]
        let bioage: BioAgeResult
        let ingestionJobs: [IngestionJob]
        let checkin: CheckinInstrument
        let prep: PrepReport
        let citations: [String: Source]

        enum CodingKeys: String, CodingKey {
            case overview, systems, parameters, bioage, checkin, prep, citations
            case ingestionJobs = "ingestion_jobs"
        }
    }

    private let blob: Container

    /// Loads and decodes `sample-data.json` from the given bundle (defaults to
    /// `Bundle.main`). On any failure we `assertionFailure` in DEBUG so a shape
    /// mismatch is impossible to miss while testing, then fall back to an empty
    /// snapshot in release rather than crashing.
    init(bundle: Bundle = .main, resource: String = "sample-data") {
        do {
            self.blob = try Self.load(bundle: bundle, resource: resource)
        } catch {
            #if DEBUG
            assertionFailure("BundledSpanAPI failed to load \(resource).json — \(error)")
            #endif
            self.blob = Self.empty
        }
    }

    private static func load(bundle: Bundle, resource: String) throws -> Container {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw BundledSpanAPIError.resourceMissing("\(resource).json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // NOTE: no keyDecodingStrategy — the DTOs own their snake_case CodingKeys.
        do {
            return try decoder.decode(Container.self, from: data)
        } catch {
            throw BundledSpanAPIError.decodeFailed(underlying: error)
        }
    }

    // MARK: SpanAPI

    func overview() async throws -> OverviewDTO {
        blob.overview
    }

    func systemDetail(_ key: SystemKey) async throws -> SystemDetailDTO {
        guard let detail = blob.systems[key.rawValue] else {
            throw BundledSpanAPIError.notFound(kind: "system", id: key.rawValue)
        }
        return detail
    }

    func parameterDetail(_ id: String) async throws -> ParameterDetailDTO {
        guard let detail = blob.parameters[id] else {
            throw BundledSpanAPIError.notFound(kind: "parameter", id: id)
        }
        return detail
    }

    func bioAge() async throws -> BioAgeResult {
        blob.bioage
    }

    func citation(_ id: String) async throws -> Source {
        guard let source = blob.citations[id] else {
            throw BundledSpanAPIError.notFound(kind: "citation", id: id)
        }
        return source
    }

    func ingestionJobs() async throws -> [IngestionJob] {
        blob.ingestionJobs
    }

    func checkinNext() async throws -> CheckinInstrument {
        blob.checkin
    }

    func prepReport() async throws -> PrepReport {
        blob.prep
    }

    // MARK: Release-mode fallback

    /// An empty-but-valid snapshot used only if the bundle resource is missing or
    /// malformed in a release build (DEBUG asserts before reaching this).
    private static let empty = Container(
        overview: OverviewDTO(
            greetingName: "",
            asOf: Date(),
            promis: nil,
            attention: [],
            systems: [],
            bioageAvailable: false
        ),
        systems: [:],
        parameters: [:],
        bioage: BioAgeResult(
            computable: false,
            missingInputs: [],
            valueYears: nil,
            chronoAge: nil,
            deltaYears: nil,
            trend: [],
            inputsUsed: [],
            confidenceCaption: nil,
            caveats: [],
            sourceId: nil,
            source: nil
        ),
        ingestionJobs: [],
        checkin: CheckinInstrument(
            instrumentId: "",
            instrumentName: "",
            intro: nil,
            items: []
        ),
        prep: PrepReport(
            id: "",
            generatedAt: Date(),
            raiseFirst: RaiseFirst(body: "", citations: []),
            glanceTable: [],
            questions: [],
            lifestyleSupplements: [],
            gapsClinicianMissed: []
        ),
        citations: [:]
    )
}
