//
//  BluetoothScanManager.swift
//  Span — CGM diagnostic probe (Probe B: BLE advertisement reconnaissance).
//
//  ISOLATED probe. PASSIVE SCAN ONLY. We scan for ALL peripherals (no service
//  filter, because we do not know the Vixxa/AiDEX service UUID) and record what
//  each device ADVERTISES — name, identifier, RSSI, advertised service UUIDs, and
//  manufacturer data. We NEVER connect, NEVER discover services, NEVER read/write
//  characteristics, NEVER pair, NEVER decrypt. There is no "Inspect GATT" path.
//
//  The goal is purely to see whether a device that looks like the sensor
//  (Vixxa / GlucoRx / AiDEX / LinX / MicroTech / serial-looking name) shows up in
//  the air at all. The Vixxa sensor typically only advertises when the official
//  app is NOT holding the connection.
//

import Foundation
import CoreBluetooth
import Observation

/// One discovered peripheral, flattened from a scan advertisement. Read-only.
struct DiscoveredPeripheral: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    /// Advertised service UUID strings (CBAdvertisementDataServiceUUIDsKey).
    var serviceUUIDs: [String]
    /// Manufacturer-specific data as a hex string (CBAdvertisementDataManufacturerDataKey).
    var manufacturerHex: String?
    /// Heuristic: does the name look like the GlucoRx Vixxa / AiDEX sensor family?
    var isLikelySensor: Bool
    /// Stable position so the list doesn't reorder as RSSI jitters (anti-flicker).
    var firstSeenOrder: Int
    /// How many advertisements we've seen from this device (it's alive if growing).
    var advertCount: Int
    /// Up to the last 20 DISTINCT manufacturer-data hex samples + when seen.
    /// For likely sensors this lets us check if the glucose is encoded in the
    /// advertisement itself (a field that changes as the reading changes).
    var mfgHistory: [String]

    /// 0x0059 little-endian (5900) ⇒ Nordic Semiconductor — surfaced for context.
    var manufacturerName: String? {
        guard let hex = manufacturerHex, hex.count >= 4 else { return nil }
        let companyLE = String(hex.prefix(4))   // first 2 bytes, little-endian
        switch companyLE.uppercased() {
        case "5900": return "Nordic Semiconductor"
        default:     return "Company 0x\(String(companyLE.suffix(2)))\(String(companyLE.prefix(2)))"
        }
    }

    /// Attempt the AiDEX/Vixxa plaintext-advertisement glucose decode on the
    /// latest manufacturer payload. nil unless it decodes to a plausible value.
    /// READ-ONLY — decodes bytes the sensor already broadcasts; no connection.
    var decodedGlucose: AiDEXReading? {
        guard let hex = manufacturerHex else { return nil }
        return AiDEXDecoder.decode(manufacturerHex: hex)
    }
}

@Observable
final class BluetoothScanManager: NSObject {

    // MARK: Published state

    /// Discovered peripherals, sorted by RSSI (strongest first).
    private(set) var peripherals: [DiscoveredPeripheral] = []
    /// Current Core Bluetooth manager state (poweredOn, unauthorized, etc).
    private(set) var state: CBManagerState = .unknown
    /// True while a passive scan is running.
    private(set) var isScanning = false

    /// Human-readable line for the Bluetooth state.
    var stateDescription: String {
        switch state {
        case .poweredOn:   return "Bluetooth ready"
        case .poweredOff:  return "Bluetooth is off — turn it on in Control Center"
        case .unauthorized: return "Bluetooth permission denied — allow it in Settings"
        case .unsupported: return "Bluetooth LE not supported on this device"
        case .resetting:   return "Bluetooth resetting…"
        case .unknown:     return "Bluetooth state unknown…"
        @unknown default:  return "Bluetooth state unavailable"
        }
    }

    // MARK: Private

    private var central: CBCentralManager?
    /// Live store keyed by identifier for O(1) de-dup / RSSI update.
    private var store: [UUID: DiscoveredPeripheral] = [:]
    /// Monotonic counter giving each new device a stable sort position.
    private var seenCounter = 0
    /// Coalesce UI publishes: we mutate `store` on every advert but only push to
    /// `peripherals` on a timer, so the list updates smoothly instead of flickering.
    private var needsPublish = false
    private var publishTimer: Timer?

