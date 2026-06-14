//
//  CGMConnectionManager.swift
//  Span — CONNECT to the GlucoRx Vixxa CGM sensor over BLE GATT and read live
//  glucose continuously (the app becomes a real CGM reader, replacing the Vixxa app).
//
//  WHY this exists (vs the passive BluetoothScanManager): the sensor allows ONE BLE
//  connection at a time and only ADVERTISES while nothing is connected. The passive
//  advertisement decode (AiDEXDecoder) therefore only works when the Vixxa app is
//  closed AND nobody owns the connection. This manager instead CONNECTS, owns the
//  link, and subscribes to the standard Continuous Glucose Monitoring (CGM) GATT
//  service so glucose streams to us as notifications — exactly what the Vixxa app
//  was doing.
//
//  READ-ONLY INTENT: we subscribe (CCCD writes) and READ characteristics. The ONLY
//  value-writes are to the session-control characteristics (Session Start Time
//  0x2AAA and the CGM Specific Ops Control Point 0x2AAC), which the spec REQUIRES to
//  start the data session. We never write glucose, calibration, or anything else.
//
//  STANDARD CGM SERVICE (Bluetooth SIG) — implemented exactly:
//    Service                       0x181F
//    CGM Measurement               0x2AA7  NOTIFY   ← glucose arrives here
//    CGM Feature                   0x2AA8  READ     (bit 12 = E2E-CRC present)
//    CGM Status                    0x2AA9  READ
//    CGM Session Start Time        0x2AAA  READ/WRITE
//    CGM Session Run Time          0x2AAB  READ
//    Record Access Control Point   0x2A52  WRITE/INDICATE (history — phase 2)
//    CGM Specific Ops Control Pt   0x2AAC  WRITE/INDICATE (Start Session = 0x1A)
//
//  CGM Measurement record byte layout (per the spec):
//    [0] Size   : uint8  (total record length incl. this byte)
//    [1] Flags  : uint8
//    [2..3] Glucose Concentration : SFLOAT, mg/dL, little-endian
//    [4..5] Time Offset           : uint16 minutes since session start, LE
//    ...    optional fields (status, trend, quality) gated by Flags
//    [last-2..last] optional E2E-CRC : uint16 (only if CGM Feature bit 12 set)
//
//  SFLOAT (IEEE-11073 16-bit short float): high nibble of the high byte is a signed
//  4-bit exponent (two's complement); the low 12 bits are a signed mantissa (two's
//  complement). value = mantissa * 10^exponent. Reserved/NaN codes return nil.
//

import Foundation
import CoreBluetooth
import Observation

// MARK: - Models

/// One live glucose sample read over GATT (or cross-checked from the advert).
///
/// Codable so `GlucoseStore` can snapshot the rolling history to disk and reload it
/// on launch. `mmol` is derived from `mgdl` at init, so we persist only the source
/// fields (id, mgdl, date, timeOffsetMin) and re-derive `mmol` on decode via the
/// memberwise-aware decoder below — keeping one source of truth for the conversion.
struct GlucoseSample: Identifiable, Hashable, Codable {
    let id: UUID
    /// Glucose in mg/dL (the clinical display unit).
    let mgdl: Double
    /// Convenience mmol/L (= mg/dL ÷ 18.0182).
    let mmol: Double
    let date: Date
    /// Minutes since session start, from the CGM Measurement Time Offset field.
    let timeOffsetMin: Int?

    init(mgdl: Double, date: Date = Date(), timeOffsetMin: Int? = nil, id: UUID = UUID()) {
        self.id = id
        self.mgdl = (mgdl * 10).rounded() / 10
        self.mmol = ((mgdl / 18.0182) * 10).rounded() / 10
        self.date = date
        self.timeOffsetMin = timeOffsetMin
    }

    // MARK: Codable (persistence)

