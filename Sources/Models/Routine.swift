import Foundation
import GRDB

struct Routine: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "routines"

    var id: String
    var name: String
    var notes: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let notes = Column(CodingKeys.notes)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct RoutineExercise: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "routine_exercises"

    var id: String
    var routineId: String
    var exerciseId: String
    var sortOrder: Int
    var targetSets: Int
    var targetReps: Int?
    var restSeconds: Int?
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let routineId = Column(CodingKeys.routineId)
        static let exerciseId = Column(CodingKeys.exerciseId)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let targetSets = Column(CodingKeys.targetSets)
        static let targetReps = Column(CodingKeys.targetReps)
        static let restSeconds = Column(CodingKeys.restSeconds)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        routineId: String,
        exerciseId: String,
        sortOrder: Int,
        targetSets: Int = 3,
        targetReps: Int? = 8,
        restSeconds: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

struct RoutineExerciseDetail: Identifiable, Equatable, Hashable {
    var routineExercise: RoutineExercise
    var exercise: Exercise

    var id: String { routineExercise.id }

    var effectiveRestSeconds: Int {
        routineExercise.restSeconds ?? exercise.defaultRestSeconds
    }
}

struct RoutineWithExercises: Identifiable, Equatable, Hashable {
    var routine: Routine
    var exercises: [RoutineExerciseDetail]

    var id: String { routine.id }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.routineExercise.targetSets }
    }
}
