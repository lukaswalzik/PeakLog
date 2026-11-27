import SwiftUI

struct HeartRateReceiverSettingsView: View {
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver
    @EnvironmentObject private var cardioStore: CardioStore

    @State private var isPulsing: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var statusColor: Color {
        if heartRateReceiver.lastError != nil { return .red }
        if !heartRateReceiver.isEnabled { return .secondary }
        if heartRateReceiver.hasLiveSignal { return .green }
        if heartRateReceiver.isListening { return .orange }
        return .secondary
    }

    private var statusText: String {
        if let error = heartRateReceiver.lastError { return error }
        if !heartRateReceiver.isEnabled { return "Deaktiviert" }
        if heartRateReceiver.hasLiveSignal { return "Live-Signal aktiv" }
        if heartRateReceiver.isListening { return "Lauscht auf UDP-Pakete" }
        return "Wird gestartet…"
    }

    private var currentZone: HeartRateZone? {
        guard let bpm = heartRateReceiver.currentBPM else { return nil }
        return HeartRateZone.zone(for: bpm, maxHR: cardioStore.maxHeartRate)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill((currentZone?.color ?? Color.red).opacity(heartRateReceiver.hasLiveSignal ? 0.16 : 0.08))
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
                        } else {
                            Text("Ruhe / Leicht (< 50 % Max-HF)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("– bpm")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("Warte auf Daten von airpods-hf-bridge")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(
                header: Text("Empfänger"),
                footer: Text("Empfängt lokale UDP-Datagramme (UTF-8 ASCII-BPM 30–240, z. B. \"74\", ca. 1×/Sekunde) und zeigt bzw. speichert die Herzfrequenz automatisch in aktiven Kraft-Workouts und im Live-Cardio-Timer.")
            ) {
                Toggle("Live-HF-Empfänger aktiv", isOn: $heartRateReceiver.isEnabled)

                if heartRateReceiver.isEnabled {
                    Button {
                        heartRateReceiver.restart()
                    } label: {
                        Label("UDP-Socket neu starten", systemImage: "arrow.clockwise")
                    }
                }
            }

            Section(header: Text("Verbindungsdetails")) {
                HStack {
                    Text("Endpunkt")
                    Spacer()
                    Text("\(heartRateReceiver.endpointDisplay) (UDP)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Payload")
                    Spacer()
                    Text("UTF-8 ASCII · 30–240 bpm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Empfangene Pakete")
                    Spacer()
                    Text("\(heartRateReceiver.receivedPacketCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Letztes Signal")
                    Spacer()
                    if let last = heartRateReceiver.lastSampleAt {
                        Text(Self.timeFormatter.string(from: last))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    } else {
                        Text("Noch keins")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Live-Herzfrequenz (UDP)")
        .navigationBarTitleDisplayMode(.inline)
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
}