    // Persist only the source fields; `mmol` is re-derived from `mgdl` on decode so
    // the mg/dL→mmol/L conversion has a single source of truth (the initializer).
    private enum CodingKeys: String, CodingKey { case id, mgdl, date, timeOffsetMin }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mgdl: try c.decode(Double.self, forKey: .mgdl),
            date: try c.decode(Date.self, forKey: .date),
            timeOffsetMin: try c.decodeIfPresent(Int.self, forKey: .timeOffsetMin),
            id: try c.decode(UUID.self, forKey: .id)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(mgdl, forKey: .mgdl)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(timeOffsetMin, forKey: .timeOffsetMin)
    }
}

/// Up / flat / down trend derived from the last two GATT samples.
enum LiveGlucoseTrend {
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

/// Coarse connection lifecycle state, each with a human-readable line for the UI.
enum CGMConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case discovering
    case subscribing
    case streaming
    case failed(String)

    var label: String {
        switch self {
        case .idle:         return "Idle"
        case .scanning:     return "Scanning for sensor…"
        case .connecting:   return "Connecting…"
        case .discovering:  return "Discovering services…"
        case .subscribing:  return "Subscribing to glucose…"
        case .streaming:    return "Streaming live glucose"
        case .failed(let m): return "Failed — \(m)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .subscribing: return true
        default: return false
        }
    }
}

/// One line in the on-screen diagnostic log (what the GATT actually did).
struct CGMLogEntry: Identifiable, Hashable {
    enum Level { case info, good, warn, error, data }
    let id = UUID()
    let date: Date
    let level: Level
    let message: String
}

// MARK: - Connection manager

@Observable
final class CGMConnectionManager: NSObject {

    // MARK: Published state

    private(set) var connectionState: CGMConnectionState = .idle
    /// Newest GATT-decoded reading.
    private(set) var latest: GlucoseSample?
    /// Rolling history (newest last), capped.
    private(set) var history: [GlucoseSample] = []
    /// The advertisement-decoded value (AiDEXDecoder), captured during the scan so we
    /// can CROSS-CHECK that the GATT SFLOAT agrees with the broadcast value.
    private(set) var advertReading: AiDEXReading?
    /// CoreBluetooth manager state mirror.
    private(set) var managerState: CBManagerState = .unknown
    /// Diagnostic log — newest last. The first live test reads top-to-bottom here.
    private(set) var log: [CGMLogEntry] = []
    /// CGM Feature flags note (E2E-CRC etc.), nil until 0x2AA8 is read.
    private(set) var featureNote: String?
    /// True if CGM Feature bit 12 (E2E-CRC) is set → measurements carry a trailing CRC.
    private(set) var e2eCRCPresent = false

    /// Trend from the last two GATT samples (±2 mg/dL deadband).
    var trend: LiveGlucoseTrend? {
        guard history.count >= 2 else { return nil }
        let delta = history[history.count - 1].mgdl - history[history.count - 2].mgdl
        if delta > 2 { return .up }
        if delta < -2 { return .down }
        return .flat
    }

    /// Whether the GATT value and the advertisement value currently agree (±6 mg/dL).
    /// nil if we don't have both. This is the confidence check for the first test.
    var crossCheckAgrees: Bool? {
        guard let g = latest?.mgdl, let a = advertReading?.mgdl else { return nil }
        return abs(g - a) <= 6
    }

    var stateDescription: String {
        switch managerState {
        case .poweredOn:    return connectionState.label
        case .poweredOff:   return "Bluetooth is off — turn it on in Control Center"
        case .unauthorized: return "Bluetooth permission denied — allow it in Settings"
        case .unsupported:  return "Bluetooth LE not supported on this device"
        case .resetting:    return "Bluetooth resetting…"
        case .unknown:      return "Starting Bluetooth…"
        @unknown default:   return "Bluetooth unavailable"
        }
    }

    // MARK: GATT UUIDs (standard CGM Service)

