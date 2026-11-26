import Foundation
import GRDB

final class ActiveWorkoutManager: ObservableObject {
    @Published private(set) var activeWorkout: WorkoutDetail?
    @Published var isPresentingSheet: Bool = false
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

    func startWorkout(from routine: RoutineWithExercises, gymId: String? = nil) {
        guard activeWorkout == nil else {
            isPresentingSheet = true
            return
        }
        do {
            _ = try database.startWorkout(from: routine, gymId: gymId)
            isPresentingSheet = true
        } catch {
            errorMessage = "Routine konnte nicht gestartet werden: \(error.localizedDescription)"
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
        restSeconds: Int,
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
                onSetCompleted?(restSeconds)
            }
        } catch {
            errorMessage = "Satz-Status konnte nicht gespeichert werden: \(error.localizedDescription)"
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

    func finishWorkout() {
        guard let workoutId = activeWorkout?.workout.id else { return }
        do {
            try database.finishWorkout(id: workoutId)
            isPresentingSheet = false
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
