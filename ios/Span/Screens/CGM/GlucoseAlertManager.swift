//
//  GlucoseAlertManager.swift
//  Span — local notifications for glucose HIGHS and LOWS.
//
//  WHY: a CGM is only useful if it warns you. This manager evaluates each new reading
//  against configurable thresholds and fires a LOCAL notification when a threshold is
//  crossed. Local notifications fire whether the app is foreground or background, so
//  the warning reaches the user even while Span is suspended — paired with the
//  bluetooth-central background mode + CoreBluetooth state restoration, readings keep
//  flowing and alerts keep firing.
//
//  NOTE on background BLE: iOS may still THROTTLE background BLE delivery (coalescing
//  notifications, slowing the scan/connection wake cadence). We can't change that — we
//  just react promptly to whatever readings iOS hands us.
//
//  RATE-LIMITING (anti-spam):
//    • Each zone (high / low) holds an "alerted" latch. Once we alert for a zone we
//      DON'T re-alert until either (a) the value returns to normal (latch clears, so
//      the next excursion alerts again) or (b) the situation ESCALATES from a plain
//      high/low to an URGENT high/low (we always alert on first escalation).
//    • Even within a held zone, a fresh plain alert is only allowed after a cooldown
//      (default 25 min) — so a value hovering just over the line can't spam.
//    • Urgent alerts use a shorter cooldown (default 10 min) because they matter more.
//
//  Thresholds are user-configurable and persisted to UserDefaults. The @Observable
//  state is bindable for a settings UI (steppers in CGMView).
//

import Foundation
import Observation
import UserNotifications

@Observable
final class GlucoseAlertManager {

    // MARK: Thresholds (mg/dL) — standard CGM alert levels as defaults.

    /// High alert at/above this. Default 180.
    var highThreshold: Double {
        didSet { persist(); clampThresholds() }
    }
    /// Urgent-high alert at/above this. Default 250.
    var urgentHighThreshold: Double {
        didSet { persist() }
    }
    /// Low alert at/below this. Default 70.
    var lowThreshold: Double {
        didSet { persist(); clampThresholds() }
    }
    /// Urgent-low alert at/below this. Default 54.
    var urgentLowThreshold: Double {
        didSet { persist() }
    }
    /// Master on/off for firing notifications (separate from OS authorization).
    var alertsEnabled: Bool {
        didSet { persist() }
    }

    // MARK: Authorization state (for the settings UI)

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: Rate-limit defaults

    /// Min time between two PLAIN alerts of the same kind.
    private static let plainCooldown: TimeInterval = 25 * 60
    /// Min time between two URGENT alerts of the same kind (shorter — more important).
    private static let urgentCooldown: TimeInterval = 10 * 60

    // MARK: Internal latch / cooldown state

    private enum Excursion { case none, high, urgentHigh, low, urgentLow }

    /// What zone we've most recently alerted for (the latch).
    private var lastAlertedExcursion: Excursion = .none
    private var lastHighAlertAt: Date?
    private var lastLowAlertAt: Date?

    /// History for the simple "falling/rising fast" rule (delta over ~15 min).
    private var recent: [(date: Date, mgdl: Double)] = []
    private static let fastWindow: TimeInterval = 15 * 60
    /// mg/dL change over the window that counts as "fast".
    private static let fastDelta: Double = 45

    private let notifier: UNUserNotificationCenter
    private let defaults: UserDefaults

    // MARK: Init

    init(notifier: UNUserNotificationCenter = .current(),
         defaults: UserDefaults = .standard) {
        self.notifier = notifier
        self.defaults = defaults

        // Load persisted thresholds, else seed the standard defaults.
        let d = defaults
        highThreshold       = Self.stored(d, Keys.high, default: 180)
        urgentHighThreshold = Self.stored(d, Keys.urgentHigh, default: 250)
        lowThreshold        = Self.stored(d, Keys.low, default: 70)
        urgentLowThreshold  = Self.stored(d, Keys.urgentLow, default: 54)
        alertsEnabled       = (d.object(forKey: Keys.enabled) as? Bool) ?? true

        refreshAuthorizationStatus()
    }

    // MARK: Authorization