    static let cgmService          = CBUUID(string: "181F")
    static let cgmMeasurement      = CBUUID(string: "2AA7") // NOTIFY — glucose
    static let cgmFeature          = CBUUID(string: "2AA8") // READ   — feature flags
    static let cgmStatus           = CBUUID(string: "2AA9") // READ
    static let cgmSessionStartTime = CBUUID(string: "2AAA") // READ/WRITE
    static let cgmSessionRunTime   = CBUUID(string: "2AAB") // READ
    static let racp                = CBUUID(string: "2A52") // WRITE/INDICATE (phase 2)
    static let socp                = CBUUID(string: "2AAC") // WRITE/INDICATE — Start Session

    /// SOCP Start Session opcode and its success indication ("1C 1A 01").
    private static let socpStartSession: UInt8 = 0x1A
    private static let socpResponseOpcode: UInt8 = 0x1C
    private static let socpSuccess: UInt8 = 0x01

    // MARK: Private

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    /// A specific peripheral identifier to retrieve (if we already know it).
    private var targetIdentifier: UUID?

    /// CoreBluetooth state-restoration identifier. Passing this when creating the
    /// central lets iOS RELAUNCH the app into the background (after it has been
    /// suspended/terminated) to keep delivering glucose notifications — this is what
    /// makes background CGM actually survive app suspension. iOS calls
    /// `centralManager(_:willRestoreState:)` on relaunch with the peripheral(s) we
    /// were connected to, which we re-wire below.
    private static let restoreIdentifier = "com.parikshit.span.cgm.central"

    // MARK: Reading callback (wiring to GlucoseStore + GlucoseAlertManager)

    /// Forward each newly-parsed reading to whoever owns persistence + alerts.
    /// CGMView sets this closure so the connection manager stays decoupled from the
    /// store/alert managers (no tight references, no retain cycles to manage here).
    var onReading: ((GlucoseSample) -> Void)?

    // Discovered characteristics.
    private var measurementChar: CBCharacteristic?
    private var featureChar: CBCharacteristic?
    private var sessionStartChar: CBCharacteristic?
    private var socpChar: CBCharacteristic?

    /// True while the user wants a live stream (drives auto-reconnect on drop).
    private var streamDesired = false
    /// Reconnect backoff (seconds), grows on repeated drops.
    private var reconnectDelay: TimeInterval = 1
    private var reconnectWorkItem: DispatchWorkItem?

    /// Fallback timer: if no 0x2AA7 notification arrives within this window after
    /// subscribing, kick the session-start sequence.
    private var sessionStartTimer: Timer?
    private static let sessionStartTimeout: TimeInterval = 10
    /// Set once we've already tried the session-start fallback this connection.
    private var triedSessionStart = false
    /// Set once at least one measurement notification has been parsed this connection.
    private var gotMeasurement = false

    private static let maxHistory = 720 // ~3h at 1 reading / 15s, plenty for a chart.

    // MARK: Lifecycle

    override init() {
        super.init()
        // Central created lazily on connect() so opening the tab doesn't prompt.
    }

    /// Pre-load a known peripheral identifier (e.g. one matched by the passive scan).
    /// Connecting later will `retrievePeripherals` it directly — no scan needed.
    func setTarget(identifier: UUID) {
        targetIdentifier = identifier
    }

    /// Seed the advertisement cross-check value (call from the passive scan when the
    /// likely sensor is decoded, so the Connect view can compare GATT vs advert).
    func setAdvertReading(_ reading: AiDEXReading?) {
        advertReading = reading
    }

    // MARK: Public control

    /// Begin: power-check → retrieve-or-scan → connect → discover → subscribe.
    func connect() {
        streamDesired = true
        reconnectDelay = 1
        if central == nil {
            // Create with a state-restoration identifier so iOS can relaunch us into
            // the background to keep glucose flowing across app suspension/termination.
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
            // didUpdateState will drive the first action once powered on.
            return
        }
        startFlow()
    }

