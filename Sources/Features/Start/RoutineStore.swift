import Foundation
import GRDB

final class RoutineStore: ObservableObject {
    @Published private(set) var routines: [RoutineWithExercises] = []
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservation()
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchRoutinesWithExercises(in: db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Routinen konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] routines in
                self?.routines = routines
            }
        )
    }

    func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) {
        do {
            try database.saveRoutine(routine, exercises: exercises)
        } catch {
            errorMessage = "Routine konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteRoutine(id: String) {
        do {
            try database.deleteRoutine(id: id)
        } catch {
            errorMessage = "Routine konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func moveRoutines(from source: IndexSet, to destination: Int) {
        var reordered = routines
        reordered.move(fromOffsets: source, toOffset: destination)
        let ids = reordered.map { $0.id }
        do {
            try database.reorderRoutines(ids: ids)
        } catch {
            errorMessage = "Reihenfolge konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
