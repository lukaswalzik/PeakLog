import SwiftUI

struct AppleHealthView: View {
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    @State private var isPulsing: Bool = false
    @State private var isImportingWeight: Bool = false
    @State private var weightImportMessage: String? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var currentZone: HeartRateZone? {
        guard let bpm = heartRateReceiver.currentBPM else { return nil }
        return HeartRateZone.zone(for: bpm, maxHR: cardioStore.maxHeartRate)
    }

    var body: some View {
        List {
            if !healthKitService.isAvailable {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Apple Health ist auf diesem Gerät nicht verfügbar.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Live Heart Rate Hero Section
                Section {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(heartRateReceiver.hasLiveSignal ? 0.16 : 0.08))
                                .frame(width: 64, height: 64)
                            Image(systemName: heartRateReceiver.hasLiveSignal ? "heart.fill" : "heart")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(heartRateReceiver.hasLiveSignal ? (currentZone?.color ?? .red) : .secondary)
                                .scaleEffect(isPulsing ? 1.16 : 1.0)
                        }

                        if let bpm = heartRateReceiver.currentBPM {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(bpm)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text("bpm")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }

                            if let zone = currentZone {
                                Text("\(zone.title) · \(zone.bpmRangeText(maxHR: cardioStore.maxHeartRate))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(zone.color)
                            }

                            if let source = heartRateReceiver.activeSource {
                                Label("Quelle: \(source.displayName)", systemImage: source == .appleHealth ? "heart.text.square.fill" : "antenna.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Text("– bpm")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text(
                                healthKitService.isConnected
                                    ? "Verbunden · wartet auf Live-Herzfrequenz aus Apple Health"
                                    : "Noch nicht mit Apple Health verbunden"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        }

                        if let err = healthKitService.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                // Authorization & Controls
                Section(
                    header: Text("Verbindung & Live-Sync"),
                    footer: Text("Sobald Apple Health verbunden ist, liest PeakLog neue Herzfrequenz-Werte (z. B. von AirPods HF Bridge oder Apple Watch) in Echtzeit aus Apple Health aus, zeigt sie im Kraft-Workout & Live-Cardio-Timer an und wählt automatisch die passende HF-Zone.")
                ) {
                    if !healthKitService.isConnected {
                        Button {
                            healthKitService.requestAuthorization()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Mit Apple Health verbinden", systemImage: "heart.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Toggle("Live-Herzfrequenz aus Apple Health", isOn: $healthKitService.liveHeartRateEnabled)
                        Toggle("Workouts in Apple Health speichern", isOn: $healthKitService.exportWorkoutsEnabled)

                        Button {
                            healthKitService.requestAuthorization()
                        } label: {
                            Label("Berechtigungen erneut prüfen", systemImage: "checkmark.shield")
                        }

                        Button(role: .destructive) {
                            healthKitService.disconnect()
                        } label: {
                            Label("Apple Health trennen", systemImage: "xmark.circle")
                        }
                    }
                }

                // Today's Health Summary
                if healthKitService.isConnected {
                    Section(header: Text("Apple Health · Übersicht")) {
                        HStack {
                            Label("Schritte heute", systemImage: "figure.walk")
                            Spacer()
                            Text(healthKitService.dailySummary.stepsToday.map { "\($0)" } ?? "–")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Label("Aktivitätskalorien heute", systemImage: "flame.fill")
                            Spacer()
                            Text(healthKitService.dailySummary.activeCaloriesToday.map { "\($0) kcal" } ?? "–")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Label("Ruhepuls", systemImage: "heart")
                            Spacer()
                            Text(healthKitService.dailySummary.restingHeartRate.map { "\($0) bpm" } ?? "–")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Label("HRV (SDNN)", systemImage: "waveform.path.ecg")
                            Spacer()
                            Text(healthKitService.dailySummary.hrvMs.map { "\($0) ms" } ?? "–")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Label("Letztes Körpergewicht", systemImage: "scalemass")
                            Spacer()
                            if let kg = healthKitService.dailySummary.latestWeightKg {
                                Text("\(Formatters.weight(kg)) kg")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("–")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            healthKitService.refreshDailySummary()
                        } label: {
                            HStack {
                                if healthKitService.isLoadingSummary {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                }
                                Label("Daten aktualisieren", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(healthKitService.isLoadingSummary)
                    }

                    // Bodyweight import
                    Section(
                        header: Text("Körpergewicht importieren"),
                        footer: Text("Importiert Gewichtsmessungen der letzten 90 Tage aus Apple Health (bereits vorhandene Tage in PeakLog werden übersprungen).")
                    ) {
                        Button {
                            importBodyweightFromHealth()
                        } label: {
                            HStack {
                                if isImportingWeight {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                }
                                Label("Gewicht aus Apple Health importieren", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(isImportingWeight)

                        if let msg = weightImportMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    // Live Stream Diagnostics
                    Section(header: Text("Live-HF Status")) {
                        HStack {
                            Text("HealthKit Live-Stream")
                            Spacer()
                            Text(healthKitService.isStreamingHeartRate ? "Aktiv" : "Pausiert")
                                .foregroundColor(healthKitService.isStreamingHeartRate ? .green : .secondary)
                        }

                        HStack {
                            Text("Empfangene Health-Werte")
                            Spacer()
                            Text("\(healthKitService.heartRateSamplesReceived)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Letzter Health-Messwert")
                            Spacer()
                            if let bpm = healthKitService.lastHeartRateBPM,
                               let date = healthKitService.lastHeartRateAt {
                                Text("\(bpm) bpm · \(Self.timeFormatter.string(from: date))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("Noch keiner")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if healthKitService.isConnected {
                healthKitService.refreshDailySummary()
                healthKitService.updateHeartRateStreamingState()
            }
        }
        .onChange(of: heartRateReceiver.receivedPacketCount) { _ in
            withAnimation(.easeOut(duration: 0.14)) {
                isPulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeIn(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }

    private func importBodyweightFromHealth() {
        isImportingWeight = true
        weightImportMessage = nil

        healthKitService.fetchRecentBodyweightSamples(days: 90) { samples in
            let cal = Calendar.current
            var existingDays: Set<Date> = Set(
                bodyweightStore.entries.map { cal.startOfDay(for: $0.entry.recordedAt) }
            )

            // Keep latest sample per day
            var latestByDay: [Date: HealthKitWeightSample] = [:]
            for s in samples {
                let day = cal.startOfDay(for: s.date)
                if let current = latestByDay[day] {
                    if s.date > current.date {
                        latestByDay[day] = s
                    }
                } else {
                    latestByDay[day] = s
                }
            }

            var imported = 0
            for day in latestByDay.keys.sorted() {
                guard !existingDays.contains(day), let sample = latestByDay[day] else { continue }
                let entry = BodyweightEntry(
                    recordedAt: sample.date,
                    weightKg: sample.weightKg,
                    notes: "Aus Apple Health importiert"
                )
                bodyweightStore.saveEntry(entry, photos: [])
                existingDays.insert(day)
                imported += 1
            }

            isImportingWeight = false
            if imported > 0 {
                weightImportMessage = "\(imported) neue Gewichtseinträge aus Apple Health importiert."
            } else if samples.isEmpty {
                weightImportMessage = "Keine Gewichtseinträge in Apple Health (letzte 90 Tage) gefunden."
            } else {
                weightImportMessage = "Alle Gewichtseinträge der letzten 90 Tage sind bereits vorhanden."
            }
        }
    }
}
