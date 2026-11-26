import SwiftUI

@main
struct StrongTrackerApp: App {
    @StateObject private var exerciseStore = ExerciseStore(database: AppDatabase.shared)

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(exerciseStore)
        }
    }
}
