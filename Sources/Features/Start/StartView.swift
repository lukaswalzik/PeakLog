import SwiftUI

struct StartView: View {
    @EnvironmentObject private var routineStore: RoutineStore
    @EnvironmentObject private var activeWorkoutManager: ActiveWorkoutManager
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    @State private var isShowingCreateRoutine: Bool = false
    @State private var editingRoutine: RoutineWithExercises? = nil
    @State private var routineToDelete: RoutineWithExercises? = nil
    @State private var isShowingAlreadyActiveAlert: Bool = false
    @State private var isShowingCardioForm: Bool = false
    @State private var isShowingLiveCardio: Bool = false

    private var progressSummary: UserProgressSummary {
        ProgressEngine.compute(
            workouts: historyStore.completedWorkouts,
            cardioSessions: cardioStore.sessions,
            bodyweightEntries: bodyweightStore.entries
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    heroQuickStartCard
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section(
                    header: HStack {
                        Text("Meine Routinen")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            isShowingCreateRoutine = true
                        } label: {
                            Label("Neue Routine", systemImage: "plus")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(nil)
                        }
                    }
                ) {
                    if routineStore.routines.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("Noch keine Routinen")
                                .font(.headline)
                            Text("Erstelle deine erste Trainingsvorlage (z. B. Push A oder Ganzkörper).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Erste Routine erstellen") {
                                isShowingCreateRoutine = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(routineStore.routines) { item in
                            RoutineCardRow(
                                item: item,
                                onStart: {
                                    if activeWorkoutManager.hasActiveWorkout {
                                        isShowingAlreadyActiveAlert = true
                                    } else {
                                        activeWorkoutManager.startWorkout(from: item)
                                    }
                                },
                                onEdit: {
                                    editingRoutine = item
                                },
                                onDelete: {
                                    routineToDelete = item
                                }
                            )
                        }
                        .onMove { source, destination in
                            routineStore.moveRoutines(from: source, to: destination)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("StrongTracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if routineStore.routines.count > 1 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingCreateRoutine = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Neue Routine")
                }
            }
            .sheet(isPresented: $isShowingCreateRoutine) {
                RoutineEditorView(nextSortOrder: routineStore.routines.count) { routine, exercises in
                    routineStore.saveRoutine(routine, exercises: exercises)
                }
            }
            .sheet(item: $editingRoutine) { item in
                RoutineEditorView(
                    existingRoutine: item,
                    nextSortOrder: routineStore.routines.count
                ) { routine, exercises in
                    routineStore.saveRoutine(routine, exercises: exercises)
                }
            }
            .sheet(isPresented: $isShowingCardioForm) {
                CardioFormView { session in
                    cardioStore.save(session)
                }
            }
            .sheet(isPresented: $isShowingLiveCardio) {
                LiveCardioTimerView { session in
                    cardioStore.save(session)
                }
            }
            .alert(
                "Routine löschen?",
                isPresented: Binding(
                    get: { routineToDelete != nil },
                    set: { isPresented in
                        if !isPresented { routineToDelete = nil }
                    }
                ),
                presenting: routineToDelete
            ) { item in
                Button("Löschen", role: .destructive) {
                    routineStore.deleteRoutine(id: item.id)
                    routineToDelete = nil
                }
                Button("Abbrechen", role: .cancel) {
                    routineToDelete = nil
                }
            } message: { item in
                Text("Die Routine „\(item.routine.name)“ wird entfernt. Vergangene Workouts bleiben im Verlauf erhalten.")
            }
            .alert("Workout läuft bereits", isPresented: $isShowingAlreadyActiveAlert) {
                Button("Laufendes Workout öffnen") {
                    activeWorkoutManager.isPresentingSheet = true
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Du hast aktuell ein aktives Workout. Beende oder verwirf es zuerst, bevor du ein neues startest.")
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: { routineStore.errorMessage != nil || activeWorkoutManager.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            routineStore.errorMessage = nil
                            activeWorkoutManager.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(routineStore.errorMessage ?? activeWorkoutManager.errorMessage ?? "")
            }
        }
    }

    private var heroQuickStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Level \(progressSummary.level)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.22))
                            .foregroundColor(.white)
                            .clipShape(Capsule())

                        if progressSummary.weeklyStreak > 0 {
                            Label("\(progressSummary.weeklyStreak) Wo. Streak", systemImage: "flame.fill")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.28))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Bereit fürs Training?")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 2)

                    Text("\(progressSummary.rankTitle) · \(progressSummary.sessionsThisWeek) Trainings diese Woche")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    if activeWorkoutManager.hasActiveWorkout {
                        isShowingAlreadyActiveAlert = true
                    } else {
                        activeWorkoutManager.startEmptyWorkout()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Kraft starten")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.11, green: 0.36, blue: 0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        isShowingLiveCardio = true
                    } label: {
                        Label("Live Cardio-Timer", systemImage: "stopwatch.fill")
                    }
                    Button {
                        isShowingCardioForm = true
                    } label: {
                        Label("Cardio manuell eintragen", systemImage: "plus.circle")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Cardio")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(AppTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.blue.opacity(0.22), radius: 8, x: 0, y: 4)
    }
}

private struct RoutineCardRow: View {
    let item: RoutineWithExercises
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var exerciseSummary: String {
        if item.exercises.isEmpty {
            return "Noch keine Übungen"
        }
        return item.exercises
            .prefix(4)
            .map { "\($0.routineExercise.targetSets)× \($0.exercise.name)" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.routine.name)
                        .font(.headline)
                    if let notes = item.routine.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }

            if !item.exercises.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.exercises.prefix(5)) { ex in
                        ExerciseThumbnailView(exercise: ex.exercise, size: 30)
                    }
                    if item.exercises.count > 5 {
                        Text("+\(item.exercises.count - 5)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            Text(exerciseSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(4)

            HStack {
                Text("\(item.exercises.count) Übungen · \(item.totalSets) Sätze")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    onStart()
                } label: {
                    Label("Starten", systemImage: "play.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        StartView()
            .environmentObject(RoutineStore(database: db))
            .environmentObject(ExerciseStore(database: db))
            .environmentObject(ActiveWorkoutManager(database: db))
            .environmentObject(HistoryStore(database: db))
            .environmentObject(CardioStore(database: db))
            .environmentObject(BodyweightStore(database: db))
    }
}
