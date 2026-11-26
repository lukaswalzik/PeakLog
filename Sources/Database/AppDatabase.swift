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
