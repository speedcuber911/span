//
//  GlucoseStore.swift
//  Span — PERSIST CGM glucose samples so the history survives app restarts / relaunch.
//
//  WHY: CGMConnectionManager keeps only an in-memory rolling window (capped, lost on
//  quit). For a real CGM the user expects past readings to still be there after the
//  app is killed and reopened — and after iOS relaunches us in the background for a
//  new reading. This store is the durable layer.
//
//  PERSISTENCE FORMAT & LOCATION:
//    • All samples are encoded as a single JSON array of `GlucoseSample` (which is
//      Codable — see CGMConnectionManager.swift) and written ATOMICALLY to
//        Application Support/CGM/glucose-samples.json
//      Application Support is the right home for app-managed data the user doesn't see
//      and that should be backed up. We create the CGM/ subfolder on first use.
//    • Writes are DEBOUNCED (~2s) and run OFF the main thread on a serial queue, so a
//      burst of readings collapses into one disk write. Loads happen once on init.
//    • Volume is tiny — ~1 reading/min ≈ 1440/day; a JSON snapshot is more than fast
//      enough and is far simpler/robuster than SQLite for this size.
//
//  This file lives entirely in Screens/CGM/ and consumes only the dark DesignSystem.
//

import Foundation
import Observation

@Observable
final class GlucoseStore {

    // MARK: Published state

    /// All retained samples, sorted oldest→newest. The on-disk file holds the same
    /// set (capped at `maxPersisted`). The UI reads `last24h` for the chart.
    private(set) var samples: [GlucoseSample] = []

    /// Newest sample, if any.
    var latest: GlucoseSample? { samples.last }

    // MARK: Tunables

    /// Default in-range band (mg/dL) for time-in-range. Standard CGM TIR is 70–180.
    static let inRangeLow: Double = 70
    static let inRangeHigh: Double = 180

    /// Keep this much history persisted (and in memory). ~7 days at 1/min ≈ 10k.
    private static let maxPersisted = 20_000
    /// Window the UI charts by default.
    private static let uiWindow: TimeInterval = 24 * 3600

    // MARK: Persistence plumbing

    private let ioQueue = DispatchQueue(label: "com.parikshit.span.glucosestore.io", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private static let saveDebounce: TimeInterval = 2.0

    private let fileURL: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CGM", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("glucose-samples.json")
    }()

    // MARK: Init

    init() {
        loadFromDisk()
    }

    // MARK: Recording

    /// Append a new reading (called by CGMConnectionManager via its `onReading`
    /// closure). Deduped against the most recent sample by ~1-minute bucket: if a
    /// sample with the same minute AND the same mg/dL already exists, we skip it so
    /// repeated identical notifications don't bloat the file. A changed value within
    /// the same minute still records (the sensor refined the reading).
    func record(_ sample: GlucoseSample) {
        if let last = samples.last, isDuplicate(sample, of: last) {
            return
        }
        // Keep sorted: append if newest, else insert at the right spot (restoration or
        // out-of-order delivery can hand us an older timestamp).
        if let last = samples.last, sample.date < last.date {
            let idx = samples.firstIndex { $0.date > sample.date } ?? samples.endIndex
            // Guard duplicates against the neighbour we're inserting next to, too.
            if idx > samples.startIndex, isDuplicate(sample, of: samples[idx - 1]) { return }
            samples.insert(sample, at: idx)
        } else {
            samples.append(sample)
        }
        trimIfNeeded()
        scheduleSave()
    }

    /// Convenience overload.
    func record(mgdl: Double, date: Date = Date()) {
        record(GlucoseSample(mgdl: mgdl, date: date))
    }

    /// Same minute bucket + same rounded mg/dL ⇒ duplicate.
    private func isDuplicate(_ a: GlucoseSample, of b: GlucoseSample) -> Bool {
        guard abs(a.mgdl - b.mgdl) < 0.05 else { return false }
        return Int(a.date.timeIntervalSince1970 / 60) == Int(b.date.timeIntervalSince1970 / 60)
    }

    private func trimIfNeeded() {
        if samples.count > Self.maxPersisted {
            samples.removeFirst(samples.count - Self.maxPersisted)
        }
    }

    /// Wipe history (memory + disk).
    func clear() {
        samples = []
        scheduleSave()
    }

    // MARK: Derived windows & stats

    /// Samples from the last 24h, sorted oldest→newest (the chart's source).
    var last24h: [GlucoseSample] {
        let cutoff = Date().addingTimeInterval(-Self.uiWindow)
        return samples.filter { $0.date >= cutoff }
    }

    /// Min / max / average mg/dL over a window (defaults to last 24h).
    func stats(over window: [GlucoseSample]? = nil) -> GlucoseStats {
        let xs = window ?? last24h
        guard !xs.isEmpty else { return .empty }
        let values = xs.map(\.mgdl)
        let inRange = values.filter { $0 >= Self.inRangeLow && $0 <= Self.inRangeHigh }.count
        return GlucoseStats(
            count: values.count,
            min: values.min() ?? 0,
            max: values.max() ?? 0,
            average: values.reduce(0, +) / Double(values.count),
            timeInRangePct: Double(inRange) / Double(values.count) * 100,
            inRangeLow: Self.inRangeLow,
            inRangeHigh: Self.inRangeHigh
        )
    }

    /// Convenience: stats for last 24h.
    var last24hStats: GlucoseStats { stats(over: last24h) }

    /// Simple trend from the last few points: average slope over up to the last 4
    /// readings, with a ±2 mg/dL deadband (mirrors the live manager's trend logic).
    var trend: LiveGlucoseTrend? {
        let pts = samples.suffix(4)
        guard pts.count >= 2, let first = pts.first, let last = pts.last else { return nil }
        let delta = last.mgdl - first.mgdl
        if delta > 2 { return .up }
        if delta < -2 { return .down }
        return .flat
    }

    // MARK: Disk I/O

    private func loadFromDisk() {
        let url = fileURL
        // Synchronous on init is fine (tiny file, once), so the UI shows history
        // immediately on launch before any reconnect.
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([GlucoseSample].self, from: data) else { return }
        samples = decoded.sorted { $0.date < $1.date }
        trimIfNeeded()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        // Snapshot the value type now; encode off-main after the debounce.
        let snapshot = samples
        let url = fileURL
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            // Atomic write so a crash mid-write can't corrupt the history.
            try? data.write(to: url, options: [.atomic])
        }
        saveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + Self.saveDebounce, execute: work)
    }

    /// Force an immediate save (e.g. on background/terminate) bypassing the debounce.
    func flush() {
        saveWorkItem?.cancel()
        let snapshot = samples
        let url = fileURL
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }
}

// MARK: - Stats value type

/// Summary statistics over a window of glucose samples.
struct GlucoseStats {
    let count: Int
    let min: Double
    let max: Double
    let average: Double
    /// Percent of readings within [inRangeLow, inRangeHigh].
    let timeInRangePct: Double
    let inRangeLow: Double
    let inRangeHigh: Double

    static let empty = GlucoseStats(count: 0, min: 0, max: 0, average: 0,
                                    timeInRangePct: 0, inRangeLow: 70, inRangeHigh: 180)

    var hasData: Bool { count > 0 }
}
