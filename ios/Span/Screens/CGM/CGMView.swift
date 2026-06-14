//
//  CGMView.swift
//  Span — CGM diagnostic probe tab (ISOLATED).
//
//  One question, two read-only probes:
//    • Probe A (Health): does the GlucoRx Vixxa stack mirror glucose into Apple
//      Health, and under which SOURCE app name? The source name is the answer.
//    • Probe B (Bluetooth): does a sensor-looking device advertise over BLE at all?
//      Passive scan only — never connects/pairs/decrypts.
//
//  Consumes the Span dark design system; touches nothing in Models/ or other
//  screens. @Observable managers injected via @State.
//

import SwiftUI
import CoreBluetooth

struct CGMView: View {
    @State private var glucose = GlucoseHealthKitManager()
    @State private var bluetooth = BluetoothScanManager()
    @State private var probe = 0 // 0 = Health, 1 = Bluetooth

    var body: some View {
        VStack(spacing: 0) {
            SpanNavBar(title: "CGM Probe")

            SpanSegmentedControl(options: ["Health (Glucose)", "Bluetooth"], selection: $probe)
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.gutter)
                .padding(.bottom, SpanSpacing.xs)

            if probe == 0 {
                GlucoseProbeView(manager: glucose)
            } else {
                BluetoothProbeView(manager: bluetooth)
            }

            DisclaimerFooter(
                text: "Read-only reconnaissance · no connecting, no pairing, no decryption."
            )
        }
        .background(SpanColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Probe A: Apple Health (blood glucose)

private struct GlucoseProbeView: View {
    @Bindable var manager: GlucoseHealthKitManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                headerCard

                if manager.samples.isEmpty {
                    emptyState
                } else {
                    SpanSectionLabel("Recent readings")
                    VStack(spacing: SpanSpacing.xs) {
                        ForEach(manager.samples) { reading in
                            ReadingRow(reading: reading)
                        }
                    }
                }

                Button(manager.authRequested ? "Refresh" : "Request access / Refresh") {
                    Task { await manager.requestAndFetch() }
                }
                .spanPrimaryButton(enabled: !manager.isLoading)
                .padding(.top, SpanSpacing.xs)
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
            .padding(.bottom, SpanSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .task {
            // Auto-request on first appearance so the probe is one tap less.
            if !manager.authRequested { await manager.requestAndFetch() }
        }
    }

    // The answer card: most recent value + trend + timestamp + SOURCE name (bold).
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SpanSectionLabel("Most recent")

            if let latest = manager.latest {
                HStack(alignment: .firstTextBaseline, spacing: SpanSpacing.xs) {
                    Text(latest.value, format: .number.precision(.fractionLength(0)))
                        .font(SpanFont.mono(48, weight: .heavy))
                        .foregroundStyle(SpanColor.textPrimary)
                        .kerning(-1.5)
                    Text(latest.unit)
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)
                    if let trend = manager.latestTrend {
                        StatusBadge(
                            text: trend.label,
                            style: .info,
                            systemImage: trend.symbolName
                        )
                    }
                }

                Text(String(format: "%.1f mmol/L", latest.mmol))
                    .font(SpanFont.monoBody)
                    .foregroundStyle(SpanColor.textSecondary)

                Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)

                Divider().overlay(SpanColor.border)

                // THE EXPERIMENT RESULT.
                VStack(alignment: .leading, spacing: 3) {
                    SpanSectionLabel("Source app")
                    Text(latest.sourceName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SpanColor.accent)
                }
            } else {
                Text("—")
                    .font(SpanFont.mono(48, weight: .heavy))
                    .foregroundStyle(SpanColor.textTertiary)
                Text(manager.isLoading ? "Reading Apple Health…" : "No reading yet")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.statusRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            HStack(spacing: SpanSpacing.xs) {
                Image(systemName: "drop")
                    .font(.system(size: 15))
                    .foregroundStyle(SpanColor.textTertiary)
                Text("No glucose readings in Apple Health yet")
                    .font(SpanFont.body)
                    .foregroundStyle(SpanColor.textPrimary)
            }
            Text("The GlucoRx Vixxa app must mirror readings into Apple Health for this path to work — open the Vixxa app and enable its Apple Health / write-to-Health setting, then refresh.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }
}

/// One glucose reading row: value mg/dL + small mmol/L + timestamp + source name.
private struct ReadingRow: View {
    let reading: GlucoseReading

    var body: some View {
        HStack(alignment: .center, spacing: SpanSpacing.gutter) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.value, format: .number.precision(.fractionLength(0)))
                        .font(SpanFont.monoValue)
                        .foregroundStyle(SpanColor.textPrimary)
                    Text("mg/dL")
                        .font(SpanFont.caption)
                        .foregroundStyle(SpanColor.textTertiary)
                    Text(String(format: "· %.1f mmol/L", reading.mmol))
                        .font(SpanFont.caption)
                        .foregroundStyle(SpanColor.textTertiary)
                }
                Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                    .font(SpanFont.caption)
                    .foregroundStyle(SpanColor.textSecondary)
            }
            Spacer()
            Text(reading.sourceName)
                .font(SpanFont.caption)
                .foregroundStyle(SpanColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .spanCard(padding: SpanSpacing.gutter)
    }
}

