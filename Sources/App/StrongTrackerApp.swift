import SwiftUI
import UIKit

@main
struct StrongTrackerApp: App {
    @StateObject private var exerciseStore: ExerciseStore
    @StateObject private var routineStore: RoutineStore
    @StateObject private var activeWorkoutManager: ActiveWorkoutManager
    @StateObject private var restTimerManager: RestTimerManager
    @StateObject private var historyStore: HistoryStore
    @StateObject private var bodyweightStore: BodyweightStore
    @StateObject private var cardioStore: CardioStore
    @StateObject private var gymStore: GymStore
    @StateObject private var nutritionStore: NutritionStore
    @StateObject private var wellnessStore: WellnessStore
    @StateObject private var heartRateReceiver: HeartRateReceiver
    @StateObject private var healthKitService: HealthKitService

    init() {
        let db = AppDatabase.shared
        let timerManager = RestTimerManager()
        let hrReceiver = HeartRateReceiver()
        let hkService = HealthKitService()
        hkService.bindHeartRateReceiver(hrReceiver)

        let workoutManager = ActiveWorkoutManager(database: db)
        workoutManager.onSetCompleted = { restSeconds in
            timerManager.startIfAutoEnabled(seconds: restSeconds)
        }
        workoutManager.onWorkoutFinished = { id, name, startedAt, finishedAt, totalVolumeKg in
            hkService.saveStrengthWorkout(
                id: id,
                name: name,
                startedAt: startedAt,
                finishedAt: finishedAt,
                totalVolumeKg: totalVolumeKg
            )
        }
        workoutManager.bindHeartRateReceiver(hrReceiver)

        let cStore = CardioStore(database: db)
        cStore.onSessionSaved = { session in
            hkService.saveCardioSession(session)
        }

        _exerciseStore = StateObject(wrappedValue: ExerciseStore(database: db))
        _routineStore = StateObject(wrappedValue: RoutineStore(database: db))
        _activeWorkoutManager = StateObject(wrappedValue: workoutManager)
        _restTimerManager = StateObject(wrappedValue: timerManager)
        _historyStore = StateObject(wrappedValue: HistoryStore(database: db))
        _bodyweightStore = StateObject(wrappedValue: BodyweightStore(database: db))
        _cardioStore = StateObject(wrappedValue: cStore)
        _gymStore = StateObject(wrappedValue: GymStore(database: db))
        _nutritionStore = StateObject(wrappedValue: NutritionStore(database: db))
        _wellnessStore = StateObject(wrappedValue: WellnessStore(database: db))
        _heartRateReceiver = StateObject(wrappedValue: hrReceiver)
        _healthKitService = StateObject(wrappedValue: hkService)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(exerciseStore)
                .environmentObject(routineStore)
                .environmentObject(activeWorkoutManager)
                .environmentObject(restTimerManager)
                .environmentObject(historyStore)
                .environmentObject(bodyweightStore)
                .environmentObject(cardioStore)
                .environmentObject(gymStore)
                .environmentObject(nutritionStore)
                .environmentObject(wellnessStore)
                .environmentObject(heartRateReceiver)
                .environmentObject(healthKitService)
        }
    }
}
