import Foundation
import GRDB

struct BodyweightEntry: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bodyweight_entries"

    var id: String
    var recordedAt: Date
    var weightKg: Double
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recordedAt = Column(CodingKeys.recordedAt)
        static let weightKg = Column(CodingKeys.weightKg)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        recordedAt: Date = Date(),
        weightKg: Double,
        notes: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.weightKg = weightKg
        self.notes = notes
    }
}

struct BodyweightPhoto: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bodyweight_photos"

    var id: String
    var entryId: String
    var imageFilename: String
    var caption: String?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let entryId = Column(CodingKeys.entryId)
        static let imageFilename = Column(CodingKeys.imageFilename)
        static let caption = Column(CodingKeys.caption)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: String = UUID().uuidString,
        entryId: String,
        imageFilename: String,
        caption: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.entryId = entryId
        self.imageFilename = imageFilename
        self.caption = caption
        self.createdAt = createdAt
    }
}

struct BodyweightEntryWithPhotos: Identifiable, Equatable, Hashable {
    var entry: BodyweightEntry
    var photos: [BodyweightPhoto]

    var id: String { entry.id }
}

struct PhotoTimelineItem: Identifiable, Equatable, Hashable {
    let photo: BodyweightPhoto
    let recordedAt: Date
    let weightKg: Double

    var id: String { photo.id }

    var labelText: String {
        let base = "\(Formatters.weight(weightKg)) kg · \(Formatters.shortDate(recordedAt))"
        if let caption = photo.caption, !caption.isEmpty {
            return "\(base) (\(caption))"
        }
        return base
    }
}
