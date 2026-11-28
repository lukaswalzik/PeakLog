import SwiftUI
import UIKit

struct LiveCardioTimerView: View {
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var activeCardioManager: ActiveCardioManager
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver

    @State private var isShowingDiscardAlert: Bool = false

    private var formattedTotalTime: String {
        let secs = activeCardioManager.elapsedSeconds
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        let rem = secs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, rem)
        }
        return String(format: "%02d:%02d", mins, rem)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let planned = activeCardioManager.plannedSession {
                        plannedSessionBanner(planned)
                    }

                    Picker("Sportart", selection: $activeCardioManager.activityType) {
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

                                if let avg = activeCardioManager.avgRecordedHeartRate,
                                   let maxHR = activeCardioManager.hrMaxBpm {
                                    Text("Ø \(avg) · Max \(maxHR)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 2)
                        } else if activeCardioManager.autoZoneEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "heart")
                                    .font(.caption)
                                Text("Warte auf Live-HF (Apple Health / UDP)")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(activeCardioManager.currentZone.color)
                                .frame(width: 10, height: 10)
                            Text(activeCardioManager.currentZone.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(activeCardioManager.currentZone.color)
                            Text("· \(activeCardioManager.currentZone.bpmRangeText(maxHR: cardioStore.maxHeartRate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Du kannst dieses Fenster oder PeakLog jederzeit minimieren – Timer & Dynamic Island laufen weiter.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .strongCard()

                    // Auto-Zone toggle + zone list
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $activeCardioManager.autoZoneEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HF-Zone automatisch nach Puls")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(
                                    activeCardioManager.isAutoZoneActive
                                        ? "Aktiv · Zone wechselt automatisch (Max-HF \(cardioStore.maxHeartRate) bpm)"
                                        : (activeCardioManager.autoZoneEnabled
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
                            let secs = activeCardioManager.zoneSeconds[zone] ?? 0
                            let isSelected = activeCardioManager.currentZone == zone
                            Button {
                                activeCardioManager.selectZoneManually(zone)
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
                                            if isSelected && activeCardioManager.isAutoZoneActive {
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
                            activeCardioManager.togglePause()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: activeCardioManager.isRunning ? "pause.fill" : "play.fill")
                                Text(activeCardioManager.isRunning ? "Pause" : "Weiter")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            activeCardioManager.finish()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Speichern")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(activeCardioManager.elapsedSeconds < 5)
                    }
                    .padding(.top, 4)

                    Button(role: .destructive) {
                        isShowingDiscardAlert = true
                    } label: {
                        Text("Cardio-Einheit verwerfen")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Live Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        activeCardioManager.isPresentingSheet = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                    }
                    .accessibilityLabel("Cardio minimieren")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        activeCardioManager.finish()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .disabled(activeCardioManager.elapsedSeconds < 5)
                }
            }
            .alert("Cardio verwerfen?", isPresented: $isShowingDiscardAlert) {
                Button("Verwerfen", role: .destructive) {
                    activeCardioManager.discard()
                }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                Text("Die aktuelle Cardio-Einheit wird nicht gespeichert.")
            }
            .onAppear {
                activeCardioManager.catchUpWallClock(now: Date())
            }
        }
    }

    private func plannedSessionBanner(_ planned: CardioPlanSession) -> some View {
        let targetSeconds = max(60, planned.targetDurationMinutes * 60)
        let progress = min(1.0, Double(activeCardioManager.elapsedSeconds) / Double(targetSeconds))
        let reachedGoal = activeCardioManager.elapsedSeconds >= targetSeconds
        let targetBounds = planned.targetZone.percentBounds
        let lowerBPM = Int(round(Double(cardioStore.maxHeartRate) * targetBounds.0))
        let upperBPM = Int(round(Double(cardioStore.maxHeartRate) * targetBounds.1))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planned.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    if !planned.intensityGuide.isEmpty {
                        Text(planned.intensityGuide)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                Spacer()
                if reachedGoal {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Ziel erreicht!")
                    }
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
                } else {
                    Text("Ziel: \(planned.targetDurationMinutes) Min")
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(reachedGoal ? .green : planned.targetZone.color)

            HStack(spacing: 6) {
                Circle()
                    .fill(planned.targetZone.color)
                    .frame(width: 8, height: 8)
                Text("Zielzone: \(planned.targetZone.shortName) (\(lowerBPM)–\(upperBPM) bpm)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if let bpm = heartRateReceiver.currentBPM {
                    if bpm >= lowerBPM && bpm <= upperBPM {
                        Text("Im Zielbereich")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    } else if bpm < lowerBPM {
                        Text("Etwas zügiger")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    } else {
                        Text("Etwas ruhiger")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .strongCard(padding: 12)
    }

    private func formatZoneTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
