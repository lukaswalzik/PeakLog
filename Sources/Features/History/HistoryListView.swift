import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var historyStore: HistoryStore

    @State private var workoutToDelete: WorkoutDetail? = nil

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.completedWorkouts.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.arrow.circlepath",
                        title: "Noch kein Verlauf",
                        message: "Sobald du dein erstes Workout abschließt, erscheint es hier mit Dauer, Volumen und Sätzen."
                    )
                } else {
                    List {
                        ForEach(historyStore.completedWorkouts) { detail in
                            NavigationLink {
                                WorkoutDetailView(detail: detail)
                            } label: {
                                HistoryRowView(detail: detail)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    workoutToDelete = detail
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Verlauf")
            .alert(
                "Workout löschen?",
                isPresented: Binding(
                    get: { workoutToDelete != nil },
                    set: { isPresented in
                        if !isPresented { workoutToDelete = nil }
                    }
                ),
                presenting: workoutToDelete
            ) { detail in
                Button("Löschen", role: .destructive) {
                    historyStore.deleteWorkout(id: detail.id)
                    workoutToDelete = nil
                }
                Button("Abbrechen", role: .cancel) {
                    workoutToDelete = nil
                }
            } message: { detail in
                Text("Das Workout „\(detail.workout.name)“ wird dauerhaft gelöscht.")
            }
        }
    }
}

private struct HistoryRowView: View {
    let detail: WorkoutDetail

    private var durationText: String {
        let end = detail.workout.finishedAt ?? detail.workout.startedAt
        return Formatters.elapsedDuration(from: detail.workout.startedAt, to: end)
    }

    private var exercisePreview: String {
        if detail.exercises.isEmpty {
            return "Keine Übungen"
        }
        return detail.exercises
            .prefix(3)
            .map { "\($0.sets.count)× \($0.exercise.name)" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(detail.workout.name)
                    .font(.headline)
                Spacer()
                Text(Formatters.shortDate(detail.workout.startedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Label(durationText, systemImage: "clock")
                Label("\(Formatters.weight(detail.totalVolumeKg)) kg", systemImage: "scalemass")
                Label("\(detail.completedSetCount) Sätze", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(exercisePreview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

struct HistoryListView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryListView()
            .environmentObject(HistoryStore(database: .makeInMemory()))
    }
}