    /// Request notification authorization (alerts + sounds). Safe to call repeatedly.
    func requestAuthorization() {
        notifier.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    /// Re-read the current OS authorization status into our observable state.
    func refreshAuthorizationStatus() {
        notifier.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: Evaluation — called on every new reading

    /// Evaluate a new sample and fire a notification if it crosses a threshold,
    /// subject to the latch + cooldown rules above.
    func evaluate(_ sample: GlucoseSample) {
        trackRecent(sample)
        guard alertsEnabled else { return }

        let mgdl = sample.mgdl
        let excursion = classify(mgdl)

        switch excursion {
        case .none:
            // Back in range — clear the latch so the NEXT excursion re-alerts.
            lastAlertedExcursion = .none

        case .high, .urgentHigh:
            handleHigh(mgdl: mgdl, excursion: excursion)

        case .low, .urgentLow:
            handleLow(mgdl: mgdl, excursion: excursion)
        }
    }

    private func classify(_ mgdl: Double) -> Excursion {
        if mgdl <= urgentLowThreshold { return .urgentLow }
        if mgdl <= lowThreshold { return .low }
        if mgdl >= urgentHighThreshold { return .urgentHigh }
        if mgdl >= highThreshold { return .high }
        return .none
    }

    private func handleHigh(mgdl: Double, excursion: Excursion) {
        let urgent = (excursion == .urgentHigh)
        // Always alert on first escalation from plain-high to urgent-high.
        let escalated = (excursion == .urgentHigh && lastAlertedExcursion == .high)
        let cooldown: TimeInterval = urgent ? Self.urgentCooldown : Self.plainCooldown
        let cooledDown = lastHighAlertAt.map { Date().timeIntervalSince($0) >= cooldown } ?? true
        // New excursion (latch was cleared / was on the other side) OR escalation OR cooled down.
        let freshExcursion = !isHighLatched
        guard freshExcursion || escalated || cooledDown else { return }

        lastAlertedExcursion = excursion
        lastHighAlertAt = Date()
        fire(
            title: urgent ? "Urgent glucose high" : "Glucose high",
            body: "\(Int(mgdl.rounded())) mg/dL ↑" + (fastRising ? " · rising fast" : ""),
            urgent: urgent
        )
    }

    private func handleLow(mgdl: Double, excursion: Excursion) {
        let urgent = (excursion == .urgentLow)
        let escalated = (excursion == .urgentLow && lastAlertedExcursion == .low)
        let cooldown: TimeInterval = urgent ? Self.urgentCooldown : Self.plainCooldown
        let cooledDown = lastLowAlertAt.map { Date().timeIntervalSince($0) >= cooldown } ?? true
        let freshExcursion = !isLowLatched
        guard freshExcursion || escalated || cooledDown else { return }

        lastAlertedExcursion = excursion
        lastLowAlertAt = Date()
        fire(
            title: urgent ? "Urgent glucose low" : "Glucose low",
            body: "\(Int(mgdl.rounded())) mg/dL ↓" + (fastFalling ? " · falling fast" : ""),
            urgent: urgent
        )
    }

    private var isHighLatched: Bool {
        lastAlertedExcursion == .high || lastAlertedExcursion == .urgentHigh
    }
    private var isLowLatched: Bool {
        lastAlertedExcursion == .low || lastAlertedExcursion == .urgentLow
    }

    // MARK: Rising / falling fast (nice-to-have)

    private func trackRecent(_ sample: GlucoseSample) {
        recent.append((sample.date, sample.mgdl))
        let cutoff = Date().addingTimeInterval(-Self.fastWindow)
        recent.removeAll { $0.date < cutoff }
    }

    /// Δ over the recent window (mg/dL); positive = rising.
    private var recentDelta: Double? {
        guard let first = recent.first, let last = recent.last, recent.count >= 2 else { return nil }
        return last.mgdl - first.mgdl
    }
    private var fastRising: Bool { (recentDelta ?? 0) >= Self.fastDelta }
    private var fastFalling: Bool { (recentDelta ?? 0) <= -Self.fastDelta }

    // MARK: Firing

    private func fire(title: String, body: String, urgent: Bool) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = urgent ? .defaultCritical : .default
        content.interruptionLevel = urgent ? .timeSensitive : .active
        // nil trigger = deliver immediately (works in background).
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        notifier.add(request, withCompletionHandler: nil)
    }

    // MARK: Threshold hygiene

    /// Keep thresholds sane relative to each other (high > low, urgents on the right side).
    private func clampThresholds() {
        if highThreshold <= lowThreshold + 10 { highThreshold = lowThreshold + 10 }
        if urgentHighThreshold < highThreshold { urgentHighThreshold = highThreshold }
        if urgentLowThreshold > lowThreshold { urgentLowThreshold = lowThreshold }
    }

    // MARK: Persistence (UserDefaults)

    private enum Keys {
        static let high = "span.cgm.alert.high"
        static let urgentHigh = "span.cgm.alert.urgentHigh"
        static let low = "span.cgm.alert.low"
        static let urgentLow = "span.cgm.alert.urgentLow"
        static let enabled = "span.cgm.alert.enabled"
    }

    private static func stored(_ d: UserDefaults, _ key: String, default def: Double) -> Double {
        d.object(forKey: key) == nil ? def : d.double(forKey: key)
    }

    private func persist() {
        defaults.set(highThreshold, forKey: Keys.high)
        defaults.set(urgentHighThreshold, forKey: Keys.urgentHigh)
        defaults.set(lowThreshold, forKey: Keys.low)
        defaults.set(urgentLowThreshold, forKey: Keys.urgentLow)
        defaults.set(alertsEnabled, forKey: Keys.enabled)
    }
}
