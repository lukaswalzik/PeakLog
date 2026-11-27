import Combine
import Foundation
import UIKit
import WidgetKit

/// Syncs live daily nutrition, hydration, supplements, streak, and workout data
/// from the main app to the shared App Group snapshot and reloads WidgetKit timelines.
final class WidgetDataSyncManager: ObservableObject {
    private let database: AppDatabase
    private weak var historyStore: HistoryStore?
    private weak var cardioStore: CardioStore?
    private weak var bodyweightStore: BodyweightStore?
    private weak var routineStore: RoutineStore?
    private weak var nutritionStore: NutritionStore?
    private weak var wellnessStore: WellnessStore?

    private var cancellables: Set<AnyCancellable> = []
    private var debounceWorkItem: DispatchWorkItem?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    init(database: AppDatabase) {
        self.database = database

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSync(delay: 0.2)
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncNow()
        }
    }

    deinit {
        debounceWorkItem?.cancel()
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = backgroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func bind(
        historyStore: HistoryStore,
        cardioStore: CardioStore,
        bodyweightStore: BodyweightStore,
        routineStore: RoutineStore,
        nutritionStore: NutritionStore,
        wellnessStore: WellnessStore
    ) {
        self.historyStore = historyStore
        self.cardioStore = cardioStore
        self.bodyweightStore = bodyweightStore
        self.routineStore = routineStore
        self.nutritionStore = nutritionStore
        self.wellnessStore = wellnessStore

        cancellables.removeAll()

        historyStore.$completedWorkouts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        cardioStore.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        routineStore.$routines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        nutritionStore.$dayEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        nutritionStore.$goals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        wellnessStore.$waterMl
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        wellnessStore.$dailyWaterGoalMl
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        wellnessStore.$takenSupplementIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        wellnessStore.$supplements
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        wellnessStore.$readinessLogs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        scheduleSync(delay: 0.3)
    }

    func scheduleSync(delay: TimeInterval = 0.4) {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.syncNow()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func syncNow() {
        guard let historyStore = historyStore,
              let cardioStore = cardioStore,
              let bodyweightStore = bodyweightStore,
              let routineStore = routineStore,
              let nutritionStore = nutritionStore,
              let wellnessStore = wellnessStore else {
            return
        }

        let now = Date()
        let todayKey = PeakLogWidgetSnapshot.dayKey(for: now)

        // Always read TODAY's nutrition, water, and supplements from SQLite
        // (even if the user is currently browsing a past date in the UI)
        var todayTotals = DailyNutritionTotals()
        var todayWaterMl = wellnessStore.waterMl
        var todaySuppsTaken = wellnessStore.takenSupplementIds.count
        var totalSupps = wellnessStore.supplements.count

        do {
            try database.dbWriter.read { db in
                let todayEntries = try AppDatabase.fetchFoodLogEntries(forDay: now, in: db)
                todayTotals = DailyNutritionTotals.from(todayEntries)
                todayWaterMl = try AppDatabase.fetchWaterMilliliters(forDayKey: todayKey, in: db)
                todaySuppsTaken = try AppDatabase.fetchTakenSupplementIds(forDayKey: todayKey, in: db).count
                totalSupps = try AppDatabase.fetchSupplements(in: db).count
            }
        } catch {
            // Fall back to in-memory values if DB read fails transiently
        }

        let workouts = historyStore.completedWorkouts
        let cardioSessions = cardioStore.sessions
        let progress = ProgressEngine.compute(
            workouts: workouts,
            cardioSessions: cardioSessions,
            bodyweightEntries: bodyweightStore.entries
        )

        // Compute current ISO week (Mon..Sun) workout stats
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = .current
        let weekComponents = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let startOfWeek = isoCal.date(from: weekComponents) ?? isoCal.startOfDay(for: now)
        let endOfWeek = isoCal.date(byAdding: .day, value: 7, to: startOfWeek) ?? now

        var weekDays = Array(repeating: false, count: 7)
        var workoutsThisWeek = 0
        var weeklyVolumeKg: Double = 0
        var trainedToday = false

        for detail in workouts {
            let date = detail.workout.startedAt
            if isoCal.isDate(date, inSameDayAs: now) {
                trainedToday = true
            }
            if date >= startOfWeek && date < endOfWeek {
                workoutsThisWeek += 1
                weeklyVolumeKg += detail.totalVolumeKg
                let dayOffset = isoCal.dateComponents([.day], from: startOfWeek, to: isoCal.startOfDay(for: date)).day ?? 0
                if dayOffset >= 0 && dayOffset < 7 {
                    weekDays[dayOffset] = true
                }
            }
        }

        for session in cardioSessions {
            let date = session.startedAt
            if isoCal.isDate(date, inSameDayAs: now) {
                trainedToday = true
            }
            if date >= startOfWeek && date < endOfWeek {
                let dayOffset = isoCal.dateComponents([.day], from: startOfWeek, to: isoCal.startOfDay(for: date)).day ?? 0
                if dayOffset >= 0 && dayOffset < 7 {
                    weekDays[dayOffset] = true
                }
            }
        }

        let isTrainingDay = nutritionStore.isTrainingDay(date: now, autoDetected: trainedToday)
        let goals = nutritionStore.goals
        let effectiveCalories = goals.effectiveCalories(isTrainingDay: isTrainingDay)
        let effectiveCarbs = goals.effectiveCarbs(isTrainingDay: isTrainingDay)

        // Suggest next routine (cycle after most recently completed routine, or first routine)
        let nextRoutineName: String?
        if let lastRoutineId = workouts.first?.workout.routineId,
           let lastIdx = routineStore.routines.firstIndex(where: { $0.id == lastRoutineId }),
           !routineStore.routines.isEmpty {
            let nextIdx = (lastIdx + 1) % routineStore.routines.count
            nextRoutineName = routineStore.routines[nextIdx].routine.name
        } else {
            nextRoutineName = routineStore.routines.first?.routine.name
        }

        let readinessScore: Int?
        if let latest = wellnessStore.latestReadiness,
           Calendar.current.isDateInToday(latest.recordedAt) {
            readinessScore = latest.readinessScore
        } else {
            readinessScore = wellnessStore.latestReadiness?.readinessScore
        }

        let snapshot = PeakLogWidgetSnapshot(
            updatedAt: now,
            dayKey: todayKey,
            caloriesConsumed: Int(todayTotals.calories.rounded()),
            caloriesTarget: effectiveCalories,
            proteinGrams: Int(todayTotals.protein.rounded()),
            proteinTarget: goals.targetProteinGrams,
            carbsGrams: Int(todayTotals.carbs.rounded()),
            carbsTarget: effectiveCarbs,
            fatGrams: Int(todayTotals.fat.rounded()),
            fatTarget: goals.targetFatGrams,
            waterMl: todayWaterMl,
            waterGoalMl: wellnessStore.dailyWaterGoalMl,
            supplementsTaken: todaySuppsTaken,
            supplementsTotal: totalSupps,
            weeklyStreak: progress.weeklyStreak,
            workoutsThisWeek: workoutsThisWeek,
            weeklyVolumeKg: weeklyVolumeKg,
            weekActivityDays: weekDays,
            level: progress.level,
            rankTitle: progress.rankTitle,
            nextRoutineName: nextRoutineName,
            lastWorkoutName: workouts.first?.workout.name,
            lastWorkoutDate: workouts.first?.workout.startedAt,
            readinessScore: readinessScore
        )

        PeakLogWidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