// MARK: - Probe B: Bluetooth advertisement reconnaissance

private struct BluetoothProbeView: View {
    @Bindable var manager: BluetoothScanManager
    @State private var calibrating: DiscoveredPeripheral?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                instructionBanner

                HStack {
                    Text(manager.stateDescription)
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)
                    Spacer()
                    SpanToggle(isOn: Binding(
                        get: { manager.isScanning },
                        set: { $0 ? manager.start() : manager.stop() }
                    ))
                }
                .padding(.horizontal, 2)

                if manager.peripherals.isEmpty {
                    Text(manager.isScanning
                         ? "Scanning… no devices seen yet."
                         : "Toggle scanning on to listen for nearby BLE advertisements.")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .spanCard()
                } else {
                    SpanSectionLabel("Discovered (\(manager.peripherals.count))")
                    VStack(spacing: SpanSpacing.xs) {
                        ForEach(manager.peripherals) { p in
                            PeripheralRow(peripheral: p)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Tap a sensor row to open the calibration tool.
                                    if p.manufacturerHex != nil { calibrating = p }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
            .padding(.bottom, SpanSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .onDisappear { manager.stop() }
        .sheet(item: $calibrating) { p in
            // Re-fetch live so the sheet sees the latest payload/history as it updates.
            CalibrationView(manager: manager, peripheralID: p.id)
        }
    }

    private var instructionBanner: some View {
        HStack(alignment: .top, spacing: SpanSpacing.xs) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15))
                .foregroundStyle(SpanColor.accent)
            Text("The sensor may only advertise when the official app is NOT connected. Force-quit the Vixxa app, then watch for a device named Vixxa, GlucoRx, AiDEX or MicroTech.")
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SpanSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpanColor.accentBg, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous)
                .strokeBorder(SpanColor.accentBorder, lineWidth: SpanSpacing.hairline)
        )
    }
}

/// One discovered peripheral. Sensor-looking rows are highlighted in accent + glow.
private struct PeripheralRow: View {
    let peripheral: DiscoveredPeripheral

