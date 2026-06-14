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
import Charts
import UIKit

struct CGMView: View {
    @State private var glucose = GlucoseHealthKitManager()
    @State private var bluetooth = BluetoothScanManager()
    @State private var connection = CGMConnectionManager()
    // Persistence + alerts live at this level and are injected into the Connect view;
    // the connection manager forwards each reading into them via its `onReading` closure.
    @State private var store = GlucoseStore()
    @State private var alerts = GlucoseAlertManager()
    @State private var probe = 0 // 0 = Health, 1 = Bluetooth, 2 = Connect
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            SpanNavBar(title: "CGM Probe")

            SpanSegmentedControl(options: ["Health (Glucose)", "Bluetooth", "Connect"], selection: $probe)
                .padding(.horizontal, SpanSpacing.screenH)
                .padding(.top, SpanSpacing.gutter)
                .padding(.bottom, SpanSpacing.xs)

            switch probe {
            case 0: GlucoseProbeView(manager: glucose)
            case 1: BluetoothProbeView(manager: bluetooth)
            default: ConnectProbeView(manager: connection, store: store, alerts: alerts)
            }

            DisclaimerFooter(
                text: probe == 2
                    ? "Live CGM reader · connects & reads glucose only; writes only the required session-control."
                    : "Read-only reconnaissance · no connecting, no pairing, no decryption."
            )
        }
        .background(SpanColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // Wire the connection manager → persistence + alerts. Set once; the closure
            // captures the @State managers, which are stable for the view's lifetime.
            connection.onReading = { [store, alerts] sample in
                store.record(sample)
                alerts.evaluate(sample)
            }
            alerts.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            // Persist immediately when leaving the foreground so nothing is lost if the
            // app is suspended/terminated; re-sync auth status on return.
            if phase == .background || phase == .inactive {
                store.flush()
            } else if phase == .active {
                alerts.refreshAuthorizationStatus()
            }
        }
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
    @State private var copied = false

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

                        // Copy ALL distinct payloads (+ ref) so the full untruncated
                        // structure can be analysed off-device.
                        Button {
                            var lines = ["Vixxa=\(reference.isEmpty ? "?" : reference) mg/dL  device=\(p.name)  count=\(distinct.count)"]
                            lines += distinct.sorted().map { "  \($0)" }
                            UIPasteboard.general.string = lines.joined(separator: "\n")
                            copied = true
                        } label: {
                            HStack {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(copied ? "Copied \(distinct.count) payloads" : "Copy all \(distinct.count) payloads")
                            }
                            .font(SpanFont.callout)
                            .foregroundStyle(copied ? SpanColor.statusGreen : SpanColor.accent)
                            .frame(maxWidth: .infinity)
                            .padding(SpanSpacing.gutter)
                            .spanCard(fill: SpanColor.accentBg, border: SpanColor.accentBorder)
                        }

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

// MARK: - Probe C: Connect & read live glucose over GATT

/// Span CONNECTS to the GlucoRx Vixxa sensor (standard CGM Service 0x181F),
/// subscribes to CGM Measurement notifications (0x2AA7), and streams live glucose —
/// making Span a real CGM reader. The diagnostic log shows exactly what the GATT did
/// (services found, subscribe result, whether session-start was needed, raw
/// notification hex + parsed value) so the first live test is fully observable.
private struct ConnectProbeView: View {
    @Bindable var manager: CGMConnectionManager
    @Bindable var store: GlucoseStore
    @Bindable var alerts: GlucoseAlertManager

    private var isStreaming: Bool { manager.connectionState == .streaming }
    private var isBusy: Bool { manager.connectionState.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpanSpacing.md) {
                instructionBanner
                liveCard
                connectControls
                // Diagnostic log directly under the status so the GATT trace is
                // always visible while connecting (no scrolling needed).
                diagnosticLog
                if !store.samples.isEmpty {
                    statsRow
                    trendChartCard
                }
                alertsSection
                if let note = manager.featureNote { featureRow(note) }
            }
            .padding(.horizontal, SpanSpacing.screenH)
            .padding(.top, SpanSpacing.md)
            .padding(.bottom, SpanSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        // NOTE: we deliberately do NOT disconnect on disappear anymore — the whole
        // point of background CGM is to keep streaming when this view (and the app)
        // isn't visible. The user disconnects explicitly via the Disconnect button.
    }

