import SwiftUI

struct HeartRateReceiverSettingsView: View {
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver
    @EnvironmentObject private var cardioStore: CardioStore

    @State private var isPulsing: Bool = false
    @State private var portDraft: String = ""

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
        if heartRateReceiver.isListening { return "Lauscht auf UDP :\(heartRateReceiver.port) (IPv4 + IPv6)" }
        return "Wird gestartet…"
    }

    private var currentZone: HeartRateZone? {
        guard let bpm = heartRateReceiver.currentBPM else { return nil }
        return HeartRateZone.zone(for: bpm, maxHR: cardioStore.maxHeartRate)
    }

    private var parsedDraftPort: UInt16? {
        guard let val = Int(portDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
              val >= 1024 && val <= 65535 else {
            return nil
        }
        return UInt16(val)
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
                        Text("Warte auf UDP-Pakete auf Port \(heartRateReceiver.port)")
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
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(
                header: Text("Empfänger & Selbsttest"),
                footer: Text("Tippe auf „Test-Paket senden“, um zu prüfen, ob der UDP-Empfänger in StrongTracker lokal empfängt. Wenn der Test 74 bpm anzeigt, aber von airpods-hf-bridge 0 Roh-Pakete ankommen, sendet die Bridge im Hintergrund nicht auf Port \(heartRateReceiver.port) (z. B. weil iOS die Bridge beim App-Wechsel pausiert).")
            ) {
                Toggle("Live-HF-Empfänger aktiv", isOn: $heartRateReceiver.isEnabled)

                if heartRateReceiver.isEnabled {
                    Button {
                        heartRateReceiver.sendTestPacket(bpm: 74)
                    } label: {
                        Label("Test-Paket senden (74 bpm → 127.0.0.1:\(heartRateReceiver.port))", systemImage: "paperplane.fill")
                    }

                    Button {
                        heartRateReceiver.restart()
                    } label: {
                        Label("UDP-Socket neu starten", systemImage: "arrow.clockwise")
                    }
                }
            }

            Section(header: Text("UDP-Port")) {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("49153", text: $portDraft)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .monospacedDigit()
                    if let newPort = parsedDraftPort, newPort != heartRateReceiver.port {
                        Button("Übernehmen") {
                            heartRateReceiver.port = newPort
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .buttonStyle(.borderedProminent)
                    }
                }

                if heartRateReceiver.port != HeartRateReceiver.defaultPort {
                    Button("Standard-Port 49153 wiederherstellen") {
                        heartRateReceiver.port = HeartRateReceiver.defaultPort
                        portDraft = "\(HeartRateReceiver.defaultPort)"
                    }
                    .font(.caption)
                }
            }

            Section(header: Text("Diagnose")) {
                HStack {
                    Text("Lauscht auf")
                    Spacer()
                    Text("0.0.0.0 & [::]:\(heartRateReceiver.port) (UDP)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Empfangene Roh-Pakete")
                    Spacer()
                    Text("\(heartRateReceiver.rawPacketCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Gültige BPM-Werte")
                    Spacer()
                    Text("\(heartRateReceiver.receivedPacketCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Letzter Roh-Payload")
                    Spacer()
                    Text(heartRateReceiver.lastRawPayload ?? "–")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Letztes Paket")
                    Spacer()
                    if let last = heartRateReceiver.lastRawPacketAt {
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
        .onAppear {
            portDraft = "\(heartRateReceiver.port)"
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
}
