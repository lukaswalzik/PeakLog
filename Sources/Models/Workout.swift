import Foundation
import GRDB

enum SetType: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case normal
    case warmup
    case dropset
    case failure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Arbeitssatz"
        case .warmup: return "Aufwärmsatz"
        case .dropset: return "Dropset"
        case .failure: return "Muskelversagen"
        }
    }

    var shortBadge: String? {
        switch self {
        case .normal: return nil
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        }
    }
}

struct Workout: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workouts"

    var id: String
    var routineId: String?
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let routineId = Column(CodingKeys.routineId)
        static let name = Column(CodingKeys.name)
        static let startedAt = Column(CodingKeys.startedAt)
        static let finishedAt = Column(CodingKeys.finishedAt)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        routineId: String? = nil,
        name: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
    }
}

struct WorkoutExercise: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_exercises"

    var id: String
    var workoutId: String
    var exerciseId: String
    var sortOrder: Int
    var restSeconds: Int
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workoutId = Column(CodingKeys.workoutId)
        static let exerciseId = Column(CodingKeys.exerciseId)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let restSeconds = Column(CodingKeys.restSeconds)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        workoutId: String,
        exerciseId: String,
        sortOrder: Int,
        restSeconds: Int = 90,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

struct WorkoutSet: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_sets"

    var id: String
    var workoutExerciseId: String
    var setOrder: Int
    var setType: SetType
    var weightKg: Double?
    var reps: Int?
    var isCompleted: Bool
    var completedAt: Date?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workoutExerciseId = Column(CodingKeys.workoutExerciseId)
        static let setOrder = Column(CodingKeys.setOrder)
        static let setType = Column(CodingKeys.setType)
        static let weightKg = Column(CodingKeys.weightKg)
        static let reps = Column(CodingKeys.reps)
        static let isCompleted = Column(CodingKeys.isCompleted)
        static let completedAt = Column(CodingKeys.completedAt)
    }

    init(
        id: String = UUID().uuidString,
        workoutExerciseId: String,
        setOrder: Int,
        setType: SetType = .normal,
        weightKg: Double? = nil,
        reps: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setOrder = setOrder
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

struct PreviousSetReference: Equatable, Hashable {
    var weightKg: Double?
    var reps: Int?
}

struct WorkoutExerciseDetail: Identifiable, Equatable, Hashable {
    var workoutExercise: WorkoutExercise
    var exercise: Exercise
    var sets: [WorkoutSet]
    var previousSets: [Int: PreviousSetReference]

    var id: String { workoutExercise.id }
}

struct WorkoutDetail: Identifiable, Equatable, Hashable {
    var workout: Workout
    var exercises: [WorkoutExerciseDetail]

    var id: String { workout.id }

    var completedSetCount: Int {
        exercises.reduce(0) { sum, ex in
            sum + ex.sets.filter { $0.isCompleted }.count
        }
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalVolumeKg: Double {
        exercises.reduce(0.0) { sum, ex in
            sum + ex.sets.filter { $0.isCompleted }.reduce(0.0) { setSum, set in
                let w = set.weightKg ?? 0
                let r = Double(set.reps ?? 0)
                return setSum + (w * r)
            }
        }
    }
}
