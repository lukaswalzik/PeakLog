import Foundation
import GRDB

final class ActiveWorkoutManager: ObservableObject {
    @Published private(set) var activeWorkout: WorkoutDetail?
    @Published var isPresentingSheet: Bool = false
    @Published var lastCompletedRecap: CompletedWorkoutRecap? = nil
    @Published var errorMessage: String?

    /// Hook invoked when a set transitions from incomplete -> completed, passing the exercise's restSeconds.
    var onSetCompleted: ((Int) -> Void)?

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservation()
    }

    var hasActiveWorkout: Bool {
        activeWorkout != nil
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchActiveWorkoutDetail(in: db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Aktives Workout konnte nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] workoutDetail in
                self?.activeWorkout = workoutDetail
                if workoutDetail == nil {
                    self?.isPresentingSheet = false
                }
            }
        )
    }

    func startEmptyWorkout(gymId: String? = nil) {
        guard activeWorkout == nil else {
            isPresentingSheet = true
            return
        }
        do {
            _ = try database.startEmptyWorkout(gymId: gymId)
            isPresentingSheet = true
        } catch {
            errorMessage = "Workout konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func startWorkout(from routine: RoutineWithExercises, gymId: String? = nil, isDeload: Bool = false) {
        guard activeWorkout == nil else {
            isPresentingSheet = true
            return
        }
        do {
            _ = try database.startWorkout(from: routine, gymId: gymId, isDeload: isDeload)
            isPresentingSheet = true
        } catch {
            errorMessage = "Routine konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func moveExercise(workoutExerciseId: String, direction: Int) {
        guard let workoutId = activeWorkout?.workout.id else { return }
        do {
            try database.moveWorkoutExercise(workoutId: workoutId, workoutExerciseId: workoutExerciseId, direction: direction)
        } catch {
            errorMessage = "Übung konnte nicht verschoben werden: \(error.localizedDescription)"
        }
    }

    func updateExerciseRestSeconds(workoutExerciseId: String, restSeconds: Int) {
        do {
            try database.updateWorkoutExerciseRestSeconds(workoutExerciseId: workoutExerciseId, restSeconds: restSeconds)
        } catch {
            errorMessage = "Pausenzeit konnte nicht geändert werden: \(error.localizedDescription)"
        }
    }

    func updateGym(gymId: String?) {
        guard let workoutId = activeWorkout?.workout.id else { return }
        do {
            try database.updateWorkoutGym(workoutId: workoutId, gymId: gymId)
        } catch {
            errorMessage = "Gym konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func addExercises(_ exercises: [Exercise]) {
        guard let workoutId = activeWorkout?.workout.id, !exercises.isEmpty else { return }
        do {
            try database.addExercisesToWorkout(workoutId: workoutId, exercises: exercises)
        } catch {
            errorMessage = "Übungen konnten nicht hinzugefügt werden: \(error.localizedDescription)"
        }
    }

    func removeExercise(workoutExerciseId: String) {
        do {
            try database.removeWorkoutExercise(id: workoutExerciseId)
        } catch {
            errorMessage = "Übung konnte nicht entfernt werden: \(error.localizedDescription)"
        }
    }

    func addSet(to workoutExerciseId: String) {
        do {
            try database.addSet(to: workoutExerciseId)
        } catch {
            errorMessage = "Satz konnte nicht hinzugefügt werden: \(error.localizedDescription)"
        }
    }

    func updateSet(_ set: WorkoutSet) {
        do {
            try database.updateSet(set)
        } catch {
            errorMessage = "Satz konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func toggleSetCompleted(
        _ set: WorkoutSet,
        exerciseDetail: WorkoutExerciseDetail,
        previous: PreviousSetReference?
    ) {
        var updated = set
        let willComplete = !set.isCompleted
        updated.isCompleted = willComplete
        updated.completedAt = willComplete ? Date() : nil

        if willComplete {
            if updated.weightKg == nil, let prevWeight = previous?.weightKg {
                updated.weightKg = prevWeight
            }
            if updated.reps == nil, let prevReps = previous?.reps {
                updated.reps = prevReps
            }
        }

        do {
            try database.updateSet(updated)
            if willComplete {
                let shouldStartRest = shouldTriggerRestTimer(for: exerciseDetail)
                if shouldStartRest {
                    onSetCompleted?(exerciseDetail.workoutExercise.restSeconds)
                }
            }
        } catch {
            errorMessage = "Satz-Status konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    /// Only start rest timer when this exercise is NOT followed by another exercise in the same superset group.
    private func shouldTriggerRestTimer(for exerciseDetail: WorkoutExerciseDetail) -> Bool {
        guard let group = exerciseDetail.workoutExercise.supersetGroup,
              let exercises = activeWorkout?.exercises,
              let idx = exercises.firstIndex(where: { $0.id == exerciseDetail.id }) else {
            return true
        }
        if idx + 1 < exercises.count, exercises[idx + 1].workoutExercise.supersetGroup == group {
            return false
        }
        return true
    }

    func linkSupersetWithNext(workoutExerciseId: String) {
        guard let workoutId = activeWorkout?.workout.id else { return }
        do {
            try database.linkSupersetWithNext(workoutId: workoutId, workoutExerciseId: workoutExerciseId)
        } catch {
            errorMessage = "Supersatz konnte nicht verknüpft werden: \(error.localizedDescription)"
        }
    }

    func clearSuperset(workoutExerciseId: String) {
        do {
            try database.clearSuperset(workoutExerciseId: workoutExerciseId)
        } catch {
            errorMessage = "Supersatz konnte nicht gelöst werden: \(error.localizedDescription)"
        }
    }

    func saveSetupNote(exerciseId: String, note: String) {
        let gymId = activeWorkout?.workout.gymId
        do {
            try database.saveExerciseGymNote(exerciseId: exerciseId, gymId: gymId, note: note)
        } catch {
            errorMessage = "Setup-Notiz konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func replaceExercise(workoutExerciseId: String, with newExercise: Exercise) {
        do {
            try database.replaceWorkoutExercise(workoutExerciseId: workoutExerciseId, newExercise: newExercise)
        } catch {
            errorMessage = "Übung konnte nicht ersetzt werden: \(error.localizedDescription)"
        }
    }

    func addWarmupSets(for exerciseDetail: WorkoutExerciseDetail) {
        // Determine working weight from first non-warmup set, or from previous session's top set
        let workingWeight: Double = exerciseDetail.sets
            .first(where: { $0.setType != .warmup && ($0.weightKg ?? 0) > 0 })?.weightKg
            ?? exerciseDetail.previousSets.values.compactMap { $0.weightKg }.max()
            ?? 40.0
        do {
            try database.insertWarmupSets(for: exerciseDetail.id, workingWeightKg: workingWeight)
        } catch {
            errorMessage = "Aufwärmsätze konnten nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    func deleteSet(id: String, workoutExerciseId: String) {
        do {
            try database.deleteSet(id: id, workoutExerciseId: workoutExerciseId)
        } catch {
            errorMessage = "Satz konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func updateHeader(name: String, notes: String?) {
        guard let workoutId = activeWorkout?.workout.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Freies Training" : trimmedName
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes

        do {
            try database.updateWorkoutHeader(id: workoutId, name: finalName, notes: finalNotes)
        } catch {
            errorMessage = "Workout-Details konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func finishWorkout(updateRoutine: Bool = false) {
        guard let detail = activeWorkout else { return }
        let workoutId = detail.workout.id

        // Snapshot recap before finishing
        let finishedAt = Date()
        let durationSeconds = max(60, Int(finishedAt.timeIntervalSince(detail.workout.startedAt)))
        var prDescriptions: [String] = []
        for ex in detail.exercises {
            let prSets = ex.sets.filter { ex.isLivePR($0) }
            if let bestPR = prSets.max(by: {
                OneRepMaxCalculator.estimatedOneRepMax(weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0) <
                OneRepMaxCalculator.estimatedOneRepMax(weightKg: $1.weightKg ?? 0, reps: $1.reps ?? 0)
            }), let w = bestPR.weightKg, let r = bestPR.reps {
                prDescriptions.append("\(ex.exercise.name): \(Formatters.weight(w)) kg × \(r)")
            }
        }
        let recap = CompletedWorkoutRecap(
            id: workoutId,
            workoutName: detail.workout.name,
            gymName: detail.gymName,
            finishedAt: finishedAt,
            durationSeconds: durationSeconds,
            exerciseCount: detail.exercises.count,
            completedSets: detail.completedSetCount,
            totalVolumeKg: detail.totalVolumeKg,
            prDescriptions: prDescriptions
        )

        do {
            try database.finishWorkout(id: workoutId, updateRoutine: updateRoutine)
            isPresentingSheet = false
            if recap.completedSets > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.lastCompletedRecap = recap
                }
            }
        } catch {
            errorMessage = "Workout konnte nicht abgeschlossen werden: \(error.localizedDescription)"
        }
    }

    func discardWorkout() {
        guard let workoutId = activeWorkout?.workout.id else { return }
        do {
            try database.discardWorkout(id: workoutId)
            isPresentingSheet = false
        } catch {
            errorMessage = "Workout konnte nicht verworfen werden: \(error.localizedDescription)"
        }
    }
}
