import Foundation
import SwiftUI

struct Milestone: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let currentValue: Double
    let targetValue: Double
    let unitLabel: String

    var isUnlocked: Bool {
        currentValue >= targetValue
    }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(1.0, max(0.0, currentValue / targetValue))
    }

    var progressText: String {
        let currentInt = Int(currentValue)
        let targetInt = Int(targetValue)
        return "\(min(currentInt, targetInt)) / \(targetInt) \(unitLabel)"
    }
}

struct UserProgressSummary: Equatable {
    let level: Int
    let rankTitle: String
    let totalXP: Int
    let currentLevelXP: Int
    let nextLevelRequiredXP: Int
    let weeklyStreak: Int
    let sessionsThisWeek: Int
    let milestones: [Milestone]

    var levelProgress: Double {
        guard nextLevelRequiredXP > 0 else { return 0 }
        return min(1.0, max(0.0, Double(currentLevelXP) / Double(nextLevelRequiredXP)))
    }

    var unlockedCount: Int {
        milestones.filter { $0.isUnlocked }.count
    }
}

enum ProgressEngine {
    static func compute(
        workouts: [WorkoutDetail],
        cardioSessions: [CardioSession],
        bodyweightEntries: [BodyweightEntryWithPhotos],
        now: Date = Date()
    ) -> UserProgressSummary {
        let workoutCount = workouts.count
        let totalSets = workouts.reduce(0) { $0 + $1.completedSetCount }
        let totalVolumeKg = workouts.reduce(0.0) { $0 + $1.totalVolumeKg }
        let cardioCount = cardioSessions.count
        let totalCardioMinutes = cardioSessions.reduce(0) { $0 + $1.durationSeconds } / 60
        let totalZone2Minutes = cardioSessions.reduce(0) { $0 + $1.zone2Seconds } / 60
        let totalPhotos = bodyweightEntries.reduce(0) { $0 + $1.photos.count }

        let allActivityDates = workouts.map { $0.workout.startedAt } + cardioSessions.map { $0.startedAt }
        let streakInfo = computeWeeklyStreak(dates: allActivityDates, now: now)

        let milestones: [Milestone] = [
            Milestone(
                id: "first-workout",
                title: "Erster Schritt",
                subtitle: "Erstes Kraft-Workout abschließen",
                icon: "figure.strengthtraining.traditional",
                color: .blue,
                currentValue: Double(workoutCount),
                targetValue: 1,
                unitLabel: "Workout"
            ),
            Milestone(
                id: "workouts-10",
                title: "Routine-Profi",
                subtitle: "10 Kraft-Workouts abschließen",
                icon: "star.fill",
                color: .indigo,
                currentValue: Double(workoutCount),
                targetValue: 10,
                unitLabel: "Workouts"
            ),
            Milestone(
                id: "workouts-25",
                title: "Eisen-Habit",
                subtitle: "25 Kraft-Workouts abschließen",
                icon: "flame.fill",
                color: .orange,
                currentValue: Double(workoutCount),
                targetValue: 25,
                unitLabel: "Workouts"
            ),
            Milestone(
                id: "workouts-50",
                title: "Gym-Veteran",
                subtitle: "50 Kraft-Workouts abschließen",
                icon: "crown.fill",
                color: .yellow,
                currentValue: Double(workoutCount),
                targetValue: 50,
                unitLabel: "Workouts"
            ),
            Milestone(
                id: "streak-2",
                title: "Auf Kurs",
                subtitle: "2 Wochen in Folge trainieren",
                icon: "calendar.badge.clock",
                color: .green,
                currentValue: Double(streakInfo.streak),
                targetValue: 2,
                unitLabel: "Wochen"
            ),
            Milestone(
                id: "streak-4",
                title: "Unaufhaltsam",
                subtitle: "4 Wochen in Folge trainieren",
                icon: "bolt.fill",
                color: .teal,
                currentValue: Double(streakInfo.streak),
                targetValue: 4,
                unitLabel: "Wochen"
            ),
            Milestone(
                id: "streak-12",
                title: "Disziplin-Meister",
                subtitle: "12 Wochen in Folge trainieren",
                icon: "medal.fill",
                color: .purple,
                currentValue: Double(streakInfo.streak),
                targetValue: 12,
                unitLabel: "Wochen"
            ),
            Milestone(
                id: "volume-10t",
                title: "10 Tonnen bewegt",
                subtitle: "10.000 kg Gesamtvolumen heben",
                icon: "scalemass.fill",
                color: .cyan,
                currentValue: totalVolumeKg / 1000.0,
                targetValue: 10,
                unitLabel: "t"
            ),
            Milestone(
                id: "volume-100t",
                title: "100 Tonnen bewegt",
                subtitle: "100.000 kg Gesamtvolumen heben",
                icon: "dumbbell.fill",
                color: .blue,
                currentValue: totalVolumeKg / 1000.0,
                targetValue: 100,
                unitLabel: "t"
            ),
            Milestone(
                id: "cardio-first",
                title: "Herz-Kreislauf-Start",
                subtitle: "Erste Cardio-Einheit loggen",
                icon: "heart.fill",
                color: .red,
                currentValue: Double(cardioCount),
                targetValue: 1,
                unitLabel: "Einheit"
            ),
            Milestone(
                id: "zone2-120",
                title: "Zone-2-Engine",
                subtitle: "120 Min. Grundlagenausdauer in Zone 2",
                icon: "waveform.path.ecg",
                color: .green,
                currentValue: Double(totalZone2Minutes),
                targetValue: 120,
                unitLabel: "min"
            ),
            Milestone(
                id: "first-progress-photo",
                title: "Fortschritt im Blick",
                subtitle: "Erstes Körpergewichts-Foto speichern",
                icon: "camera.fill",
                color: .pink,
                currentValue: Double(totalPhotos),
                targetValue: 1,
                unitLabel: "Foto"
            )
        ]

        let unlockedBonusXP = milestones.filter { $0.isUnlocked }.count * 150
        let baseXP = (workoutCount * 100)
            + (totalSets * 5)
            + (cardioCount * 80)
            + ((totalCardioMinutes / 5) * 2)
            + (bodyweightEntries.count * 25)
            + (totalPhotos * 25)
        let totalXP = baseXP + unlockedBonusXP

        let levelInfo = calculateLevel(from: totalXP)

        return UserProgressSummary(
            level: levelInfo.level,
            rankTitle: rankTitle(for: levelInfo.level),
            totalXP: totalXP,
            currentLevelXP: levelInfo.currentLevelXP,
            nextLevelRequiredXP: levelInfo.requiredForNext,
            weeklyStreak: streakInfo.streak,
            sessionsThisWeek: streakInfo.sessionsThisWeek,
            milestones: milestones
        )
    }

