import Foundation
import GRDB

final class HistoryStore: ObservableObject {
    @Published private(set) var completedWorkouts: [WorkoutDetail] = []
    @Published private(set) var exercisePRs: [ExercisePRSummary] = []
    @Published var errorMessage: String?

    let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservation()
    }

    var totalCompletedWorkouts: Int {
        completedWorkouts.count
    }

    var totalVolumeKg: Double {
        completedWorkouts.reduce(0.0) { $0 + $1.totalVolumeKg }
    }

    var totalCompletedSets: Int {
        completedWorkouts.reduce(0) { $0 + $1.completedSetCount }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> ([WorkoutDetail], [ExercisePRSummary]) in
            let workouts = try AppDatabase.fetchCompletedWorkouts(in: db)
            let prs = try AppDatabase.fetchAllExercisePRs(in: db)
            return (workouts, prs)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Verlauf konnte nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] workouts, prs in
                self?.completedWorkouts = workouts
                self?.exercisePRs = prs
            }
        )
    }

    func fetchStats(forExerciseId exerciseId: String) -> ExerciseStats {
        do {
            return try database.dbWriter.read { db in
                try AppDatabase.fetchExerciseStats(exerciseId: exerciseId, in: db)
            }
        } catch {
            errorMessage = "Statistiken konnten nicht geladen werden: \(error.localizedDescription)"
            return .empty
        }
    }

    func fetchHeartRateSamples(forWorkoutId workoutId: String) -> [WorkoutHeartRateSample] {
        do {
            return try database.fetchHeartRateSamples(forWorkoutId: workoutId)
        } catch {
            errorMessage = "Herzfrequenz-Daten konnten nicht geladen werden: \(error.localizedDescription)"
            return []
        }
    }

    func deleteWorkout(id: String) {
        do {
            try database.deleteWorkout(id: id)
        } catch {
            errorMessage = "Workout konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
