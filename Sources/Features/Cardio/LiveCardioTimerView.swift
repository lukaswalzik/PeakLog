import SwiftUI
import UIKit

struct LiveCardioTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardioStore: CardioStore

    let onFinish: (CardioSession) -> Void

    @State private var activityType: CardioActivityType = .running
    @State private var currentZone: HeartRateZone = .z2
    @State private var isRunning: Bool = true
    @State private var startedAt: Date = Date()
    @State private var elapsedSeconds: Int = 0
    @State private var zoneSeconds: [HeartRateZone: Int] = [
        .z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0
    ]
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

                    // Zone selector buttons
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aktuelle HF-Zone antippen")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(HeartRateZone.allCases) { zone in
                            let secs = zoneSeconds[zone] ?? 0
                            let isSelected = currentZone == zone
                            Button {
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
                                        Text(zone.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
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
            .onReceive(ticker) { _ in
                guard isRunning else { return }
                elapsedSeconds += 1
                zoneSeconds[currentZone, default: 0] += 1
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
