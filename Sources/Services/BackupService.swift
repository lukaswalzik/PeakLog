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

    static func exportJSONData(from database: AppDatabase, includePhotos: Bool = false) throws -> Data {
        var payload = try database.exportBackupPayload()
        if includePhotos {
            var mediaFiles: [EmbeddedMediaFile] = []
            for ex in payload.exercises {
                if let fname = ex.imageFilename,
                   let data = MediaStorage.shared.loadRawData(filename: fname, in: .exercises) {
                    mediaFiles.append(
                        EmbeddedMediaFile(
                            folder: MediaFolder.exercises.rawValue,
                            filename: fname,
                            base64Data: data.base64EncodedString()
                        )
                    )
                }
            }
            for photo in payload.bodyweightPhotos ?? [] {
                if let data = MediaStorage.shared.loadRawData(filename: photo.imageFilename, in: .bodyweight) {
                    mediaFiles.append(
                        EmbeddedMediaFile(
                            folder: MediaFolder.bodyweight.rawValue,
                            filename: photo.imageFilename,
                            base64Data: data.base64EncodedString()
                        )
                    )
                }
            }
            payload.embeddedMedia = mediaFiles
        }
        return try makeEncoder().encode(payload)
    }

    static func decodePayload(from data: Data) throws -> BackupPayload {
        try makeDecoder().decode(BackupPayload.self, from: data)
    }

    static func importPayload(_ payload: BackupPayload, into database: AppDatabase) throws -> BackupImportSummary {
        try database.importBackupPayload(payload)

        var restoredMedia = 0
        for media in payload.embeddedMedia ?? [] {
            if let folder = MediaFolder(rawValue: media.folder),
               let data = Data(base64Encoded: media.base64Data) {
                try? MediaStorage.shared.saveRawData(data, filename: media.filename, in: folder)
                restoredMedia += 1
            }
        }

        return BackupImportSummary(
            exerciseCount: payload.exercises.count,
            routineCount: payload.routines.count,
            workoutCount: payload.workouts.count,
            mediaCount: restoredMedia
        )
    }

    static func defaultFilename(includePhotos: Bool = false, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let suffix = includePhotos ? "-Komplett-Mit-Fotos" : ""
        return "StrongTracker-Backup\(suffix)-\(formatter.string(from: date)).json"
    }
}