    private static func calculateLevel(from totalXP: Int) -> (level: Int, currentLevelXP: Int, requiredForNext: Int) {
        var level = 1
        var remaining = max(0, totalXP)

        while true {
            let needed = 400 + (level - 1) * 150
            if remaining >= needed {
                remaining -= needed
                level += 1
            } else {
                return (level, remaining, needed)
            }
        }
    }

    private static func rankTitle(for level: Int) -> String {
        switch level {
        case 1...2: return "Rookie"
        case 3...5: return "Eisen-Starter"
        case 6...9: return "Gym-Regular"
        case 10...14: return "Kraftpaket"
        case 15...19: return "Hypertrophie-Profi"
        case 20...29: return "Eisen-Veteran"
        default: return "PeakLog-Legende"
        }
    }

    private static func computeWeeklyStreak(dates: [Date], now: Date) -> (streak: Int, sessionsThisWeek: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday

        let currentWeekStart = startOfWeek(for: now, calendar: calendar)
        var countsByWeek: [Date: Int] = [:]
        for date in dates {
            let weekStart = startOfWeek(for: date, calendar: calendar)
            countsByWeek[weekStart, default: 0] += 1
        }

        let sessionsThisWeek = countsByWeek[currentWeekStart] ?? 0
        var streak = 0
        var cursorWeek = currentWeekStart

        // If user hasn't trained yet this week, check if last week was active so the streak stays alive
        if sessionsThisWeek == 0 {
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart),
                  (countsByWeek[previousWeek] ?? 0) > 0 else {
                return (0, 0)
            }
            cursorWeek = previousWeek
        }

        while (countsByWeek[cursorWeek] ?? 0) > 0 {
            streak += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursorWeek) else { break }
            cursorWeek = prev
        }

        return (streak, sessionsThisWeek)
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }
}