    private var shortID: String { String(peripheral.id.uuidString.prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(peripheral.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(peripheral.isLikelySensor ? SpanColor.statusGreen : SpanColor.textPrimary)
                    .lineLimit(1)
                if peripheral.isLikelySensor {
                    StatusBadge(text: "Likely sensor", style: .optimal, systemImage: "sparkles")
                }
                Spacer()
                Text("\(peripheral.rssi) dBm")
                    .font(SpanFont.monoBody)
                    .foregroundStyle(SpanColor.textSecondary)
            }

            Text("ID \(shortID)…")
                .font(SpanFont.caption)
                .foregroundStyle(SpanColor.textTertiary)

            // DECODED GLUCOSE — the experiment payoff. If the advertisement's
            // manufacturer-data decodes to a plausible AiDEX reading, show it big.
            // Compare this against the Vixxa app to confirm the decode is correct.
            if let g = peripheral.decodedGlucose {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(g.mgdl.formatted(.number.precision(.fractionLength(0))))
                        .font(SpanFont.mono(34, weight: .heavy))
                        .foregroundStyle(SpanColor.statusGreen)
                    Text("mg/dL")
                        .font(SpanFont.caption)
                        .foregroundStyle(SpanColor.textSecondary)
                    Text("· \(g.mmol.formatted(.number.precision(.fractionLength(1)))) mmol/L")
                        .font(SpanFont.caption)
                        .foregroundStyle(SpanColor.textTertiary)
                    Spacer()
                }
                .padding(.top, 2)
                Text("Decoded from advertisement · verify against Vixxa app"
                     + (g.sampleAgeMinutes.map { String(format: " · %.0f min ago", $0) } ?? ""))
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
            }

            if !peripheral.serviceUUIDs.isEmpty {
                Text("Services: \(peripheral.serviceUUIDs.joined(separator: ", "))")
                    .font(SpanFont.caption)
                    .foregroundStyle(SpanColor.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let hex = peripheral.manufacturerHex {
                Text("Mfg: \(hex)")
                    .font(SpanFont.mono(10, weight: .regular))
                    .foregroundStyle(SpanColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard(
            padding: SpanSpacing.gutter,
            fill: peripheral.isLikelySensor ? SpanColor.statusGreenBg : SpanColor.surfaceCard,
            border: peripheral.isLikelySensor ? SpanColor.statusGreenBorder : SpanColor.border
        )
        .spanGlow(peripheral.isLikelySensor ? SpanColor.statusGreen : .clear,
                  radius: 8,
                  opacity: peripheral.isLikelySensor ? 0.45 : 0)
    }
}

// MARK: - Calibration (find the glucose byte offset for this firmware)

/// Tap a sensor → enter the value the Vixxa app shows → this finds which byte /
/// interpretation in the FULL (untruncated) advertisement payload matches, across
/// every distinct payload we've captured. Removes all offset guesswork.
private struct CalibrationView: View {
    @Bindable var manager: BluetoothScanManager
    let peripheralID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""

    private var peripheral: DiscoveredPeripheral? { manager.peripheral(id: peripheralID) }
    private var refMgdl: Double? { Double(reference) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpanSpacing.md) {
                    Text("Enter the glucose the Vixxa app shows right now. We'll find which byte in the broadcast matches — across every distinct payload captured.")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textSecondary)

                    HStack {
                        Text("Vixxa reading (mg/dL)")
                            .font(SpanFont.callout).foregroundStyle(SpanColor.textPrimary)
                        Spacer()
                        TextField("97", text: $reference)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(SpanFont.monoValue)
                            .foregroundStyle(SpanColor.statusGreen)
                            .frame(width: 90)
                    }
                    .padding(SpanSpacing.gutter)
                    .spanCard()

                    if let p = peripheral {
                        // Run calibration over the latest payload + the distinct history.
                        let payloads = ([p.manufacturerHex].compactMap { $0 } + p.mfgHistory)
                        let distinct = Array(Set(payloads))

                        if let ref = refMgdl {
                            let matches = distinct.flatMap { hex in
                                AiDEXDecoder.calibrate(manufacturerHex: hex, referenceMgdl: ref)
                            }
                            SpanSectionLabel("Matching offsets (\(matches.count))")
                            if matches.isEmpty {
                                Text("No byte matched \(Int(ref)) mg/dL yet. Keep this open a minute so more payloads accumulate, or re-check the Vixxa value.")
                                    .font(SpanFont.footnote)
                                    .foregroundStyle(SpanColor.statusYellow)
                                    .spanCard()
                            } else {
                                VStack(spacing: SpanSpacing.xs) {
                                    ForEach(matches) { m in
                                        HStack {
                                            Text(m.interpretation)
                                                .font(SpanFont.mono(13, weight: .semibold))
                                                .foregroundStyle(SpanColor.statusGreen)
                                            Spacer()
                                            Text("\(m.decodedMgdl.formatted(.number.precision(.fractionLength(0)))) mg/dL")
                                                .font(SpanFont.monoBody)
                                                .foregroundStyle(SpanColor.textSecondary)
                                        }
                                        .padding(SpanSpacing.gutter)
                                        .spanCard(fill: SpanColor.statusGreenBg, border: SpanColor.statusGreenBorder)
                                    }
                                }
                            }
                        }

                        SpanSectionLabel("Latest payload (\(distinct.count) distinct seen)")
                        let idx = AiDEXDecoder.indexedPayload(manufacturerHex: p.manufacturerHex ?? "")
                        // byte grid: offset + hex + decimal, highlight ones matching the ref
                        let target = refMgdl
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                            ForEach(idx, id: \.offset) { cell in
                                let asMmol = Double(cell.value)/10*AiDEXReading.mmolToMgdl
                                let hit = target.map { abs(asMmol - $0) <= 6 || abs(Double(cell.value) - $0) <= 6 } ?? false
                                VStack(spacing: 1) {
                                    Text("\(cell.offset)").font(SpanFont.caption2).foregroundStyle(SpanColor.textTertiary)
                                    Text(cell.hex).font(SpanFont.mono(12, weight: .bold))
                                        .foregroundStyle(hit ? SpanColor.statusGreen : SpanColor.textPrimary)
                                    Text("\(cell.value)").font(SpanFont.caption2).foregroundStyle(SpanColor.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(hit ? SpanColor.statusGreenBg : SpanColor.surfaceCard)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        Text("Full mfg: \(p.manufacturerHex ?? "—")")
                            .font(SpanFont.mono(9, weight: .regular))
                            .foregroundStyle(SpanColor.textTertiary)
                            .textSelection(.enabled)
                    } else {
                        Text("Sensor went quiet — keep the scanner running.")
                            .font(SpanFont.footnote).foregroundStyle(SpanColor.textTertiary)
                    }
                }
                .padding(SpanSpacing.screenH)
            }
            .scrollContentBackground(.hidden)
            .background(SpanColor.background.ignoresSafeArea())
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(SpanColor.accent)
                }
            }
        }
    }
}

#Preview {
    CGMView()
}
