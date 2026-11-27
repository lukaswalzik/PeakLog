import Foundation

struct PeakLogWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var dayKey: String

    // Today's Nutrition
    var caloriesConsumed: Int
    var caloriesTarget: Int
    var proteinGrams: Int
    var proteinTarget: Int
    var carbsGrams: Int
    var carbsTarget: Int
    var fatGrams: Int
    var fatTarget: Int

    // Today's Hydration & Supplements
    var waterMl: Int
    var waterGoalMl: Int
    var supplementsTaken: Int
    var supplementsTotal: Int

    // Training & Weekly Activity
    var weeklyStreak: Int
    var workoutsThisWeek: Int
    var weeklyVolumeKg: Double
    /// Monday (index 0) through Sunday (index 6) for the current week
    var weekActivityDays: [Bool]
    var level: Int
    var rankTitle: String
    var nextRoutineName: String?
    var lastWorkoutName: String?
    var lastWorkoutDate: Date?

    // Optional Wellness
    var readinessScore: Int?

    var remainingCalories: Int {
        max(0, caloriesTarget - caloriesConsumed)
    }

    var calorieProgress: Double {
        guard caloriesTarget > 0 else { return 0 }
        return min(1.0, max(0.0, Double(caloriesConsumed) / Double(caloriesTarget)))
    }

    var proteinProgress: Double {
        guard proteinTarget > 0 else { return 0 }
        return min(1.0, max(0.0, Double(proteinGrams) / Double(proteinTarget)))
    }

    var carbsProgress: Double {
        guard carbsTarget > 0 else { return 0 }
        return min(1.0, max(0.0, Double(carbsGrams) / Double(carbsTarget)))
    }

    var fatProgress: Double {
        guard fatTarget > 0 else { return 0 }
        return min(1.0, max(0.0, Double(fatGrams) / Double(fatTarget)))
    }

    var waterProgress: Double {
        guard waterGoalMl > 0 else { return 0 }
        return min(1.0, max(0.0, Double(waterMl) / Double(waterGoalMl)))
    }

    var formattedWaterLiters: String {
        let liters = Double(waterMl) / 1000.0
        return String(format: "%.1f L", liters).replacingOccurrences(of: ".", with: ",")
    }

    var formattedWaterGoalLiters: String {
        let liters = Double(waterGoalMl) / 1000.0
        return String(format: "%.1f L", liters).replacingOccurrences(of: ".", with: ",")
    }

    var formattedWeeklyVolume: String {
        if weeklyVolumeKg >= 1000 {
            return String(format: "%.1f t", weeklyVolumeKg / 1000.0).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(weeklyVolumeKg.rounded())) kg"
    }

    static func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static var sample: PeakLogWidgetSnapshot {
        PeakLogWidgetSnapshot(
            updatedAt: Date(),
            dayKey: dayKey(),
            caloriesConsumed: 1890,
            caloriesTarget: 2600,
            proteinGrams: 152,
            proteinTarget: 185,
            carbsGrams: 198,
            carbsTarget: 290,
            fatGrams: 54,
            fatTarget: 75,
            waterMl: 2250,
            waterGoalMl: 3000,
            supplementsTaken: 3,
            supplementsTotal: 4,
            weeklyStreak: 6,
            workoutsThisWeek: 3,
            weeklyVolumeKg: 24650,
            weekActivityDays: [true, false, true, false, true, false, false],
            level: 12,
            rankTitle: "Kraftpaket",
            nextRoutineName: "Push Day A",
            lastWorkoutName: "Pull Day B",
            lastWorkoutDate: Date().addingTimeInterval(-86400),
            readinessScore: 86
        )
    }
}

enum PeakLogWidgetStore {
    static let appGroupId = "group.com.local.strongtracker"
    private static let snapshotFilename = "peaklog-widget-snapshot.json"
    private static let defaultsKey = "peaklog.widget.snapshot.v1"

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static var containerFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(snapshotFilename)
    }

    static func save(_ snapshot: PeakLogWidgetSnapshot) {
        guard let data = try? makeEncoder().encode(snapshot) else { return }

        if let fileURL = containerFileURL {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(data, forKey: defaultsKey)
        }
    }

    static func load(referenceDate: Date = Date()) -> PeakLogWidgetSnapshot? {
        var rawData: Data? = nil
        if let fileURL = containerFileURL,
           let fileData = try? Data(contentsOf: fileURL) {
            rawData = fileData
        }
        if rawData == nil,
           let sharedDefaults = UserDefaults(suiteName: appGroupId),
           let defaultsData = sharedDefaults.data(forKey: defaultsKey) {
            rawData = defaultsData
        }

        guard let data = rawData,
              var snapshot = try? makeDecoder().decode(PeakLogWidgetSnapshot.self, from: data) else {
            return nil
        }

        // Automatically reset daily counters after midnight even before the app is opened again
        let todayKey = PeakLogWidgetSnapshot.dayKey(for: referenceDate)
        if snapshot.dayKey != todayKey {
            snapshot.dayKey = todayKey
            snapshot.caloriesConsumed = 0
            snapshot.proteinGrams = 0
            snapshot.carbsGrams = 0
            snapshot.fatGrams = 0
            snapshot.waterMl = 0
            snapshot.supplementsTaken = 0
        }

        return snapshot
    }
}