    /// Name fragments that suggest a GlucoRx Vixxa-family CGM sensor.
    private static let sensorHints = ["vixxa", "glucorx", "aidex", "linx", "microtech"]

    // MARK: Lifecycle

    override init() {
        super.init()
        // Manager is created lazily on first start() so we don't trigger the
        // Bluetooth permission prompt just by opening the tab.
    }

    /// Begin a passive, unfiltered scan. Creates the central on first use.
    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        // If already powered on, start immediately; otherwise the delegate
        // callback (didUpdateState) will start once it powers on.
        if central?.state == .poweredOn {
            beginScan()
        }
        isScanning = true
        startPublishTimer()
    }

    /// Stop scanning. Keeps the already-discovered rows on screen.
    func stop() {
        central?.stopScan()
        isScanning = false
        publishTimer?.invalidate()
        publishTimer = nil
        flush()   // final repaint so the list reflects the last state
    }

    /// Publish coalesced updates ~3×/sec — smooth, not per-packet (anti-flicker).
    private func startPublishTimer() {
        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    /// Live lookup of a discovered peripheral by id (for the calibration sheet,
    /// which wants the freshest payload + mfg history as it updates).
    func peripheral(id: UUID) -> DiscoveredPeripheral? { store[id] }

    /// Rebuild the published array only if something changed, in STABLE order
    /// (by first-seen, not live RSSI) so rows never jump around.
    private func flush() {
        guard needsPublish else { return }
        needsPublish = false
        peripherals = store.values.sorted { $0.firstSeenOrder < $1.firstSeenOrder }
    }

    private func beginScan() {
        // withServices: nil → discover EVERYTHING (we don't know the sensor's UUID).
        // AllowDuplicates lets RSSI refresh as the device moves.
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private static func looksLikeSensor(name: String) -> Bool {
        let lower = name.lowercased()
        if sensorHints.contains(where: { lower.contains($0) }) { return true }
        // Serial-looking: a longish token that is mostly hex/digits (e.g. "A1B2C3D4").
        let compact = name.replacingOccurrences(of: " ", with: "")
        if compact.count >= 6 {
            let alnumHex = compact.allSatisfy { $0.isHexDigit }
            let mostlyDigits = compact.filter(\.isNumber).count >= max(4, compact.count / 2)
            if alnumHex || mostlyDigits { return true }
        }
        return false
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothScanManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn, isScanning {
            beginScan()
        } else if central.state != .poweredOn {
            // Can't scan unless powered on — reflect that in the toggle.
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // PASSIVE: we only read the advertisement. No connect, ever.
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        let name = (advName?.isEmpty == false ? advName! : "Unnamed")

        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString } ?? []

        var manufacturerHex: String?
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            manufacturerHex = hexString(from: mfg)
        }

        let id = peripheral.identifier
        let likely = BluetoothScanManager.looksLikeSensor(name: name)

        if var existing = store[id] {
            // Update in place. Smooth RSSI (EMA) so the number doesn't jitter
            // every packet; enrich fields if this advert carried more.
            existing.rssi = (existing.rssi * 3 + RSSI.intValue) / 4
            existing.advertCount += 1
            if name != "Unnamed" { existing.name = name }
            if !serviceUUIDs.isEmpty { existing.serviceUUIDs = serviceUUIDs }
            if let manufacturerHex {
                existing.manufacturerHex = manufacturerHex
                // Keep a rolling history of DISTINCT mfg-data payloads. If the
                // glucose is encoded in the advertisement, a field here will
                // change over time as the reading changes — that's the tell.
                if existing.mfgHistory.last != manufacturerHex {
                    existing.mfgHistory.append(manufacturerHex)
                    if existing.mfgHistory.count > 20 { existing.mfgHistory.removeFirst() }
                }
            }
            existing.isLikelySensor = existing.isLikelySensor || likely
            store[id] = existing
        } else {
            seenCounter += 1
            store[id] = DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                serviceUUIDs: serviceUUIDs,
                manufacturerHex: manufacturerHex,
                isLikelySensor: likely,
                firstSeenOrder: seenCounter,
                advertCount: 1,
                mfgHistory: manufacturerHex.map { [$0] } ?? []
            )
        }
        needsPublish = true
    }
}
