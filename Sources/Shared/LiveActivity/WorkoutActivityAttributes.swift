import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workoutName: String
        var currentExerciseName: String?
        var completedSets: Int
        var totalSets: Int
        var totalVolumeKg: Double
        var heartRateBPM: Int?
        var heartRateZoneShort: String?
        var restStartDate: Date?
        var restEndDate: Date?

        var activeRestInterval: ClosedRange<Date>? {
            guard let start = restStartDate,
                  let end = restEndDate,
                  end > start,
                  end > Date() else {
                return nil
            }
            return start...end
        }
    }

    var workoutId: String
    var startedAt: Date
}
