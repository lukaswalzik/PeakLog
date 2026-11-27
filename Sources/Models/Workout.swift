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
    var gymId: String?
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var notes: String?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var minHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case id, routineId, gymId, name, startedAt, finishedAt, notes, avgHeartRate, maxHeartRate, minHeartRate
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let routineId = Column(CodingKeys.routineId)
        static let gymId = Column(CodingKeys.gymId)
        static let name = Column(CodingKeys.name)
        static let startedAt = Column(CodingKeys.startedAt)
        static let finishedAt = Column(CodingKeys.finishedAt)
        static let notes = Column(CodingKeys.notes)
        static let avgHeartRate = Column(CodingKeys.avgHeartRate)
        static let maxHeartRate = Column(CodingKeys.maxHeartRate)
        static let minHeartRate = Column(CodingKeys.minHeartRate)
    }

    init(
        id: String = UUID().uuidString,
        routineId: String? = nil,
        gymId: String? = nil,
        name: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        notes: String? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        minHeartRate: Int? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.gymId = gymId
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        routineId = try c.decodeIfPresent(String.self, forKey: .routineId)
        gymId = try c.decodeIfPresent(String.self, forKey: .gymId)
        name = try c.decode(String.self, forKey: .name)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        avgHeartRate = try c.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        maxHeartRate = try c.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        minHeartRate = try c.decodeIfPresent(Int.self, forKey: .minHeartRate)
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
    var supersetGroup: Int?

    enum CodingKeys: String, CodingKey {
        case id, workoutId, exerciseId, sortOrder, restSeconds, notes, supersetGroup
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workoutId = Column(CodingKeys.workoutId)
        static let exerciseId = Column(CodingKeys.exerciseId)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let restSeconds = Column(CodingKeys.restSeconds)
        static let notes = Column(CodingKeys.notes)
        static let supersetGroup = Column(CodingKeys.supersetGroup)
    }

    init(
        id: String = UUID().uuidString,
        workoutId: String,
        exerciseId: String,
        sortOrder: Int,
        restSeconds: Int = 90,
        notes: String? = nil,
        supersetGroup: Int? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.notes = notes
        self.supersetGroup = supersetGroup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workoutId = try c.decode(String.self, forKey: .workoutId)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        supersetGroup = try c.decodeIfPresent(Int.self, forKey: .supersetGroup)
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
    var rir: Int?
    var isCompleted: Bool
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, workoutExerciseId, setOrder, setType, weightKg, reps, rir, isCompleted, completedAt
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workoutExerciseId = Column(CodingKeys.workoutExerciseId)
        static let setOrder = Column(CodingKeys.setOrder)
        static let setType = Column(CodingKeys.setType)
        static let weightKg = Column(CodingKeys.weightKg)
        static let reps = Column(CodingKeys.reps)
        static let rir = Column(CodingKeys.rir)
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
        rir: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setOrder = setOrder
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workoutExerciseId = try c.decode(String.self, forKey: .workoutExerciseId)
        setOrder = try c.decode(Int.self, forKey: .setOrder)
        setType = try c.decodeIfPresent(SetType.self, forKey: .setType) ?? .normal
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct ExerciseGymNote: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exercise_gym_notes"

    var id: String
    var exerciseId: String
    var gymId: String?
    var note: String
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let exerciseId = Column(CodingKeys.exerciseId)
        static let gymId = Column(CodingKeys.gymId)
        static let note = Column(CodingKeys.note)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(
        id: String = UUID().uuidString,
        exerciseId: String,
        gymId: String? = nil,
        note: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.gymId = gymId
        self.note = note
        self.updatedAt = updatedAt
    }
}

struct ProgressionSuggestion: Equatable, Hashable {
    var message: String
    var isWeightIncrease: Bool
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
    var historicalBest1RM: Double = 0
    var historicalBestWeightKg: Double = 0
    var setupNote: String? = nil
    var progressionSuggestion: ProgressionSuggestion? = nil

    var id: String { workoutExercise.id }

    func isLivePR(_ workoutSet: WorkoutSet) -> Bool {
        guard workoutSet.isCompleted,
              workoutSet.setType != .warmup,
              let weight = workoutSet.weightKg,
              let reps = workoutSet.reps,
              weight > 0, reps > 0 else {
            return false
        }
        // Only celebrate PR if there is prior history to beat
        guard historicalBest1RM > 0 || historicalBestWeightKg > 0 else { return false }
        let est1RM = OneRepMaxCalculator.estimatedOneRepMax(weightKg: weight, reps: reps)
        return est1RM > historicalBest1RM + 0.05 || weight > historicalBestWeightKg + 0.05
    }
}

struct WorkoutDetail: Identifiable, Equatable, Hashable {
    var workout: Workout
    var gymName: String? = nil
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

struct WorkoutHeartRateSample: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_heart_rate_samples"

    var id: String
    var workoutId: String
    var recordedAt: Date
    var bpm: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workoutId = Column(CodingKeys.workoutId)
        static let recordedAt = Column(CodingKeys.recordedAt)
        static let bpm = Column(CodingKeys.bpm)
    }

    init(
        id: String = UUID().uuidString,
        workoutId: String,
        recordedAt: Date = Date(),
        bpm: Int
    ) {
        self.id = id
        self.workoutId = workoutId
        self.recordedAt = recordedAt
        self.bpm = bpm
    }
}

struct WorkoutHeartRateStats: Equatable {
    var sampleCount: Int = 0
    var bpmSum: Int = 0
    var minBPM: Int? = nil
    var maxBPM: Int? = nil
    var recentSamples: [WorkoutHeartRateSample] = []

    var avgBPM: Int? {
        guard sampleCount > 0 else { return nil }
        return Int((Double(bpmSum) / Double(sampleCount)).rounded())
    }

    mutating func record(_ sample: WorkoutHeartRateSample, maxRecent: Int = 120) {
        sampleCount += 1
        bpmSum += sample.bpm
        minBPM = minBPM.map { min($0, sample.bpm) } ?? sample.bpm
        maxBPM = maxBPM.map { max($0, sample.bpm) } ?? sample.bpm
        recentSamples.append(sample)
        if recentSamples.count > maxRecent {
            recentSamples.removeFirst(recentSamples.count - maxRecent)
        }
    }

    static func from(samples: [WorkoutHeartRateSample], maxRecent: Int = 120) -> WorkoutHeartRateStats {
        var stats = WorkoutHeartRateStats()
        for sample in samples {
            stats.sampleCount += 1
            stats.bpmSum += sample.bpm
            stats.minBPM = stats.minBPM.map { min($0, sample.bpm) } ?? sample.bpm
            stats.maxBPM = stats.maxBPM.map { max($0, sample.bpm) } ?? sample.bpm
        }
        if samples.count > maxRecent {
            stats.recentSamples = Array(samples.suffix(maxRecent))
        } else {
            stats.recentSamples = samples
        }
        return stats
    }
}

struct CompletedWorkoutRecap: Identifiable, Equatable {
    let id: String
    let workoutName: String
    let gymName: String?
    let finishedAt: Date
    let durationSeconds: Int
    let exerciseCount: Int
    let completedSets: Int
    let totalVolumeKg: Double
    let prDescriptions: [String]
    var avgHeartRate: Int? = nil
    var maxHeartRate: Int? = nil
    var minHeartRate: Int? = nil
}