    // Close-the-Vixxa-app instruction — the sensor allows ONE connection at a time.
    private var instructionBanner: some View {
        HStack(alignment: .top, spacing: SpanSpacing.xs) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 15))
                .foregroundStyle(SpanColor.accent)
            Text("Close the Vixxa app first — the sensor allows one connection at a time. Span then owns the link and reads glucose directly over Bluetooth.")
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

    // The big live glucose number (mono, green) once streaming + state line + trend.
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            HStack(spacing: SpanSpacing.xs) {
                stateDot
                Text(manager.stateDescription)
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
                    .lineLimit(2)
                Spacer()
                if isStreaming {
                    StatusBadge(text: "LIVE", style: .optimal, systemImage: "dot.radiowaves.left.and.right")
                }
            }

            if let g = manager.latest {
                HStack(alignment: .firstTextBaseline, spacing: SpanSpacing.xs) {
                    Text(g.mgdl, format: .number.precision(.fractionLength(0)))
                        .font(SpanFont.mono(56, weight: .heavy))
                        .foregroundStyle(isStreaming ? SpanColor.statusGreen : SpanColor.textTertiary)
                        .kerning(-2)
                    Text("mg/dL")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textSecondary)
                    if let trend = manager.trend {
                        StatusBadge(text: trend.label, style: .info, systemImage: trend.symbolName)
                    }
                }
                .spanGlow(isStreaming ? SpanColor.statusGreen : .clear,
                          radius: 12, opacity: isStreaming ? 0.4 : 0)

                Text(String(format: "%.1f mmol/L", g.mmol))
                    .font(SpanFont.monoBody)
                    .foregroundStyle(SpanColor.textSecondary)

                HStack(spacing: SpanSpacing.xs) {
                    Text("Updated \(g.date.formatted(date: .omitted, time: .standard))")
                        .font(SpanFont.footnote)
                        .foregroundStyle(SpanColor.textTertiary)
                    if let off = g.timeOffsetMin {
                        Text("· session +\(off) min")
                            .font(SpanFont.footnote)
                            .foregroundStyle(SpanColor.textTertiary)
                    }
                }

                crossCheckRow
            } else {
                Text("—")
                    .font(SpanFont.mono(56, weight: .heavy))
                    .foregroundStyle(SpanColor.textTertiary)
                Text(isBusy ? "Establishing GATT link…" : "Not connected. Tap Connect to start streaming.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    // A colored dot that mirrors the connection state.
    private var stateDot: some View {
        let color: Color = {
            switch manager.connectionState {
            case .streaming: return SpanColor.statusGreen
            case .failed:    return SpanColor.statusRed
            case .idle:      return SpanColor.textTertiary
            default:         return SpanColor.statusYellow
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .spanGlow(color, radius: 6, opacity: 0.6)
    }

    // CROSS-CHECK: confirm the GATT SFLOAT value matches the advertisement value.
    @ViewBuilder private var crossCheckRow: some View {
        if let advert = manager.advertReading {
            HStack(spacing: 6) {
                Image(systemName: manager.crossCheckAgrees == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(manager.crossCheckAgrees == true ? SpanColor.statusGreen : SpanColor.statusYellow)
                Text("Advert cross-check: \(Int(advert.mgdl)) mg/dL"
                     + (manager.crossCheckAgrees == true ? " · matches GATT" : " · differs from GATT"))
                    .font(SpanFont.caption)
                    .foregroundStyle(SpanColor.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    private var connectControls: some View {
        VStack(spacing: SpanSpacing.xs) {
            if isIdleOrFailed {
                Button("Connect to sensor") { manager.connect() }
                    .spanPrimaryButton()
            } else {
                Button("Disconnect") { manager.disconnect() }
                    .spanGhostButton(tint: SpanColor.statusRed, border: SpanColor.statusRedBorder)
            }
        }
    }

    private var isIdleOrFailed: Bool {
        switch manager.connectionState {
        case .idle, .failed: return true
        default: return false
        }
    }

    // MARK: Stats row (persisted last-24h)

    private var statsRow: some View {
        let s = store.last24hStats
        return VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SpanSectionLabel("Last 24 h · \(s.count) readings")
            HStack(spacing: SpanSpacing.xs) {
                statTile("Latest",
                         store.latest.map { "\(Int($0.mgdl.rounded()))" } ?? "—",
                         color: store.latest.map { zoneColor(for: $0.mgdl) } ?? SpanColor.textTertiary)
                statTile("In range", s.hasData ? "\(Int(s.timeInRangePct.rounded()))%" : "—",
                         color: tirColor(s.timeInRangePct))
                statTile("Avg", s.hasData ? "\(Int(s.average.rounded()))" : "—",
                         color: SpanColor.textPrimary)
            }
            HStack(spacing: SpanSpacing.xs) {
                statTile("Min", s.hasData ? "\(Int(s.min.rounded()))" : "—",
                         color: s.hasData ? zoneColor(for: s.min) : SpanColor.textTertiary)
                statTile("Max", s.hasData ? "\(Int(s.max.rounded()))" : "—",
                         color: s.hasData ? zoneColor(for: s.max) : SpanColor.textTertiary)
                statTile("Trend", trendText, color: SpanColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    private var trendText: String {
        switch store.trend {
        case .up?:   return "Rising"
        case .down?: return "Falling"
        case .flat?: return "Flat"
        case nil:    return "—"
        }
    }

    private func statTile(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).spanSectionHeaderStyle()
            Text(value)
                .font(SpanFont.mono(22, weight: .heavy))
                .foregroundStyle(color)
                .kerning(-0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpanSpacing.gutter)
        .background(SpanColor.surfaceRaised, in: RoundedRectangle(cornerRadius: SpanRadius.small, style: .continuous))
    }

    // MARK: Persisted trend chart (Swift Charts)

    private var trendChartCard: some View {
        let data = store.last24h
        let low = store.latest != nil ? GlucoseStore.inRangeLow : 70
        let high = GlucoseStore.inRangeHigh
        // Y range padded around the data and the threshold band.
        let values = data.map(\.mgdl)
        let yMin = max(0, (values.min() ?? low) - 20)
        let yMax = (values.max() ?? high) + 20

        return VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            SpanSectionLabel("Glucose · last 24 h")
            Chart {
                // In-range band (70–180) tinted green.
                RectangleMark(
                    yStart: .value("low", low),
                    yEnd: .value("high", high)
                )
                .foregroundStyle(SpanColor.statusGreen.opacity(0.08))

                // Threshold rule lines.
                RuleMark(y: .value("High", high))
                    .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
                    .foregroundStyle(SpanColor.statusRed.opacity(0.5))
                RuleMark(y: .value("Low", low))
                    .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
                    .foregroundStyle(SpanColor.accent.opacity(0.5))

                // The reading points, colored by zone.
                ForEach(data) { sample in
                    PointMark(
                        x: .value("Time", sample.date),
                        y: .value("Glucose", sample.mgdl)
                    )
                    .symbolSize(18)
                    .foregroundStyle(zoneColor(for: sample.mgdl))
                }

                // A faint connecting line so the trace reads as a curve.
                ForEach(data) { sample in
                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Glucose", sample.mgdl)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .foregroundStyle(SpanColor.textSecondary.opacity(0.45))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: yMin...yMax)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(SpanColor.border)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                                .font(SpanFont.mono(9, weight: .regular))
                                .foregroundStyle(SpanColor.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(SpanColor.border)
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(date: .omitted, time: .shortened))
                                .font(SpanFont.mono(9, weight: .regular))
                                .foregroundStyle(SpanColor.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 200)

            // Legend.
            HStack(spacing: SpanSpacing.gutter) {
                legendDot(SpanColor.statusRed, "High")
                legendDot(SpanColor.statusYellow, "Elevated")
                legendDot(SpanColor.statusGreen, "In range")
                legendDot(SpanColor.accent, "Low")
            }
            .font(SpanFont.caption2)
            .foregroundStyle(SpanColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    /// Zone color for a mg/dL value, using the alert thresholds for the cutoffs.
    private func zoneColor(for mgdl: Double) -> Color {
        if mgdl <= alerts.lowThreshold { return SpanColor.accent }            // low (blue/purple)
        if mgdl >= alerts.highThreshold { return SpanColor.statusRed }        // high (red)
        if mgdl >= GlucoseStore.inRangeHigh - 30 { return SpanColor.statusYellow } // elevated (amber)
        return SpanColor.statusGreen                                          // in range (green)
    }

    private func tirColor(_ pct: Double) -> Color {
        if pct >= 70 { return SpanColor.statusGreen }
        if pct >= 50 { return SpanColor.statusYellow }
        return SpanColor.statusRed
    }

    // MARK: Alerts section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.gutter) {
            HStack {
                SpanSectionLabel("Alerts")
                Spacer()
                if alerts.isAuthorized {
                    StatusBadge(text: "Notifications on", style: .optimal, systemImage: "bell.fill")
                }
            }

            if !alerts.isAuthorized {
                Button("Enable glucose notifications") { alerts.requestAuthorization() }
                    .spanPrimaryButton()
                Text("Allow notifications so Span can alert you to highs and lows. Alerts fire even when the app is in the background.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("Fire alerts")
                        .font(SpanFont.callout)
                        .foregroundStyle(SpanColor.textPrimary)
                    Spacer()
                    SpanToggle(isOn: $alerts.alertsEnabled)
                }

                thresholdStepper("High alert ≥",
                                 value: $alerts.highThreshold,
                                 range: 120...300, color: SpanColor.statusRed)
                thresholdStepper("Low alert ≤",
                                 value: $alerts.lowThreshold,
                                 range: 50...100, color: SpanColor.accent)
                thresholdStepper("Urgent high ≥",
                                 value: $alerts.urgentHighThreshold,
                                 range: 180...400, color: SpanColor.statusRed)
                thresholdStepper("Urgent low ≤",
                                 value: $alerts.urgentLowThreshold,
                                 range: 40...70, color: SpanColor.accent)

                Text("Alerts fire in the background and are rate-limited (no more than one per ~25 min unless it escalates to urgent, then re-armed once back in range). iOS may still throttle background Bluetooth.")
                    .font(SpanFont.caption2)
                    .foregroundStyle(SpanColor.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard()
    }

    private func thresholdStepper(_ label: String,
                                  value: Binding<Double>,
                                  range: ClosedRange<Double>,
                                  color: Color) -> some View {
        HStack {
            Text(label)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textPrimary)
            Spacer()
            Text("\(Int(value.wrappedValue.rounded()))")
                .font(SpanFont.monoValue)
                .foregroundStyle(color)
                .frame(minWidth: 44, alignment: .trailing)
            Text("mg/dL")
                .font(SpanFont.caption)
                .foregroundStyle(SpanColor.textTertiary)
            Stepper("", value: value, in: range, step: 1)
                .labelsHidden()
                .tint(SpanColor.accent)
        }
    }

    private func featureRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: SpanSpacing.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(SpanColor.textSecondary)
            Text(note)
                .font(SpanFont.footnote)
                .foregroundStyle(SpanColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spanCard(padding: SpanSpacing.gutter)
    }

    // THE DIAGNOSTIC LOG — read top-to-bottom during the first live test to see
    // exactly what the GATT did: services found, 0x2AA7 subscribe result, whether
    // session-start was needed, raw notification hex + parsed glucose.
    private var diagnosticLog: some View {
        VStack(alignment: .leading, spacing: SpanSpacing.xs) {
            HStack {
                SpanSectionLabel("Diagnostic log (\(manager.log.count))")
                Spacer()
                if !manager.log.isEmpty {
                    Button("Clear") { manager.clearLog() }
                        .font(SpanFont.caption)
                        .foregroundStyle(SpanColor.accent)
                }
            }

            if manager.log.isEmpty {
                Text("The GATT trace will appear here when you connect — every service, subscribe, write, and raw notification, so the first live test is fully observable.")
                    .font(SpanFont.footnote)
                    .foregroundStyle(SpanColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .spanCard()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(manager.log.suffix(120).reversed()) { entry in
                        LogRow(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .spanCard(padding: SpanSpacing.gutter, fill: SpanColor.surface)
            }
        }
    }
}

/// One diagnostic-log line: timestamp + color-coded message. Mono for hex legibility.
private struct LogRow: View {
    let entry: CGMLogEntry

    private var color: Color {
        switch entry.level {
        case .info:  return SpanColor.textSecondary
        case .good:  return SpanColor.statusGreen
        case .warn:  return SpanColor.statusYellow
        case .error: return SpanColor.statusRed
        case .data:  return SpanColor.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(SpanFont.mono(9, weight: .regular))
                .foregroundStyle(SpanColor.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text(entry.message)
                .font(SpanFont.mono(10, weight: .regular))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    CGMView()
}
