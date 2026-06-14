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

#Preview {
    CGMView()
}
