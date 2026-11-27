import SwiftUI
import UIKit

struct WorkoutRecapSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    let recap: CompletedWorkoutRecap
    @State private var renderedShareImage: UIImage? = nil
    @State private var aiFeedback: String? = nil
    @State private var isLoadingFeedback: Bool = false
    @State private var feedbackError: String? = nil

    private var progress: UserProgressSummary {
        ProgressEngine.compute(
            workouts: historyStore.completedWorkouts,
            cardioSessions: cardioStore.sessions,
            bodyweightEntries: bodyweightStore.entries
        )
    }

    private var formattedDuration: String {
        let mins = recap.durationSeconds / 60
        if mins >= 60 {
            return "\(mins / 60) Std. \(mins % 60) Min."
        }
        return "\(max(1, mins)) Min."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    recapCardView

                    if MistralAIService.shared.isConfigured {
                        if let feedback = aiFeedback {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Mistral KI-Feedback", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                                Text(feedback)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .strongCard()
                        } else {
                            Button {
                                loadAIFeedback()
                            } label: {
                                HStack {
                                    if isLoadingFeedback {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isLoadingFeedback ? "Mistral analysiert Workout..." : "KI-Feedback zum Training")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoadingFeedback)
                        }

                        if let err = feedbackError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    if let image = renderedShareImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("PeakLog – \(recap.workoutName)", image: Image(uiImage: image))
                        ) {
                            Label("Recap-Card als Bild teilen", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Fertig")
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
            .navigationTitle("Workout abgeschlossen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                renderShareCard()
            }
        }
    }

    private var recapCardView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.yellow)
                        Text("PEAKLOG RECAP")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text(recap.workoutName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    if let gym = recap.gymName {
                        Label(gym, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Level \(progress.level)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.22))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    if progress.weeklyStreak > 0 {
                        Label("\(progress.weeklyStreak) Wo.", systemImage: "flame.fill")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                    }
                }
            }

            HStack(spacing: 10) {
                recapMetricTile(value: formattedDuration, label: "Dauer", icon: "clock.fill")
                recapMetricTile(value: "\(recap.completedSets)", label: "Sätze", icon: "checkmark.circle.fill")
                recapMetricTile(value: "\(Formatters.weight(recap.totalVolumeKg)) kg", label: "Volumen", icon: "scalemass.fill")
            }

            if let avgHR = recap.avgHeartRate {
                HStack(spacing: 12) {
                    Label("Ø \(avgHR) bpm", systemImage: "heart.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    if let maxHR = recap.maxHeartRate {
                        Text("· Max \(maxHR) bpm")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.88))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !recap.prDescriptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(recap.prDescriptions.count) neue Bestleistung(en)!", systemImage: "trophy.fill")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)

                    ForEach(recap.prDescriptions.prefix(4), id: \.self) { pr in
                        Text("• \(pr)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Text(Formatters.shortDate(recap.finishedAt))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text("+100 XP · \(progress.rankTitle)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.indigo.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private func recapMetricTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func renderShareCard() {
        let renderer = ImageRenderer(
            content: recapCardView
                .frame(width: 360)
                .padding(12)
                .background(Color(uiColor: .systemBackground))
        )
        renderer.scale = 3.0
        renderedShareImage = renderer.uiImage
    }

    private func loadAIFeedback() {
        isLoadingFeedback = true
        feedbackError = nil
        Task {
            do {
                let text = try await MistralAIService.shared.generateWorkoutFeedback(recap: recap)
                await MainActor.run {
                    aiFeedback = text
                    isLoadingFeedback = false
                }
            } catch {
                await MainActor.run {
                    feedbackError = error.localizedDescription
                    isLoadingFeedback = false
                }
            }
        }
    }
}
