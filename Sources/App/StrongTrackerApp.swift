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
    @StateObject private var liveActivityManager: WorkoutLiveActivityManager
    @StateObject private var widgetSyncManager: WidgetDataSyncManager

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

        let rStore = RoutineStore(database: db)
        let hStore = HistoryStore(database: db)
        let bwStore = BodyweightStore(database: db)
        let cStore = CardioStore(database: db)
        cStore.onSessionSaved = { session in
            hkService.saveCardioSession(session)
        }
        let nStore = NutritionStore(database: db)
        let wStore = WellnessStore(database: db)

        let activityManager = WorkoutLiveActivityManager()
        activityManager.bind(
            workoutManager: workoutManager,
            restTimerManager: timerManager,
            heartRateReceiver: hrReceiver,
            cardioStore: cStore
        )

        let widgetSync = WidgetDataSyncManager(database: db)
        widgetSync.bind(
            historyStore: hStore,
            cardioStore: cStore,
            bodyweightStore: bwStore,
            routineStore: rStore,
            nutritionStore: nStore,
            wellnessStore: wStore
        )

        _exerciseStore = StateObject(wrappedValue: ExerciseStore(database: db))
        _routineStore = StateObject(wrappedValue: rStore)
        _activeWorkoutManager = StateObject(wrappedValue: workoutManager)
        _restTimerManager = StateObject(wrappedValue: timerManager)
        _historyStore = StateObject(wrappedValue: hStore)
        _bodyweightStore = StateObject(wrappedValue: bwStore)
        _cardioStore = StateObject(wrappedValue: cStore)
        _gymStore = StateObject(wrappedValue: GymStore(database: db))
        _nutritionStore = StateObject(wrappedValue: nStore)
        _wellnessStore = StateObject(wrappedValue: wStore)
        _heartRateReceiver = StateObject(wrappedValue: hrReceiver)
        _healthKitService = StateObject(wrappedValue: hkService)
        _liveActivityManager = StateObject(wrappedValue: activityManager)
        _widgetSyncManager = StateObject(wrappedValue: widgetSync)

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
                .environmentObject(liveActivityManager)
                .environmentObject(widgetSyncManager)
        }
    }
}
