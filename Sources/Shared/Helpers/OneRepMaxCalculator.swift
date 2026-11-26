import Foundation

enum OneRepMaxCalculator {
    /// Epley formula for estimated 1RM in kg.
    static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        if reps == 1 {
            return weightKg
        }
        return weightKg * (1.0 + Double(reps) / 30.0)
    }

    static func setVolume(weightKg: Double?, reps: Int?) -> Double {
        guard let w = weightKg, let r = reps, w > 0, r > 0 else { return 0 }
        return w * Double(r)
    }
}
