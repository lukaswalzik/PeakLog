import SwiftUI
import UIKit

@main
struct StrongTrackerApp: App {
    @StateObject private var exerciseStore = ExerciseStore(database: AppDatabase.shared)
    @StateObject private var routineStore = RoutineStore(database: AppDatabase.shared)
    @StateObject private var activeWorkoutManager = ActiveWorkoutManager(database: AppDatabase.shared)

    init() {
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
        }
    }
}
