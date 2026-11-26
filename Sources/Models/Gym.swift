import Foundation
import GRDB

struct Gym: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "gyms"

    var id: String
    var name: String
    var notes: String?
    var sortOrder: Int
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let notes = Column(CodingKeys.notes)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
