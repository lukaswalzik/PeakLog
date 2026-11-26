import Foundation

enum BackupService {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func exportJSONData(from database: AppDatabase) throws -> Data {
        let payload = try database.exportBackupPayload()
        return try makeEncoder().encode(payload)
    }

    static func decodePayload(from data: Data) throws -> BackupPayload {
        try makeDecoder().decode(BackupPayload.self, from: data)
    }

    static func importPayload(_ payload: BackupPayload, into database: AppDatabase) throws -> BackupImportSummary {
        try database.importBackupPayload(payload)
        return BackupImportSummary(
            exerciseCount: payload.exercises.count,
            routineCount: payload.routines.count,
            workoutCount: payload.workouts.count
        )
    }

    static func defaultFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "StrongTracker-Backup-\(formatter.string(from: date)).json"
    }
}