    /// Tear down: stop scanning, cancel the connection, stop auto-reconnect.
    func disconnect() {
        streamDesired = false
        cancelReconnect()
        sessionStartTimer?.invalidate(); sessionStartTimer = nil
        if central?.isScanning == true { central?.stopScan() }
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        connectionState = .idle
        addLog("Disconnected by user.", .info)
    }

    // MARK: Flow

    private func startFlow() {
        guard let central, central.state == .poweredOn else {
            addLog("Waiting for Bluetooth to power on…", .info)
            return
        }
        // Reset per-connection flags.
        triedSessionStart = false
        gotMeasurement = false
        measurementChar = nil; featureChar = nil; sessionStartChar = nil; socpChar = nil

        // 1) If we know the peripheral, retrieve it directly (no scan needed).
        if let id = targetIdentifier,
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            addLog("Retrieved known peripheral \(short(id)). Connecting…", .info)
            beginConnect(to: known)
            return
        }
        // 2) Otherwise, also try anything iOS has already connected with the CGM service.
        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.cgmService]).first {
            addLog("Found system-connected CGM peripheral \(short(connected.identifier)). Connecting…", .info)
            beginConnect(to: connected)
            return
        }
        // 3) Scan and match by service 0x181F or name prefix "RXC-".
        connectionState = .scanning
        addLog("Scanning for CGM service 0x181F / name prefix \"RXC-\"…", .info)
        central.scanForPeripherals(
            withServices: [Self.cgmService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        // Also run an unfiltered fallback scan in case the sensor doesn't advertise
        // the service UUID in its advert (some firmwares only put it in the GATT).
        // We match those by the "RXC-" name in didDiscover.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func beginConnect(to p: CBPeripheral) {
        if central?.isScanning == true { central?.stopScan() }
        peripheral = p
        p.delegate = self
        connectionState = .connecting
        central?.connect(p, options: nil)
    }

    // MARK: Session-start fallback

    private func armSessionStartTimer() {
        sessionStartTimer?.invalidate()
        sessionStartTimer = Timer.scheduledTimer(withTimeInterval: Self.sessionStartTimeout,
                                                 repeats: false) { [weak self] _ in
            self?.runSessionStartFallback()
        }
    }

    /// No glucose notification within the timeout → the data session likely isn't
    /// running. Per spec: write the current time to Session Start Time (0x2AAA) and
    /// write Start Session (0x1A) to the SOCP (0x2AAC) whose indications we enabled.
    private func runSessionStartFallback() {
        guard streamDesired, !gotMeasurement, !triedSessionStart else { return }
        triedSessionStart = true
        addLog("No glucose in \(Int(Self.sessionStartTimeout))s — running session-start fallback.", .warn)

        if let p = peripheral, let startChar = sessionStartChar {
            let bytes = Self.sessionStartTimeBytes(Date())
            addLog("WRITE Session Start Time 0x2AAA ← \(hex(bytes))", .info)
            p.writeValue(Data(bytes), for: startChar, type: .withResponse)
        } else {
            addLog("Session Start Time 0x2AAA not found — skipping time write.", .warn)
        }

        if let p = peripheral, let socp = socpChar {
            let op = Data([Self.socpStartSession])
            addLog("WRITE SOCP 0x2AAC ← \(hex([Self.socpStartSession])) (Start Session)", .info)
            p.writeValue(op, for: socp, type: .withResponse)
        } else {
            addLog("SOCP 0x2AAC not found — cannot send Start Session.", .warn)
        }
        // Give the sensor a moment, then re-arm one last watchdog window.
        sessionStartTimer = Timer.scheduledTimer(withTimeInterval: Self.sessionStartTimeout,
                                                 repeats: false) { [weak self] _ in
            guard let self, self.streamDesired, !self.gotMeasurement else { return }
            self.addLog("Still no glucose after session-start. Check the sensor is awake and the Vixxa app is closed.", .warn)
        }
    }

    // MARK: SFLOAT + record parsing

    /// Decode an IEEE-11073 16-bit SFLOAT from two little-endian bytes.
    /// High nibble of the high byte = signed 4-bit exponent (two's complement);
    /// low 12 bits = signed mantissa (two's complement). value = mantissa·10^exp.
    /// Returns nil for the reserved NaN / NRes / +Inf / -Inf special values.
    static func parseSFloat(_ lo: UInt8, _ hi: UInt8) -> Double? {
        let raw = UInt16(lo) | (UInt16(hi) << 8)

        // 12-bit mantissa (low 12 bits), sign-extended from bit 11.
        var mantissa = Int(raw & 0x0FFF)
        if mantissa >= 0x0800 { mantissa -= 0x1000 }

        // 4-bit exponent (high nibble), sign-extended from bit 3.
        var exponent = Int((raw >> 12) & 0x000F)
        if exponent >= 0x0008 { exponent -= 0x10 }

        // Reserved special values (mantissa codes with exponent 0):
        //   0x07FF NaN, 0x0800 NRes, 0x07FE +Inf, 0x0802 -Inf, 0x0801 reserved.
        if exponent == 0 {
            switch mantissa {
            case 0x07FF, -2048, 2046, -2046, -2047: return nil
            default: break
            }
        }
        return Double(mantissa) * pow(10.0, Double(exponent))
    }

    /// Parse a CGM Measurement record. Returns the glucose mg/dL and the time offset
    /// (minutes since session start), or nil if the record is malformed.
    /// Layout: [Size][Flags][Glucose SFLOAT @2..3 LE][TimeOffset uint16 @4..5 LE]...
    static func parseMeasurement(_ data: Data) -> (mgdl: Double, timeOffsetMin: Int)? {
        let b = [UInt8](data)
        // Need at least Size+Flags+SFLOAT+TimeOffset = 6 bytes.
        guard b.count >= 6 else { return nil }
        guard let mgdl = parseSFloat(b[2], b[3]) else { return nil }
        let offset = Int(UInt16(b[4]) | (UInt16(b[5]) << 8))
        return (mgdl, offset)
    }

    /// Build the CGM Session Start Time value: a 9-byte SIG date-time-with-DST-offset
    /// (year LE uint16, month, day, hours, minutes, seconds, time-zone, dst-offset).
    /// We write "now" so the sensor anchors time-offsets to this moment.
    static func sessionStartTimeBytes(_ date: Date) -> [UInt8] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(c.year ?? 2000)
        // Time Zone: in 15-minute steps as a signed int8.
        let tzQuarters = Int8(clamping: (TimeZone.current.secondsFromGMT(for: date) / 900))
        // DST offset enum: 0 = standard, 4 = +1h DST (0x04). Approximate from isDST.
        let dst: UInt8 = TimeZone.current.isDaylightSavingTime(for: date) ? 0x04 : 0x00
        return [
            UInt8(year & 0xFF), UInt8((year >> 8) & 0xFF),
            UInt8(c.month ?? 1), UInt8(c.day ?? 1),
            UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0),
            UInt8(bitPattern: tzQuarters), dst
        ]
    }

    // MARK: Recording a reading

    private func record(_ sample: GlucoseSample) {
        latest = sample
        history.append(sample)
        if history.count > Self.maxHistory { history.removeFirst(history.count - Self.maxHistory) }
        // Forward to persistence (GlucoseStore) + highs/lows (GlucoseAlertManager).
        // Fires even when the app is backgrounded, since notifications/parsing run on
        // delivered BLE events. The closure is set by CGMView.
        onReading?(sample)
    }

    // MARK: Reconnect

    private func scheduleReconnect() {
        guard streamDesired else { return }
        cancelReconnect()
        let delay = reconnectDelay
        addLog(String(format: "Reconnecting in %.0fs…", delay), .info)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.streamDesired else { return }
            self.startFlow()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        reconnectDelay = min(reconnectDelay * 2, 30) // cap backoff at 30s.
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    // MARK: Logging helpers

    func clearLog() { log.removeAll() }

    private func addLog(_ message: String, _ level: CGMLogEntry.Level) {
        let entry = CGMLogEntry(date: Date(), level: level, message: message)
        log.append(entry)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    private func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}

// MARK: - CBCentralManagerDelegate

extension CGMConnectionManager: CBCentralManagerDelegate {

    /// STATE RESTORATION: iOS relaunched the app into the background (it had been
    /// suspended/terminated) and is handing back the CoreBluetooth objects it kept
    /// alive on our behalf. We re-wire the peripheral we were connected to so the
    /// existing subscription keeps delivering glucose without a fresh scan. This is
    /// the half of background CGM that survives the app being killed; the central is
    /// recreated by the system here (NOT via our connect()), so we mark the stream as
    /// desired and adopt the restored peripheral.
    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        self.central = central
        central.delegate = self
        streamDesired = true
        addLog("State restoration: iOS relaunched Span in the background for CGM.", .info)

        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        if let p = restored.first(where: { $0.identifier == targetIdentifier }) ?? restored.first {
            peripheral = p
            targetIdentifier = p.identifier
            p.delegate = self
            // Re-discover the chars so measurementChar etc. point at the restored
            // service objects (the old references are stale across relaunch).
            measurementChar = nil; featureChar = nil; sessionStartChar = nil; socpChar = nil
            addLog("Restored peripheral \(short(p.identifier)) (state \(p.state.rawValue)). Re-wiring…", .good)
            if p.state == .connected {
                connectionState = .discovering
                p.discoverServices([Self.cgmService])
            } else {
                connectionState = .connecting
                central.connect(p, options: nil)
            }
        } else {
            addLog("State restoration carried no peripheral — will rescan once powered on.", .warn)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        managerState = central.state
        switch central.state {
        case .poweredOn:
            addLog("Bluetooth powered on.", .good)
            if streamDesired { startFlow() }
        case .poweredOff:
            connectionState = .failed("Bluetooth is off")
            addLog("Bluetooth is off.", .error)
        case .unauthorized:
            connectionState = .failed("Bluetooth permission denied")
            addLog("Bluetooth permission denied — allow it in Settings.", .error)
        case .unsupported:
            connectionState = .failed("BLE unsupported")
            addLog("Bluetooth LE unsupported on this device.", .error)
        case .resetting:
            addLog("Bluetooth resetting…", .warn)
        case .unknown:
            addLog("Bluetooth state unknown…", .info)
        @unknown default:
            addLog("Bluetooth state unavailable.", .warn)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // Match by advertised CGM service 0x181F or by name prefix "RXC-".
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let serviceMatch = advServices.contains(Self.cgmService)
        let nameMatch = advName.uppercased().hasPrefix("RXC-")
        guard serviceMatch || nameMatch else { return }

        // CROSS-CHECK: decode the advert glucose now so the UI can compare GATT vs advert.
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            let mfgHex = mfg.map { String(format: "%02X", $0) }.joined()
            if let reading = AiDEXDecoder.decode(manufacturerHex: mfgHex) {
                advertReading = reading
                addLog("Advert cross-check: \(Int(reading.mgdl)) mg/dL decoded from broadcast.", .data)
            }
        }

        addLog("Matched sensor \"\(advName.isEmpty ? "RXC-?" : advName)\" \(short(peripheral.identifier)) (\(serviceMatch ? "service 0x181F" : "name RXC-"), \(RSSI) dBm).", .good)
        targetIdentifier = peripheral.identifier
        beginConnect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .discovering
        addLog("Connected. Discovering CGM service 0x181F…", .good)
        peripheral.discoverServices([Self.cgmService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        connectionState = .failed("Connect failed: \(msg)")
        addLog("Failed to connect: \(msg)", .error)
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        sessionStartTimer?.invalidate(); sessionStartTimer = nil
        if let error {
            addLog("Disconnected: \(error.localizedDescription)", .warn)
        } else {
            addLog("Disconnected.", .info)
        }
        if streamDesired {
            connectionState = .connecting
            scheduleReconnect()
        } else {
            connectionState = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension CGMConnectionManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .failed("Service discovery: \(error.localizedDescription)")
            addLog("Service discovery error: \(error.localizedDescription)", .error)
            return
        }
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.cgmService }) else {
            connectionState = .failed("CGM service 0x181F not found")
            addLog("CGM service 0x181F NOT found on this peripheral. Services: \(peripheral.services?.map { $0.uuid.uuidString }.joined(separator: ", ") ?? "none")", .error)
            return
        }
        addLog("Found CGM service 0x181F. Discovering characteristics…", .good)
        peripheral.discoverCharacteristics([
            Self.cgmMeasurement, Self.cgmFeature, Self.cgmStatus,
            Self.cgmSessionStartTime, Self.cgmSessionRunTime, Self.racp, Self.socp
        ], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionState = .failed("Characteristic discovery: \(error.localizedDescription)")
            addLog("Characteristic discovery error: \(error.localizedDescription)", .error)
            return
        }
        let chars = service.characteristics ?? []
        addLog("Discovered \(chars.count) characteristics: \(chars.map { $0.uuid.uuidString }.joined(separator: ", "))", .info)

        for c in chars {
            switch c.uuid {
            case Self.cgmMeasurement:      measurementChar = c
            case Self.cgmFeature:          featureChar = c
            case Self.cgmSessionStartTime: sessionStartChar = c
            case Self.socp:                socpChar = c
            default: break
            }
        }

        // Read CGM Feature first (E2E-CRC bit 12 changes how we parse measurements).
        if let f = featureChar {
            addLog("READ CGM Feature 0x2AA8…", .info)
            peripheral.readValue(for: f)
        } else {
            addLog("CGM Feature 0x2AA8 not found — assuming no E2E-CRC.", .warn)
        }

        // Enable SOCP indications up-front so the session-start fallback can hear
        // its "1C 1A 01" response if we need it.
        if let socp = socpChar {
            addLog("Enabling indications on SOCP 0x2AAC…", .info)
            peripheral.setNotifyValue(true, for: socp)
        }

        // THE MAIN EVENT: subscribe to CGM Measurement notifications (glucose stream).
        // On iOS this (encrypted) subscribe auto-triggers pairing if needed; an
        // existing OS-level Vixxa bond is reused transparently.
        guard let m = measurementChar else {
            connectionState = .failed("CGM Measurement 0x2AA7 not found")
            addLog("CGM Measurement 0x2AA7 NOT found — cannot stream glucose.", .error)
            return
        }
        connectionState = .subscribing
        addLog("Subscribing to CGM Measurement 0x2AA7 notifications…", .info)
        peripheral.setNotifyValue(true, for: m)

        // ROBUSTNESS: the subscribe callback can hang silently if the encrypted
        // characteristic needs pairing the sensor won't complete. Arm the
        // session-start watchdog NOW (not only after a successful subscribe), so
        // the fallback still runs even if didUpdateNotificationStateFor never fires.
        armSessionStartTimer()
        addLog("Armed \(Int(Self.sessionStartTimeout))s watchdog (fires session-start if no glucose / no subscribe callback).", .info)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            // A pairing-required / insufficient-encryption error surfaces here.
            addLog("Notify-enable error on \(characteristic.uuid.uuidString): \(error.localizedDescription)", .error)
            if characteristic.uuid == Self.cgmMeasurement {
                connectionState = .failed("Subscribe failed: \(error.localizedDescription)")
            }
            return
        }
        if characteristic.uuid == Self.cgmMeasurement {
            addLog("Subscribed to 0x2AA7. Waiting for glucose notifications…", .good)
            // Start the watchdog: if no glucose arrives, run the session-start fallback.
            armSessionStartTimer()
        } else if characteristic.uuid == Self.socp {
            addLog("SOCP 0x2AAC indications enabled.", .info)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            addLog("Read/notify error on \(characteristic.uuid.uuidString): \(error.localizedDescription)", .error)
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case Self.cgmMeasurement:
            handleMeasurement(data)

        case Self.cgmFeature:
            handleFeature(data)

        case Self.socp:
            handleSOCPResponse(data)

        case Self.cgmStatus:
            addLog("CGM Status 0x2AA9 = \(hex(data))", .data)

        default:
            addLog("Value for \(characteristic.uuid.uuidString) = \(hex(data))", .data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            addLog("WRITE failed on \(characteristic.uuid.uuidString): \(error.localizedDescription)", .error)
        } else {
            addLog("WRITE ack on \(characteristic.uuid.uuidString).", .good)
        }
    }

    // MARK: Characteristic handlers

    private func handleMeasurement(_ data: Data) {
        addLog("NOTIFY 0x2AA7 raw = \(hex(data))", .data)
        guard let parsed = Self.parseMeasurement(data) else {
            addLog("Could not parse CGM Measurement record (len \(data.count)).", .warn)
            return
        }
        // Plausibility guard so a malformed record never fabricates a number.
        guard parsed.mgdl >= 20, parsed.mgdl <= 600 else {
            addLog(String(format: "Parsed glucose %.0f mg/dL out of range — ignoring.", parsed.mgdl), .warn)
            return
        }
        gotMeasurement = true
        sessionStartTimer?.invalidate(); sessionStartTimer = nil
        reconnectDelay = 1 // healthy stream → reset backoff.

        let sample = GlucoseSample(mgdl: parsed.mgdl, date: Date(), timeOffsetMin: parsed.timeOffsetMin)
        record(sample)
        connectionState = .streaming

        var line = String(format: "Glucose %.0f mg/dL (%.1f mmol/L), +%d min", sample.mgdl, sample.mmol, parsed.timeOffsetMin)
        if let agree = crossCheckAgrees {
            line += agree ? "  ✓ matches advert" : "  ⚠︎ differs from advert"
        }
        addLog(line, .good)
    }

    private func handleFeature(_ data: Data) {
        addLog("CGM Feature 0x2AA8 = \(hex(data))", .data)
        // Feature field is a 24-bit (3-byte) little-endian bitmask, then type/sample
        // location nibble byte + E2E-CRC. We only need bit 12 (E2E-CRC supported).
        let b = [UInt8](data)
        guard b.count >= 3 else {
            featureNote = "Feature field too short."
            return
        }
        let features = UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16)
        e2eCRCPresent = (features & (1 << 12)) != 0
        featureNote = e2eCRCPresent
            ? "E2E-CRC supported (bit 12) — measurements carry a trailing uint16 CRC."
            : "E2E-CRC not supported — measurements have no trailing CRC."
        addLog(featureNote ?? "", e2eCRCPresent ? .warn : .info)
    }

    private func handleSOCPResponse(_ data: Data) {
        let b = [UInt8](data)
        addLog("INDICATE SOCP 0x2AAC = \(hex(data))", .data)
        // Success looks like "1C 1A 01" (Response code, request opcode = Start Session, success).
        if b.count >= 3,
           b[0] == Self.socpResponseOpcode,
           b[1] == Self.socpStartSession,
           b[2] == Self.socpSuccess {
            addLog("Session started successfully (1C 1A 01). Glucose should now stream.", .good)
        } else if b.count >= 3, b[0] == Self.socpResponseOpcode {
            addLog("SOCP response opcode 0x\(String(format: "%02X", b[1])) result 0x\(String(format: "%02X", b[2])).", .warn)
        }
    }
}
