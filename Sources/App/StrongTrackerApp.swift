import SwiftUI
import UIKit

@main
struct StrongTrackerApp: App {
    @StateObject private var exerciseStore: ExerciseStore
    @StateObject private var routineStore: RoutineStore
    @StateObject private var activeWorkoutManager: ActiveWorkoutManager
    @StateObject private var restTimerManager: RestTimerManager

    init() {
        let db = AppDatabase.shared
        let timerManager = RestTimerManager()
        let workoutManager = ActiveWorkoutManager(database: db)
        workoutManager.onSetCompleted = { restSeconds in
            timerManager.startIfAutoEnabled(seconds: restSeconds)
        }

        _exerciseStore = StateObject(wrappedValue: ExerciseStore(database: db))
        _routineStore = StateObject(wrappedValue: RoutineStore(database: db))
        _activeWorkoutManager = StateObject(wrappedValue: workoutManager)
        _restTimerManager = StateObject(wrappedValue: timerManager)

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
        }
    }
}
