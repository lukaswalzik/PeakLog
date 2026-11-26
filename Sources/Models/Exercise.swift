import Foundation
import GRDB

enum MuscleGroup: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case chest
    case back
    case shoulders
    case legs
    case biceps
    case triceps
    case core
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Brust"
        case .back: return "Rücken"
        case .shoulders: return "Schultern"
        case .legs: return "Beine"
        case .biceps: return "Bizeps"
        case .triceps: return "Trizeps"
        case .core: return "Core"
        case .other: return "Sonstiges"
        }
    }
}

enum Equipment: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Langhantel"
        case .dumbbell: return "Kurzhantel"
        case .machine: return "Maschine"
        case .cable: return "Kabelzug"
        case .bodyweight: return "Körpergewicht"
        case .kettlebell: return "Kettlebell"
        case .other: return "Sonstiges"
        }
    }
}

struct Exercise: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exercises"

    var id: String
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: Equipment
    var defaultRestSeconds: Int
    var isCustom: Bool
    var isArchived: Bool
    var notes: String?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let muscleGroup = Column(CodingKeys.muscleGroup)
        static let equipment = Column(CodingKeys.equipment)
        static let defaultRestSeconds = Column(CodingKeys.defaultRestSeconds)
        static let isCustom = Column(CodingKeys.isCustom)
        static let isArchived = Column(CodingKeys.isArchived)
        static let notes = Column(CodingKeys.notes)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        muscleGroup: MuscleGroup,
        equipment: Equipment,
        defaultRestSeconds: Int = 90,
        isCustom: Bool = true,
        isArchived: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.defaultRestSeconds = defaultRestSeconds
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.notes = notes
        self.createdAt = createdAt
    }
}
