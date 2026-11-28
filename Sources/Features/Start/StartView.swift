import SwiftUI

struct StartView: View {
    @EnvironmentObject private var routineStore: RoutineStore
    @EnvironmentObject private var activeWorkoutManager: ActiveWorkoutManager
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore
    @EnvironmentObject private var gymStore: GymStore
    @EnvironmentObject private var nutritionStore: NutritionStore

    @State private var isShowingCreateRoutine: Bool = false
    @State private var editingRoutine: RoutineWithExercises? = nil
    @State private var routineToDelete: RoutineWithExercises? = nil
    @State private var isShowingAlreadyActiveAlert: Bool = false
    @State private var isShowingCardioForm: Bool = false
    @State private var isShowingLiveCardio: Bool = false
    @State private var plannedCardioToStart: CardioPlanSession? = nil
    @State private var isShowingManageGyms: Bool = false

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

                Section {
                    weeklyDigestCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
                                        activeWorkoutManager.startWorkout(from: item, gymId: gymStore.selectedGymId, isDeload: false)
                                    }
                                },
                                onStartDeload: {
                                    if activeWorkoutManager.hasActiveWorkout {
                                        isShowingAlreadyActiveAlert = true
                                    } else {
                                        activeWorkoutManager.startWorkout(from: item, gymId: gymStore.selectedGymId, isDeload: true)
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

                Section(
                    header: Text("Mein Cardio-Plan")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                ) {
                    CardioPlansSectionView(
                        onStartSession: { planned in
                            plannedCardioToStart = planned
                        },
                        compactForStartTab: true
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("PeakLog")
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
            .sheet(item: $plannedCardioToStart) { planned in
                LiveCardioTimerView(plannedSession: planned) { session in
                    cardioStore.save(session)
                }
            }
            .sheet(isPresented: $isShowingManageGyms) {
                NavigationStack {
                    GymsManagementView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") { isShowingManageGyms = false }
                            }
                        }
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

                Menu {
                    Button {
                        gymStore.selectedGymId = nil
                    } label: {
                        HStack {
                            Text("Kein bestimmtes Gym")
                            if gymStore.selectedGymId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !gymStore.gyms.isEmpty {
                        Divider()
                        ForEach(gymStore.gyms) { gym in
                            Button {
                                gymStore.selectedGymId = gym.id
                            } label: {
                                HStack {
                                    Text(gym.name)
                                    if gymStore.selectedGymId == gym.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()
                    Button {
                        isShowingManageGyms = true
                    } label: {
                        Label("Gyms verwalten…", systemImage: "plus.circle")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(gymStore.selectedGym?.name ?? "Gym")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.20))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                Button {
                    if activeWorkoutManager.hasActiveWorkout {
                        isShowingAlreadyActiveAlert = true
                    } else {
                        activeWorkoutManager.startEmptyWorkout(gymId: gymStore.selectedGymId)
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

    private var weeklyDigestCard: some View {
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) ?? now

        let thisWeekWorkouts = historyStore.completedWorkouts.filter { $0.workout.startedAt >= weekAgo }
        let prevWeekWorkouts = historyStore.completedWorkouts.filter {
            $0.workout.startedAt >= twoWeeksAgo && $0.workout.startedAt < weekAgo
        }
        let thisWeekVolume = thisWeekWorkouts.reduce(0.0) { $0 + $1.totalVolumeKg }
        let prevWeekVolume = prevWeekWorkouts.reduce(0.0) { $0 + $1.totalVolumeKg }

        let volumeDeltaText: String? = {
            guard prevWeekVolume > 0, thisWeekVolume > 0 else { return nil }
            let pct = ((thisWeekVolume - prevWeekVolume) / prevWeekVolume) * 100.0
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(Int(round(pct)))% vs. Vorwoche"
        }()

        let thisWeekCardio = cardioStore.sessions.filter { $0.startedAt >= weekAgo }.count
        let avgKcal = nutritionStore.averageWeeklyCalories
        let avgProtein = nutritionStore.averageWeeklyProtein

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Wochenrückblick (7 Tage)", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let delta = volumeDeltaText {
                    Text(delta)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                digestTile(
                    value: "\(thisWeekWorkouts.count + thisWeekCardio)",
                    label: "Sessions",
                    color: .blue
                )
                digestTile(
                    value: thisWeekVolume >= 1000
                        ? String(format: "%.1ft", thisWeekVolume / 1000.0)
                        : "\(Int(round(thisWeekVolume))) kg",
                    label: "Volumen",
                    color: .indigo
                )
                digestTile(
                    value: avgKcal > 0 ? "\(avgKcal)" : "–",
                    label: "Ø kcal",
                    color: .orange
                )
                digestTile(
                    value: avgProtein > 0 ? "\(avgProtein)g" : "–",
                    label: "Ø Eiweiß",
                    color: .green
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
    }

    private func digestTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct RoutineCardRow: View {
    let item: RoutineWithExercises
    let onStart: () -> Void
    let onStartDeload: () -> Void
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
                        onStartDeload()
                    } label: {
                        Label("Als Deload starten (−20 %)", systemImage: "battery.75")
                    }
                    Divider()
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
