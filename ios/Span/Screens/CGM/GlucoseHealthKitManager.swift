//
//  GlucoseHealthKitManager.swift
//  Span — CGM diagnostic probe (Probe A: Apple Health → blood glucose).
//
//  ISOLATED probe. Reads ONLY HKQuantityType(.bloodGlucose), read-only, never
//  writes/shares any type. The whole point is to answer one question: does the
//  GlucoRx Vixxa stack (Vixxa app / GlucoRx / MicroTech / AiDEX) actually mirror
//  glucose into Apple Health — and if so, under which SOURCE app name.
//
//  HealthKit deliberately makes READ authorization opaque (you cannot tell
//  "denied" from "no data" via authorizationStatus(for:)). So we DO NOT branch on
//  authorizationStatus for reads — we request, run the query, and surface whatever
//  comes back, including the empty case. The source name on each sample is THE
//  experiment result.
//

import Foundation
import HealthKit
import Observation

/// One blood-glucose sample, flattened for display. `sourceName` is the answer to
/// the probe: which app wrote this reading into Health.
struct GlucoseReading: Identifiable, Hashable {
    let id: UUID
    /// Value in mg/dL (the clinical display unit).
    let value: Double
    /// Convenience mmol/L (= mg/dL ÷ 18.0182).
    let mmol: Double
    /// Unit label for display ("mg/dL").
    let unit: String
    let date: Date
    /// `sample.sourceRevision.source.name` — e.g. "Vixxa", "GlucoRx", "Health".
    let sourceName: String
}

/// Up / flat / down trend of the latest reading vs. the prior one.
enum GlucoseTrend {
    case up, flat, down

    var symbolName: String {
        switch self {
        case .up:   return "arrow.up.right"
        case .flat: return "arrow.right"
        case .down: return "arrow.down.right"
        }
    }
    var label: String {
        switch self {
        case .up:   return "Rising"
        case .flat: return "Flat"
        case .down: return "Falling"
        }
    }
}

@Observable
final class GlucoseHealthKitManager {

    // MARK: Published state

    /// Most-recent-first list of blood-glucose readings pulled from Health.
    private(set) var samples: [GlucoseReading] = []
    /// True once we have asked the system for read authorization at least once.
    private(set) var authRequested = false
    /// User-facing error string (nil = no error).
    private(set) var errorMessage: String?
    /// True while a request / query is in flight.
    private(set) var isLoading = false

    /// The newest reading (samples are sorted descending).
    var latest: GlucoseReading? { samples.first }

    /// Trend of the latest reading vs. the immediately prior one.
    var latestTrend: GlucoseTrend? {
        guard samples.count >= 2 else { return nil }
        let newest = samples[0].value
        let prior = samples[1].value
        let delta = newest - prior
        // ±2 mg/dL deadband so jitter does not read as a trend.
        if delta > 2 { return .up }
        if delta < -2 { return .down }
        return .flat
    }

    /// The distinct source app names seen — handy for the "which path" answer.
    var sourceNames: [String] {
        var seen: [String] = []
        for s in samples where !seen.contains(s.sourceName) { seen.append(s.sourceName) }
        return seen
    }

    // MARK: Private

    private let store = HKHealthStore()
    private let glucoseType = HKQuantityType(.bloodGlucose)
    /// mg/dL = (milligrams) / (deciliter).
    private let mgdlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    /// In-memory anchor for the live (anchored) query — kept so updates are incremental.
    private var anchor: HKQueryAnchor?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var observerQuery: HKObserverQuery?

    // MARK: Authorization + initial fetch

    /// Request READ access for blood glucose only, then fetch. Safe to call
    /// repeatedly (acts as a refresh). Never requests write/share types.
    @MainActor
    func requestAndFetch() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is not available on this device."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            // Read-only: toShare is empty, read is just blood glucose.
            try await store.requestAuthorization(toShare: [], read: [glucoseType])
            authRequested = true
        } catch {
            // A thrown error here is a real failure (not the opaque deny). We still
            // proceed to query — the empty result is itself a valid probe outcome.
            errorMessage = "Authorization request failed: \(error.localizedDescription)"
        }
        await fetchLatest()
        startLiveUpdates()
        isLoading = false
    }

    /// One-shot snapshot query: newest 100 samples, descending by start date.
    /// We do NOT gate this on authorizationStatus — read auth is opaque, so we
    /// run the query and surface whatever (including nothing) comes back.
    @MainActor
    func fetchLatest() async {
        let readings: [GlucoseReading] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: nil,
                limit: 100,
                sortDescriptors: [sort]
            ) { [weak self] _, samples, error in
                guard let self else { continuation.resume(returning: []); return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = "Query failed: \(error.localizedDescription)"
                    }
                }
                let mapped = (samples as? [HKQuantitySample] ?? []).map { self.makeReading($0) }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
        samples = readings
    }

    // MARK: Live updates (foreground)

    /// Start an anchored-object query that appends new samples as they arrive while
    /// the app is foregrounded. The anchor is held in memory so each callback is
    /// incremental. Also kicks off the best-effort background path.
    @MainActor
    func startLiveUpdates() {
        guard anchoredQuery == nil else { return }

        let query = HKAnchoredObjectQuery(
            type: glucoseType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, newSamples, _, newAnchor, _ in
            self?.handleAnchored(newSamples: newSamples, newAnchor: newAnchor)
        }
        query.updateHandler = { [weak self] _, newSamples, _, newAnchor, _ in
            self?.handleAnchored(newSamples: newSamples, newAnchor: newAnchor)
        }
        anchoredQuery = query
        store.execute(query)

        enableBackgroundDeliveryBestEffort()
    }

    private func handleAnchored(newSamples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        let quantitySamples = (newSamples as? [HKQuantitySample]) ?? []
        let mapped = quantitySamples.map { makeReading($0) }
        Task { @MainActor in
            self.anchor = newAnchor
            guard !mapped.isEmpty else { return }
            // Merge, de-dup by id, keep newest-first.
            var byID = Dictionary(uniqueKeysWithValues: self.samples.map { ($0.id, $0) })
            for r in mapped { byID[r.id] = r }
            self.samples = byID.values.sorted { $0.date > $1.date }
        }
    }

    /// Stretch / best-effort. iOS aggressively THROTTLES background glucose delivery
    /// (and on the simulator there is no data at all), so this is never on the main
    /// path — it just registers, failures are swallowed. The foreground anchored
    /// query above is what actually drives the UI.
    private func enableBackgroundDeliveryBestEffort() {
        store.enableBackgroundDelivery(for: glucoseType, frequency: .immediate) { [weak self] success, _ in
            guard success, let self, self.observerQuery == nil else { return }
            let observer = HKObserverQuery(sampleType: self.glucoseType, predicate: nil) { _, completion, _ in
                // We don't fetch here on the background path; the anchored query's
                // updateHandler already coalesces new samples while foregrounded.
                completion()
            }
            self.observerQuery = observer
            self.store.execute(observer)
        }
    }

    // MARK: Mapping

    private func makeReading(_ sample: HKQuantitySample) -> GlucoseReading {
        let mgdl = sample.quantity.doubleValue(for: mgdlUnit)
        return GlucoseReading(
            id: sample.uuid,
            value: mgdl,
            mmol: mgdl / 18.0182,
            unit: "mg/dL",
            date: sample.startDate,
            sourceName: sample.sourceRevision.source.name
        )
    }
}
