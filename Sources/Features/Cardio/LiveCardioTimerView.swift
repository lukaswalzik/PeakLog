import SwiftUI
import UIKit

struct LiveCardioTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver

    let onFinish: (CardioSession) -> Void

    @State private var activityType: CardioActivityType = .running
    @State private var currentZone: HeartRateZone = .z2
    @State private var autoZoneEnabled: Bool = true
    @State private var isRunning: Bool = true
    @State private var startedAt: Date = Date()
    @State private var elapsedSeconds: Int = 0
    @State private var zoneSeconds: [HeartRateZone: Int] = [
        .z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0
    ]
    @State private var hrSampleCount: Int = 0
    @State private var hrBpmSum: Int = 0
    @State private var hrMaxBpm: Int? = nil
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isAutoZoneActive: Bool {
        autoZoneEnabled && heartRateReceiver.hasLiveSignal
    }

    private var avgRecordedHeartRate: Int? {
        guard hrSampleCount > 0 else { return nil }
        return Int((Double(hrBpmSum) / Double(hrSampleCount)).rounded())
    }

    private var formattedTotalTime: String {
        let hours = elapsedSeconds / 3600
        let mins = (elapsedSeconds % 3600) / 60
        let secs = elapsedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Sportart", selection: $activityType) {
                        ForEach(CardioActivityType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Capsule())

                    // Main live clock card
                    VStack(spacing: 8) {
                        Text(formattedTotalTime)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        if let bpm = heartRateReceiver.currentBPM {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .font(.subheadline)
                                    Text("\(bpm) bpm")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .clipShape(Capsule())

                                if let avg = avgRecordedHeartRate, let maxHR = hrMaxBpm {
                                    Text("Ø \(avg) · Max \(maxHR)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 2)
                        } else if autoZoneEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "heart")
                                    .font(.caption)
                                Text("Warte auf Live-HF (UDP :\(heartRateReceiver.port))")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(currentZone.color)
                                .frame(width: 10, height: 10)
                            Text(currentZone.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(currentZone.color)
                            Text("· \(currentZone.bpmRangeText(maxHR: cardioStore.maxHeartRate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .strongCard()

                    // Auto-Zone toggle + zone display
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $autoZoneEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HF-Zone automatisch nach Puls")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(
                                    isAutoZoneActive
                                        ? "Aktiv · Zone wechselt automatisch (Max-HF \(cardioStore.maxHeartRate) bpm)"
                                        : (autoZoneEnabled
                                            ? "Bereit · übernimmt automatisch sobald Live-Puls ankommt (aktuell manuell wählbar)"
                                            : "Aus · tippe eine Zone manuell an")
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        ForEach(HeartRateZone.allCases) { zone in
                            let secs = zoneSeconds[zone] ?? 0
                            let isSelected = currentZone == zone
                            Button {
                                guard !isAutoZoneActive else { return }
                                currentZone = zone
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(zone.shortName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(zone.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(zone.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            if isSelected && isAutoZoneActive {
                                                Text("AUTO")
                                                    .font(.caption2)
                                                    .fontWeight(.heavy)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(zone.color.opacity(0.2))
                                                    .foregroundColor(zone.color)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(zone.bpmRangeText(maxHR: cardioStore.maxHeartRate))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(formatZoneTime(secs))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                        .foregroundColor(isSelected ? zone.color : .secondary)
                                }
                                .padding(12)
                                .background(
                                    isSelected
                                        ? zone.color.opacity(0.14)
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? zone.color : Color.primary.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            isRunning.toggle()
                        } label: {
                            Label(isRunning ? "Pause" : "Weiter", systemImage: isRunning ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            finishSession()
                        } label: {
                            Label("Beenden", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(elapsedSeconds < 5)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Live Cardio-Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen", role: .destructive) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if autoZoneEnabled, let bpm = heartRateReceiver.currentBPM {
                    currentZone = HeartRateZone.clampedZone(for: bpm, maxHR: cardioStore.maxHeartRate)
                }
            }
            .onReceive(ticker) { _ in
                guard isRunning else { return }
                elapsedSeconds += 1
                zoneSeconds[currentZone, default: 0] += 1
            }
            .onReceive(heartRateReceiver.sampleSubject) { reading in
                guard isRunning else { return }
                hrSampleCount += 1
                hrBpmSum += reading.bpm
                hrMaxBpm = hrMaxBpm.map { max($0, reading.bpm) } ?? reading.bpm
                if autoZoneEnabled {
                    currentZone = HeartRateZone.clampedZone(for: reading.bpm, maxHR: cardioStore.maxHeartRate)
                }
            }
        }
    }

    private func formatZoneTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func finishSession() {
        let session = CardioSession(
            activityType: activityType,
            startedAt: startedAt,
            durationSeconds: max(60, elapsedSeconds),
            avgHeartRate: avgRecordedHeartRate,
            maxHeartRate: hrMaxBpm,
            zone1Seconds: zoneSeconds[.z1] ?? 0,
            zone2Seconds: zoneSeconds[.z2] ?? 0,
            zone3Seconds: zoneSeconds[.z3] ?? 0,
            zone4Seconds: zoneSeconds[.z4] ?? 0,
            zone5Seconds: zoneSeconds[.z5] ?? 0
        )
        onFinish(session)
        dismiss()
    }
}
