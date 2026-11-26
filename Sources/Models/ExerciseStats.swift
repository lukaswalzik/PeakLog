import Foundation

struct ExerciseProgressPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let workoutName: String
    let bestEstimated1RM: Double
    let bestWeightKg: Double
    let totalVolumeKg: Double
    let sets: [WorkoutSet]
}

struct ExerciseStats: Equatable {
    let bestWeightKg: Double?
    let bestEstimated1RM: Double?
    let bestSetVolumeKg: Double?
    let totalCompletedSets: Int
    let history: [ExerciseProgressPoint]

    static let empty = ExerciseStats(
        bestWeightKg: nil,
        bestEstimated1RM: nil,
        bestSetVolumeKg: nil,
        totalCompletedSets: 0,
        history: []
    )
}

struct ExercisePRSummary: Identifiable, Equatable {
    let exercise: Exercise
    let bestEstimated1RM: Double
    let bestWeightKg: Double
    let achievedAt: Date

    var id: String { exercise.id }
}
