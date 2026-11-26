import SwiftUI

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore

    let detail: WorkoutDetail

    @State private var isShowingDeleteAlert: Bool = false

    private var durationText: String {
        let end = detail.workout.finishedAt ?? detail.workout.startedAt
        return Formatters.elapsedDuration(from: detail.workout.startedAt, to: end)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard

                if detail.exercises.isEmpty {
                    EmptyStateView(
                        systemImage: "dumbbell",
                        title: "Keine abgeschlossenen Sätze",
                        message: "In diesem Workout wurden keine Sätze abgeschlossen."
                    )
                } else {
                    ForEach(detail.exercises) { exerciseDetail in
                        exerciseCard(exerciseDetail)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(detail.workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Workout löschen")
            }
        }
        .alert("Workout löschen?", isPresented: $isShowingDeleteAlert) {
            Button("Löschen", role: .destructive) {
                historyStore.deleteWorkout(id: detail.id)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieses abgeschlossene Training wird dauerhaft aus deinem Verlauf entfernt.")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Formatters.workoutDate(detail.workout.startedAt))
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                MetricTile(title: "Dauer", value: durationText)
                MetricTile(title: "Sätze", value: "\(detail.completedSetCount)")
                MetricTile(title: "Volumen", value: "\(Formatters.weight(detail.totalVolumeKg)) kg")
            }

            if let notes = detail.workout.notes, !notes.isEmpty {
                Divider()
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func exerciseCard(_ item: WorkoutExerciseDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text("\(item.exercise.muscleGroup.displayName) · \(item.exercise.equipment.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            ForEach(item.sets) { workoutSet in
                HStack {
                    Text(workoutSet.setType.shortBadge ?? "\(workoutSet.setOrder)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(workoutSet.setType == .warmup ? .orange : .primary)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(setDescription(workoutSet))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    if workoutSet.setType != .warmup,
                       let w = workoutSet.weightKg,
                       let r = workoutSet.reps,
                       w > 0, r > 0 {
                        let est1RM = OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                        Text("1RM ~\(Formatters.weight(est1RM)) kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func setDescription(_ workoutSet: WorkoutSet) -> String {
        switch (workoutSet.weightKg, workoutSet.reps) {
        case let (w?, r?):
            return "\(Formatters.weight(w)) kg × \(r)"
        case let (nil, r?):
            return "\(r) Wdh."
        case let (w?, nil):
            return "\(Formatters.weight(w)) kg"
        case (nil, nil):
            return "Abgeschlossen"
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
