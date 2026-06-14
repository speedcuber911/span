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
    }

    /// Stop scanning. Keeps the already-discovered rows on screen.
    func stop() {
        central?.stopScan()
        isScanning = false
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

    private func resort() {
        peripherals = store.values.sorted { $0.rssi > $1.rssi }
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
            // Update in place — refresh RSSI, and enrich fields if the new advert
            // carried more (some adverts omit the name / services).
            existing.rssi = RSSI.intValue
            if name != "Unnamed" { existing.name = name }
            if !serviceUUIDs.isEmpty { existing.serviceUUIDs = serviceUUIDs }
            if let manufacturerHex { existing.manufacturerHex = manufacturerHex }
            existing.isLikelySensor = existing.isLikelySensor || likely
            store[id] = existing
        } else {
            store[id] = DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                serviceUUIDs: serviceUUIDs,
                manufacturerHex: manufacturerHex,
                isLikelySensor: likely
            )
        }
        resort()
    }
}
