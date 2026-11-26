import Foundation
import GRDB

struct DailyWaterLog: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "daily_water_logs"

    var dayKey: String
    var milliliters: Int

    var id: String { dayKey }

    enum Columns {
        static let dayKey = Column(CodingKeys.dayKey)
        static let milliliters = Column(CodingKeys.milliliters)
    }
}

struct Supplement: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "supplements"

    var id: String
    var name: String
    var dosage: String?
    var sortOrder: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let dosage = Column(CodingKeys.dosage)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.sortOrder = sortOrder
    }
}

struct SupplementLog: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "supplement_logs"

    var id: String
    var supplementId: String
    var dayKey: String
    var takenAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let supplementId = Column(CodingKeys.supplementId)
        static let dayKey = Column(CodingKeys.dayKey)
        static let takenAt = Column(CodingKeys.takenAt)
    }

    init(
        id: String = UUID().uuidString,
        supplementId: String,
        dayKey: String,
        takenAt: Date = Date()
    ) {
        self.id = id
        self.supplementId = supplementId
        self.dayKey = dayKey
        self.takenAt = takenAt
    }
}

struct BodyMeasurement: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "body_measurements"

    var id: String
    var recordedAt: Date
    var chestCm: Double?
    var waistCm: Double?
    var armCm: Double?
    var thighCm: Double?
    var neckCm: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, recordedAt, chestCm, waistCm, armCm, thighCm, neckCm, notes
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recordedAt = Column(CodingKeys.recordedAt)
        static let chestCm = Column(CodingKeys.chestCm)
        static let waistCm = Column(CodingKeys.waistCm)
        static let armCm = Column(CodingKeys.armCm)
        static let thighCm = Column(CodingKeys.thighCm)
        static let neckCm = Column(CodingKeys.neckCm)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        recordedAt: Date = Date(),
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        armCm: Double? = nil,
        thighCm: Double? = nil,
        neckCm: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.armCm = armCm
        self.thighCm = thighCm
        self.neckCm = neckCm
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        chestCm = try c.decodeIfPresent(Double.self, forKey: .chestCm)
        waistCm = try c.decodeIfPresent(Double.self, forKey: .waistCm)
        armCm = try c.decodeIfPresent(Double.self, forKey: .armCm)
        thighCm = try c.decodeIfPresent(Double.self, forKey: .thighCm)
        neckCm = try c.decodeIfPresent(Double.self, forKey: .neckCm)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct ReadinessLog: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readiness_logs"

    var id: String
    var dayKey: String
    var recordedAt: Date
    var readinessScore: Int
    var sleepHours: Double
    var soreness: Int
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let dayKey = Column(CodingKeys.dayKey)
        static let recordedAt = Column(CodingKeys.recordedAt)
        static let readinessScore = Column(CodingKeys.readinessScore)
        static let sleepHours = Column(CodingKeys.sleepHours)
        static let soreness = Column(CodingKeys.soreness)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        dayKey: String,
        recordedAt: Date = Date(),
        readinessScore: Int = 80,
        sleepHours: Double = 7.5,
        soreness: Int = 2,
        notes: String? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.recordedAt = recordedAt
        self.readinessScore = readinessScore
        self.sleepHours = sleepHours
        self.soreness = soreness
        self.notes = notes
    }
}

struct DailyNutritionPoint: Identifiable, Equatable {
    let date: Date
    let calories: Double
    let protein: Double

    var id: Date { date }
}

enum DayKeyFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
