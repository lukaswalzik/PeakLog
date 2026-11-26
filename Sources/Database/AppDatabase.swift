import Foundation
import GRDB

final class AppDatabase {
    static let shared: AppDatabase = makeShared()

    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Migrations.makeMigrator().migrate(dbWriter)
    }

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = appSupportURL.appendingPathComponent("StrongTracker", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("strongtracker.sqlite")
            var config = Configuration()
            config.foreignKeysEnabled = true

            let dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
            return try AppDatabase(dbPool)
        } catch {
            fatalError("Fehler beim Initialisieren der StrongTracker-Datenbank: \(error)")
        }
    }

    static func makeInMemory() -> AppDatabase {
        do {
            var config = Configuration()
            config.foreignKeysEnabled = true
            let dbQueue = try DatabaseQueue(configuration: config)
            return try AppDatabase(dbQueue)
        } catch {
            fatalError("Fehler beim Erstellen der In-Memory-Datenbank: \(error)")
        }
    }
}

// MARK: - Exercise Operations

extension AppDatabase {
    func saveExercise(_ exercise: Exercise) throws {
        try dbWriter.write { db in
            try exercise.save(db)
        }
    }

    func archiveOrDeleteExercise(id: String) throws {
        try dbWriter.write { db in
            let usedInRoutines = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM routine_exercises WHERE exerciseId = ?",
                arguments: [id]
            ) ?? 0
            let usedInWorkouts = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM workout_exercises WHERE exerciseId = ?",
                arguments: [id]
            ) ?? 0

            if usedInRoutines == 0 && usedInWorkouts == 0 {
                _ = try Exercise.deleteOne(db, key: id)
            } else {
                try db.execute(
                    sql: "UPDATE exercises SET isArchived = 1 WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }
}

// MARK: - Routine Operations

extension AppDatabase {
    static func fetchRoutinesWithExercises(in db: Database) throws -> [RoutineWithExercises] {
        let routines = try Routine
            .order(Routine.Columns.sortOrder.asc, Routine.Columns.createdAt.desc)
            .fetchAll(db)

        guard !routines.isEmpty else { return [] }

        let allRoutineExercises = try RoutineExercise
            .order(RoutineExercise.Columns.sortOrder.asc)
            .fetchAll(db)

        let exerciseIds = Set(allRoutineExercises.map { $0.exerciseId })
        let exercisesById: [String: Exercise]
        if exerciseIds.isEmpty {
            exercisesById = [:]
        } else {
            let exercises = try Exercise
                .filter(exerciseIds.contains(Exercise.Columns.id))
                .fetchAll(db)
            exercisesById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        }

        let groupedByRoutine = Dictionary(grouping: allRoutineExercises, by: { $0.routineId })

        return routines.map { routine in
            let items = (groupedByRoutine[routine.id] ?? []).compactMap { re -> RoutineExerciseDetail? in
                guard let exercise = exercisesById[re.exerciseId] else { return nil }
                return RoutineExerciseDetail(routineExercise: re, exercise: exercise)
            }
            return RoutineWithExercises(routine: routine, exercises: items)
        }
    }

    func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) throws {
        try dbWriter.write { db in
            var updatedRoutine = routine
            updatedRoutine.updatedAt = Date()
            try updatedRoutine.save(db)

            try RoutineExercise
                .filter(RoutineExercise.Columns.routineId == updatedRoutine.id)
                .deleteAll(db)

            for (index, item) in exercises.enumerated() {
                var normalized = item
                normalized.routineId = updatedRoutine.id
                normalized.sortOrder = index
                try normalized.insert(db)
            }
        }
    }

    func deleteRoutine(id: String) throws {
        try dbWriter.write { db in
            _ = try Routine.deleteOne(db, key: id)
        }
    }

    func reorderRoutines(ids: [String]) throws {
        try dbWriter.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE routines SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                    arguments: [index, Date(), id]
                )
            }
        }
    }
}
