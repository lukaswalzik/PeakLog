import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var gymStore: GymStore
    @EnvironmentObject private var cardioStore: CardioStore

    enum HistoryMode: String, CaseIterable, Identifiable {
        case strength = "Kraft"
        case cardio = "Cardio"
        case sauna = "Sauna"

        var id: String { rawValue }
    }

    @State private var selectedMode: HistoryMode = .strength
    @State private var selectedGymFilterId: String? = nil
    @State private var workoutToDelete: WorkoutDetail? = nil
    @State private var isShowingCalendar: Bool = false

    private var filteredWorkouts: [WorkoutDetail] {
        guard let gymId = selectedGymFilterId else {
            return historyStore.completedWorkouts
        }
        return historyStore.completedWorkouts.filter { $0.workout.gymId == gymId }
    }

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

                if isShowingCalendar {
                    TrainingCalendarView(
                        strengthDates: historyStore.completedWorkouts.map { $0.workout.startedAt },
                        cardioDates: cardioStore.sessions.map { $0.startedAt }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .background(Color(uiColor: .systemGroupedBackground))
                }

                if selectedMode == .strength {
                    if !gymStore.gyms.isEmpty {
                        gymFilterBar
                    }
                    strengthHistoryContent
                } else if selectedMode == .cardio {
                    CardioOverviewView()
                } else {
                    SaunaOverviewView()
                }
            }
            .navigationTitle("Verlauf")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingCalendar.toggle()
                        }
                    } label: {
                        Image(systemName: isShowingCalendar ? "calendar.circle.fill" : "calendar")
                    }
                    .accessibilityLabel("Trainingskalender")
                }
            }
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

    private var gymFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                gymChip(title: "Alle Gyms", isSelected: selectedGymFilterId == nil) {
                    selectedGymFilterId = nil
                }
                ForEach(gymStore.gyms) { gym in
                    gymChip(title: gym.name, isSelected: selectedGymFilterId == gym.id) {
                        selectedGymFilterId = (selectedGymFilterId == gym.id) ? nil : gym.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func gymChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var strengthHistoryContent: some View {
        if filteredWorkouts.isEmpty {
            EmptyStateView(
                systemImage: "clock.arrow.circlepath",
                title: "Noch kein Verlauf",
                message: selectedGymFilterId == nil
                    ? "Sobald du dein erstes Workout abschließt, erscheint es hier mit Dauer, Volumen und Sätzen."
                    : "Für dieses Gym wurden noch keine Workouts abgeschlossen."
            )
        } else {
            List {
                ForEach(filteredWorkouts) { detail in
                    let linkedCardio = cardioStore.sessions(forWorkoutId: detail.id)
                    NavigationLink {
                        WorkoutDetailView(detail: detail)
                    } label: {
                        HistoryRowView(detail: detail, linkedCardio: linkedCardio)
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
    let linkedCardio: [CardioSession]

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

    private var totalCardioSeconds: Int {
        linkedCardio.reduce(0) { $0 + $1.durationSeconds }
    }

    private var durationText: String {
        let end = detail.workout.finishedAt ?? detail.workout.startedAt
        let strengthSeconds = max(0, Int(end.timeIntervalSince(detail.workout.startedAt)))
        let combinedEnd = detail.workout.startedAt.addingTimeInterval(TimeInterval(strengthSeconds + totalCardioSeconds))
        return Formatters.elapsedDuration(from: detail.workout.startedAt, to: combinedEnd)
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

    private var cardioBadgeSummary: String? {
        guard !linkedCardio.isEmpty else { return nil }
        let totalMins = max(1, totalCardioSeconds / 60)
        if linkedCardio.count == 1, let first = linkedCardio.first {
            if let avg = first.avgHeartRate {
                return "+\(totalMins) Min \(first.activityType.displayName) · Ø \(avg) bpm"
            }
            return "+\(totalMins) Min \(first.activityType.displayName)"
        }
        return "+\(totalMins) Min Cardio (\(linkedCardio.count)×)"
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
                HStack(spacing: 6) {
                    Text(detail.workout.name)
                        .font(.headline)
                        .lineLimit(1)

                    if let gymName = detail.gymName {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                            Text(gymName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(durationText)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "scalemass")
                        Text("\(Formatters.weight(detail.totalVolumeKg)) kg")
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle")
                        Text("\(detail.completedSetCount)")
                    }
                    if let avgHR = detail.workout.avgHeartRate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                            Text("\(avgHR)")
                        }
                        .foregroundColor(.red)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let cardioSummary = cardioBadgeSummary {
                    HStack(spacing: 4) {
                        Image(systemName: linkedCardio.first?.activityType.systemImage ?? "heart.fill")
                            .font(.caption2)
                        Text(cardioSummary)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
                }

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
