import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var historyStore: HistoryStore

    enum HistoryMode: String, CaseIterable, Identifiable {
        case strength = "Kraft"
        case cardio = "Cardio"

        var id: String { rawValue }
    }

    @State private var selectedMode: HistoryMode = .strength
    @State private var workoutToDelete: WorkoutDetail? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modus", selection: $selectedMode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground))

                if selectedMode == .strength {
                    strengthHistoryContent
                } else {
                    CardioOverviewView()
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

    @ViewBuilder
    private var strengthHistoryContent: some View {
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
}

private struct HistoryRowView: View {
    let detail: WorkoutDetail

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMM"
        return f
    }()

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
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 1) {
                Text(Self.dayFormatter.string(from: detail.workout.startedAt))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                Text(Self.monthFormatter.string(from: detail.workout.startedAt).uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, height: 48)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(detail.workout.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(durationText, systemImage: "clock")
                    Label("\(Formatters.weight(detail.totalVolumeKg)) kg", systemImage: "scalemass")
                    Label("\(detail.completedSetCount)", systemImage: "checkmark.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(exercisePreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HistoryListView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        HistoryListView()
            .environmentObject(HistoryStore(database: db))
            .environmentObject(CardioStore(database: db))
    }
}
