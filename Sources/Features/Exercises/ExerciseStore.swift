import Foundation
import GRDB

final class ExerciseStore: ObservableObject {
    @Published private(set) var exercises: [Exercise] = []
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservation()
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try Exercise
                .filter(Exercise.Columns.isArchived == false)
                .order(Exercise.Columns.name.collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Übungen konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] exercises in
                self?.exercises = exercises
            }
        )
    }

    func save(_ exercise: Exercise) {
        do {
            try database.saveExercise(exercise)
        } catch {
            errorMessage = "Übung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func archiveOrDelete(_ exercise: Exercise) {
        do {
            try database.archiveOrDeleteExercise(id: exercise.id)
        } catch {
            errorMessage = "Übung konnte nicht entfernt werden: \(error.localizedDescription)"
        }
    }
}
