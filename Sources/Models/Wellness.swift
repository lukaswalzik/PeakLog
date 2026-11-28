import Foundation
import GRDB
import SwiftUI

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

enum SaunaType: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case finnish
    case bio
    case steam
    case infrared

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .finnish: return "Finnische Sauna"
        case .bio: return "Bio-Sauna"
        case .steam: return "Dampfbad"
        case .infrared: return "Infrarotkabine"
        }
    }

    var shortName: String {
        switch self {
        case .finnish: return "Finnisch"
        case .bio: return "Bio-Sauna"
        case .steam: return "Dampfbad"
        case .infrared: return "Infrarot"
        }
    }

    var defaultTemperatureCelsius: Int {
        switch self {
        case .finnish: return 90
        case .bio: return 60
        case .steam: return 48
        case .infrared: return 55
        }
    }

    var systemImage: String {
        switch self {
        case .finnish: return "flame.fill"
        case .bio: return "leaf.fill"
        case .steam: return "cloud.fog.fill"
        case .infrared: return "sun.max.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .finnish: return .orange
        case .bio: return .green
        case .steam: return .cyan
        case .infrared: return .red
        }
    }
}

struct SaunaSession: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sauna_sessions"

    var id: String
    var startedAt: Date
    var saunaType: SaunaType
    var temperatureCelsius: Int
    var rounds: Int
    var totalDurationMinutes: Int
    var coldPlungeDone: Bool
    var coldPlungeMinutes: Int
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var feeling: Int
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let startedAt = Column(CodingKeys.startedAt)
        static let saunaType = Column(CodingKeys.saunaType)
        static let temperatureCelsius = Column(CodingKeys.temperatureCelsius)
        static let rounds = Column(CodingKeys.rounds)
        static let totalDurationMinutes = Column(CodingKeys.totalDurationMinutes)
        static let coldPlungeDone = Column(CodingKeys.coldPlungeDone)
        static let coldPlungeMinutes = Column(CodingKeys.coldPlungeMinutes)
        static let avgHeartRate = Column(CodingKeys.avgHeartRate)
        static let maxHeartRate = Column(CodingKeys.maxHeartRate)
        static let feeling = Column(CodingKeys.feeling)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        saunaType: SaunaType = .finnish,
        temperatureCelsius: Int = 90,
        rounds: Int = 3,
        totalDurationMinutes: Int = 36,
        coldPlungeDone: Bool = true,
        coldPlungeMinutes: Int = 0,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        feeling: Int = 4,
        notes: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.saunaType = saunaType
        self.temperatureCelsius = temperatureCelsius
        self.rounds = max(1, rounds)
        self.totalDurationMinutes = max(1, totalDurationMinutes)
        self.coldPlungeDone = coldPlungeDone
        self.coldPlungeMinutes = max(0, coldPlungeMinutes)
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.feeling = max(1, min(5, feeling))
        self.notes = notes
    }
}
