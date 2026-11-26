import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @EnvironmentObject private var activeWorkoutManager: ActiveWorkoutManager
    @EnvironmentObject private var restTimerManager: RestTimerManager
    @EnvironmentObject private var gymStore: GymStore

    @State private var workoutName: String = ""
    @State private var workoutNotes: String = ""
    @State private var isShowingExercisePicker: Bool = false
    @State private var isShowingFinishAlert: Bool = false
    @State private var isShowingDiscardAlert: Bool = false
    @State private var hasLoadedHeader: Bool = false
    @State private var fullscreenPhoto: (image: UIImage, title: String)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let detail = activeWorkoutManager.activeWorkout {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard(detail: detail)

                            if detail.exercises.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "dumbbell")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary)
                                    Text("Noch keine Übungen")
                                        .font(.headline)
                                    Text("Füge deine erste Übung hinzu, um Sätze zu loggen.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            } else {
                                ForEach(detail.exercises) { exerciseDetail in
                                    exerciseCard(exerciseDetail)
                                }
                            }

                            VStack(spacing: 12) {
                                Button {
                                    isShowingExercisePicker = true
                                } label: {
                                    Label("Übung hinzufügen", systemImage: "plus.circle.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)

                                Button(role: .destructive) {
                                    isShowingDiscardAlert = true
                                } label: {
                                    Text("Workout verwerfen")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .safeAreaInset(edge: .bottom) {
                        if restTimerManager.isRunning {
                            RestTimerBarView(timerManager: restTimerManager)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .onAppear {
                        if !hasLoadedHeader {
                            workoutName = detail.workout.name
                            workoutNotes = detail.workout.notes ?? ""
                            hasLoadedHeader = true
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "Kein aktives Workout",
                        message: "Starte ein Training im Tab „Start“."
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            dismissKeyboard()
                            activeWorkoutManager.isPresentingSheet = false
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.headline)
                        }
                        .accessibilityLabel("Workout minimieren")

                        Menu {
                            Section("Pausentimer starten") {
                                Button("60 Sekunden") { restTimerManager.start(seconds: 60) }
                                Button("90 Sekunden") { restTimerManager.start(seconds: 90) }
                                Button("2 Minuten") { restTimerManager.start(seconds: 120) }
                                Button("3 Minuten") { restTimerManager.start(seconds: 180) }
                            }
                            Section {
                                Button {
                                    restTimerManager.autoStartEnabled.toggle()
                                } label: {
                                    Label(
                                        restTimerManager.autoStartEnabled ? "Auto-Pause: An" : "Auto-Pause: Aus",
                                        systemImage: restTimerManager.autoStartEnabled ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: restTimerManager.isRunning ? "timer.circle.fill" : "timer")
                                .font(.headline)
                                .foregroundColor(restTimerManager.isRunning ? .accentColor : .primary)
                        }
                        .accessibilityLabel("Pausentimer")
                    }
                }

                ToolbarItem(placement: .principal) {
                    if let startedAt = activeWorkoutManager.activeWorkout?.workout.startedAt {
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(Formatters.elapsedDuration(from: startedAt, to: context.date))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Beenden") {
                        dismissKeyboard()
                        isShowingFinishAlert = true
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .disabled(activeWorkoutManager.activeWorkout == nil)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerView { pickedExercises in
                    activeWorkoutManager.addExercises(pickedExercises)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { fullscreenPhoto != nil },
                    set: { if !$0 { fullscreenPhoto = nil } }
                )
            ) {
                if let photo = fullscreenPhoto {
                    FullscreenImageView(image: photo.image, caption: photo.title)
                }
            }
            .alert("Workout abschließen?", isPresented: $isShowingFinishAlert) {
                Button("Abschließen", role: .none) {
                    activeWorkoutManager.finishWorkout(updateRoutine: false)
                }
                if activeWorkoutManager.activeWorkout?.workout.routineId != nil {
                    Button("Abschließen & Routine updaten", role: .none) {
                        activeWorkoutManager.finishWorkout(updateRoutine: true)
                    }
                }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                if let detail = activeWorkoutManager.activeWorkout {
                    if detail.completedSetCount == 0 {
                        Text("Du hast noch keinen Satz abgehakt. Möchtest du das Workout trotzdem abschließen?")
                    } else if detail.completedSetCount < detail.totalSetCount {
                        Text("\(detail.completedSetCount) von \(detail.totalSetCount) Sätzen abgehakt. Nicht abgehakte Sätze werden beim Abschließen entfernt.")
                    } else {
                        Text("Alle \(detail.completedSetCount) Sätze sind abgehakt. Training jetzt speichern?")
                    }
                }
            }
            .alert("Workout verwerfen?", isPresented: $isShowingDiscardAlert) {
                Button("Verwerfen", role: .destructive) {
                    activeWorkoutManager.discardWorkout()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle bisher eingetragenen Sätze dieses laufenden Trainings gehen verloren.")
            }
        }
    }

    private func headerCard(detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Workout-Name", text: $workoutName)
                .font(.title3)
                .fontWeight(.bold)
                .onChange(of: workoutName) { newValue in
                    activeWorkoutManager.updateHeader(name: newValue, notes: workoutNotes)
                }

            TextField("Notizen zum Training (optional)", text: $workoutNotes, axis: .vertical)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1...3)
                .onChange(of: workoutNotes) { newValue in
                    activeWorkoutManager.updateHeader(name: workoutName, notes: newValue)
                }

            HStack(spacing: 12) {
                Label("\(detail.completedSetCount)/\(detail.totalSetCount) Sätze", systemImage: "checkmark.circle")
                Label("\(Formatters.weight(detail.totalVolumeKg)) kg", systemImage: "scalemass")

                Spacer()

                if !gymStore.gyms.isEmpty {
                    Menu {
                        Button {
                            activeWorkoutManager.updateGym(gymId: nil)
                        } label: {
                            HStack {
                                Text("Kein Gym")
                                if detail.workout.gymId == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        ForEach(gymStore.gyms) { gym in
                            Button {
                                activeWorkoutManager.updateGym(gymId: gym.id)
                            } label: {
                                HStack {
                                    Text(gym.name)
                                    if detail.workout.gymId == gym.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(detail.gymName ?? "Gym wählen")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func supersetColor(for group: Int) -> Color {
        let palette: [Color] = [.purple, .orange, .teal, .pink, .indigo]
        return palette[abs(group - 1) % palette.count]
    }

    private func exerciseCard(_ exerciseDetail: WorkoutExerciseDetail) -> some View {
        let supersetGroup = exerciseDetail.workoutExercise.supersetGroup
        let exercises = activeWorkoutManager.activeWorkout?.exercises ?? []
        let currentIndex = exercises.firstIndex(where: { $0.id == exerciseDetail.id })
        let hasNextExercise = currentIndex != nil && (currentIndex! + 1 < exercises.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    if let img = MediaStorage.shared.loadExerciseImage(for: exerciseDetail.exercise) {
                        fullscreenPhoto = (img, exerciseDetail.exercise.name)
                    }
                } label: {
                    ExerciseThumbnailView(exercise: exerciseDetail.exercise, size: 42)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exerciseDetail.exercise.name)
                            .font(.headline)
                            .foregroundColor(.accentColor)

                        if let group = supersetGroup {
                            Text("Supersatz \(group)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(supersetColor(for: group).opacity(0.18))
                                .foregroundColor(supersetColor(for: group))
                                .clipShape(Capsule())
                        }
                    }

                    Text("\(exerciseDetail.exercise.muscleGroup.displayName) · Pause \(Formatters.restDuration(exerciseDetail.workoutExercise.restSeconds))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    if hasNextExercise {
                        Button {
                            activeWorkoutManager.linkSupersetWithNext(workoutExerciseId: exerciseDetail.id)
                        } label: {
                            Label("Mit nächster als Supersatz", systemImage: "link")
                        }
                    }
                    if supersetGroup != nil {
                        Button {
                            activeWorkoutManager.clearSuperset(workoutExerciseId: exerciseDetail.id)
                        } label: {
                            Label("Supersatz lösen", systemImage: "link.badge.plus")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        activeWorkoutManager.removeExercise(workoutExerciseId: exerciseDetail.id)
                    } label: {
                        Label("Übung entfernen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Column headers
            HStack(spacing: 8) {
                Text("Satz")
                    .frame(width: 32, alignment: .center)
                Text("Vorher")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("kg")
                    .frame(width: 72, alignment: .center)
                Text("Wdh.")
                    .frame(width: 58, alignment: .center)
                Image(systemName: "checkmark")
                    .frame(width: 36, alignment: .center)
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)

            VStack(spacing: 4) {
                ForEach(exerciseDetail.sets) { set in
                    WorkoutSetRowView(
                        set: set,
                        previous: exerciseDetail.previousSets[set.setOrder],
                        isPR: exerciseDetail.isLivePR(set),
                        onUpdate: { updated in
                            activeWorkoutManager.updateSet(updated)
                        },
                        onToggleComplete: {
                            activeWorkoutManager.toggleSetCompleted(
                                set,
                                exerciseDetail: exerciseDetail,
                                previous: exerciseDetail.previousSets[set.setOrder]
                            )
                        },
                        onDelete: {
                            activeWorkoutManager.deleteSet(
                                id: set.id,
                                workoutExerciseId: exerciseDetail.id
                            )
                        }
                    )
                }
            }
            .padding(.horizontal, 4)

            Button {
                activeWorkoutManager.addSet(to: exerciseDetail.id)
            } label: {
                Label("Satz hinzufügen", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    supersetGroup.map { supersetColor(for: $0).opacity(0.6) } ?? Color.primary.opacity(0.06),
                    lineWidth: supersetGroup != nil ? 2 : 1
                )
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct ActiveWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        ActiveWorkoutView()
            .environmentObject(ActiveWorkoutManager(database: db))
            .environmentObject(ExerciseStore(database: db))
            .environmentObject(RestTimerManager())
    }
}
