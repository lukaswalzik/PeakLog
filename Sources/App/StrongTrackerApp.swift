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

    init() {
        let db = AppDatabase.shared
        let timerManager = RestTimerManager()
        let hrReceiver = HeartRateReceiver()
        let workoutManager = ActiveWorkoutManager(database: db)
        workoutManager.onSetCompleted = { restSeconds in
            timerManager.startIfAutoEnabled(seconds: restSeconds)
        }
        workoutManager.bindHeartRateReceiver(hrReceiver)

        _exerciseStore = StateObject(wrappedValue: ExerciseStore(database: db))
        _routineStore = StateObject(wrappedValue: RoutineStore(database: db))
        _activeWorkoutManager = StateObject(wrappedValue: workoutManager)
        _restTimerManager = StateObject(wrappedValue: timerManager)
        _historyStore = StateObject(wrappedValue: HistoryStore(database: db))
        _bodyweightStore = StateObject(wrappedValue: BodyweightStore(database: db))
        _cardioStore = StateObject(wrappedValue: CardioStore(database: db))
        _gymStore = StateObject(wrappedValue: GymStore(database: db))
        _nutritionStore = StateObject(wrappedValue: NutritionStore(database: db))
        _wellnessStore = StateObject(wrappedValue: WellnessStore(database: db))
        _heartRateReceiver = StateObject(wrappedValue: hrReceiver)

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
        }
    }
}
