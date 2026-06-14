//
//  AiDEXDecoder.swift
//  Span — decode live glucose from the GlucoRx Vixxa / MicroTech AiDEX BLE
//  advertisement manufacturer-data. READ-ONLY: this parses bytes the sensor
//  already broadcasts in the clear; no connection, no pairing, no decryption.
//
//  Recipe from the diabetes community's reverse-engineering of the MicroTech
//  AiDEX family (Juggluco issue #297 / aidex.js), which broadcasts the live
//  reading with no authentication:
//
//    payload = manufacturerData with the leading 2-byte company id (59 00 =
//              Nordic Semiconductor, 0x0059 little-endian) stripped.
//    glucose(mmol/L) = payload[10] / 10        →  ×18.0182 for mg/dL
//    sampleAge(min)  = payload[1]  / 6
//    timestamp       = uint32 LE at payload[2..5]  (+ device epoch)
//    sensorLife      = uint16 LE at payload[6..7] × 300  (seconds remaining)
//    sensorPhase     = payload[9]
//
//  This decoder is intentionally defensive: if the payload is too short or the
//  decoded value is implausible, it returns nil rather than a wrong number.
//  Confirm the decoded value against the official Vixxa app before trusting it.
//

import Foundation

/// One decoded glucose reading from an AiDEX-family advertisement.
struct AiDEXReading: Equatable {
    let mgdl: Double
    let mmol: Double
    /// Minutes since the sensor took this sample (from payload[1]/6).
    let sampleAgeMinutes: Double?
    /// Seconds of sensor life remaining (uint16 × 300), if present.
    let sensorLifeSeconds: Int?
    /// Raw sensor-phase byte (warmup / active / expired vary by firmware).
    let sensorPhase: Int?
    /// The exact bytes this was decoded from, hex — for the on-screen audit.
    let sourceHex: String

    /// mmol/L → mg/dL uses the clinical 18.0182 factor (we decode mmol first).
    static let mmolToMgdl = 18.0182
}

enum AiDEXDecoder {

    /// MicroTech / Nordic company id seen on the Vixxa advert (0x0059).
    static let nordicCompanyIdLE = "5900"

    /// Decode an AiDEX advertisement. `manufacturerHex` is the full hex string
    /// of CBAdvertisementDataManufacturerDataKey (company id included).
    /// Returns nil if the payload doesn't look like a decodable AiDEX reading.
    static func decode(manufacturerHex hex: String) -> AiDEXReading? {
        let bytes = hexToBytes(hex)
        // Need the 2-byte company id + at least payload[0...10].
        guard bytes.count >= 13 else { return nil }

        // Strip the 2-byte company id (Nordic 59 00). We don't hard-require the
        // id to match in case a firmware variant differs, but it should be 5900.
        let payload = Array(bytes.dropFirst(2))
        guard payload.count > 10 else { return nil }

        // Core field: glucose in mmol/L = payload[10] / 10.
        let rawGlucose = Int(payload[10])
        let mmol = Double(rawGlucose) / 10.0
        let mgdl = mmol * AiDEXReading.mmolToMgdl

        // Plausibility guard — physiologic glucose ~2.2–27.8 mmol/L (40–500 mg/dL).
        // A byte that isn't glucose will usually fall outside this; reject it so
        // we never show a fabricated number.
        guard mmol >= 2.0 && mmol <= 30.0 else { return nil }

        let sampleAge = Double(payload[1]) / 6.0
        let sensorLife = payload.count >= 8
            ? Int(payload[6]) | (Int(payload[7]) << 8)
            : nil
        let phase = payload.count >= 10 ? Int(payload[9]) : nil

        return AiDEXReading(
            mgdl: (mgdl * 10).rounded() / 10,
            mmol: (mmol * 10).rounded() / 10,
            sampleAgeMinutes: sampleAge,
            sensorLifeSeconds: sensorLife.map { $0 * 300 },
            sensorPhase: phase,
            sourceHex: hex
        )
    }

    /// Parse a hex string ("5900090800...") into bytes. Tolerates spaces / odd
    /// length by ignoring a trailing nibble.
    static func hexToBytes(_ hex: String) -> [UInt8] {
        let clean = hex.filter { $0.isHexDigit }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while let next = clean.index(idx, offsetBy: 2, limitedBy: clean.endIndex), next <= clean.endIndex {
            if let b = UInt8(clean[idx..<next], radix: 16) { out.append(b) }
            idx = next
            if idx == clean.endIndex { break }
        }
        return out
    }
}
