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
//    glucose(mmol/L) = payload[7] / 10         →  ×18.0182 for mg/dL
//
//  CALIBRATED against the GlucoRx Vixxa (RXC-22222A58G4) on 2026-06-15:
//  payload[7] = 0x36 (54) → 5.4 mmol/L → 97 mg/dL, matching the Vixxa app
//  exactly. NOTE the community aidex.js used payload[10] for the ORIGINAL
//  AiDEX; the Vixxa 2/3 firmware moved the glucose byte to offset 7.
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

    /// Byte offset of the glucose value within the payload (after the 2-byte
    /// company id). Calibrated to 7 for GlucoRx Vixxa; aidex.js used 10.
    static let glucoseOffset = 7

    /// Decode an AiDEX advertisement. `manufacturerHex` is the full hex string
    /// of CBAdvertisementDataManufacturerDataKey (company id included).
    /// Returns nil if the payload doesn't look like a decodable AiDEX reading.
    ///
    /// IMPORTANT: only fires when the company id is Nordic (0x0059 / "5900").
    /// Without this guard the byte-offset heuristic matches unrelated devices
    /// (e.g. a Samsung fridge) whose byte happens to land in the glucose range.
    static func decode(manufacturerHex hex: String) -> AiDEXReading? {
        let bytes = hexToBytes(hex)
        // Need the 2-byte company id + at least payload[0...10].
        guard bytes.count >= 13 else { return nil }

        // HARD GATE: company id must be Nordic (59 00 little-endian). The Vixxa
        // sensor advertises 0x0059; anything else is not our sensor.
        guard bytes[0] == 0x59, bytes[1] == 0x00 else { return nil }

        let payload = Array(bytes.dropFirst(2))
        guard payload.count > Self.glucoseOffset else { return nil }

        // Core field: glucose in mmol/L = payload[glucoseOffset] / 10.
        // Calibrated to offset 7 for the Vixxa firmware (see header note).
        let rawGlucose = Int(payload[Self.glucoseOffset])
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

    /// A candidate decode showing which byte offset / interpretation matches a
    /// known reference reading — used to calibrate the offset for this firmware.
    struct OffsetCandidate: Identifiable {
        let id = UUID()
        let offset: Int          // index into payload (after company id)
        let interpretation: String  // e.g. "byte/10 mmol", "byte mg/dL", "uint16 LE mg/dL"
        let decodedMgdl: Double
        let matchesReference: Bool
    }

    /// Given the full manufacturer hex and a known reference mg/dL (read off the
    /// Vixxa app at the same moment), return every byte/interpretation that lands
    /// near the reference. This is how we find the correct offset for the Vixxa
    /// firmware variant without guessing.
    static func calibrate(manufacturerHex hex: String, referenceMgdl ref: Double) -> [OffsetCandidate] {
        let bytes = hexToBytes(hex)
        guard bytes.count >= 3 else { return [] }
        let payload = Array(bytes.dropFirst(2))   // drop company id
        var out: [OffsetCandidate] = []
        let tol = 6.0  // mg/dL tolerance (CGM vs the exact advert sample)

        for i in payload.indices {
            let b = Double(payload[i])
            // (a) byte interpreted as mmol/L * 10  → mg/dL
            let asMmolX10 = (b / 10.0) * AiDEXReading.mmolToMgdl
            if abs(asMmolX10 - ref) <= tol {
                out.append(.init(offset: i, interpretation: "byte[\(i)]/10 mmol/L",
                                 decodedMgdl: (asMmolX10*10).rounded()/10,
                                 matchesReference: true))
            }
            // (b) byte interpreted directly as mg/dL
            if abs(b - ref) <= tol {
                out.append(.init(offset: i, interpretation: "byte[\(i)] mg/dL",
                                 decodedMgdl: b, matchesReference: true))
            }
            // (c) uint16 little-endian as mg/dL
            if i + 1 < payload.count {
                let u16 = Double(Int(payload[i]) | (Int(payload[i+1]) << 8))
                if abs(u16 - ref) <= tol {
                    out.append(.init(offset: i, interpretation: "uint16LE[\(i)] mg/dL",
                                     decodedMgdl: u16, matchesReference: true))
                }
                // (d) uint16 LE as mmol/L*10
                let u16mmol = (u16/10.0) * AiDEXReading.mmolToMgdl
                if abs(u16mmol - ref) <= tol {
                    out.append(.init(offset: i, interpretation: "uint16LE[\(i)]/10 mmol/L",
                                     decodedMgdl: (u16mmol*10).rounded()/10, matchesReference: true))
                }
            }
        }
        return out
    }

    /// Full payload (after company id) as indexed (offset, byte, hex) for display.
    static func indexedPayload(manufacturerHex hex: String) -> [(offset: Int, value: Int, hex: String)] {
        let bytes = hexToBytes(hex)
        guard bytes.count >= 3 else { return [] }
        return Array(bytes.dropFirst(2)).enumerated().map {
            (offset: $0.offset, value: Int($0.element), hex: String(format: "%02X", $0.element))
        }
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
