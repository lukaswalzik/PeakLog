import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case start
        case history
        case exercises
        case profile
    }

    @State private var selectedTab: Tab = .start

    var body: some View {
        TabView(selection: $selectedTab) {
            StartView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Start", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(Tab.start)

            NavigationStack {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "Trainingsverlauf",
                    message: "Abgeschlossene Workouts erscheinen hier ab Phase 5."
                )
                .navigationTitle("Verlauf")
            }
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem {
                Label("Verlauf", systemImage: "clock.arrow.circlepath")
            }
            .tag(Tab.history)

            ExerciseListView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Übungen", systemImage: "dumbbell")
                }
                .tag(Tab.exercises)

            NavigationStack {
                EmptyStateView(
                    systemImage: "person.crop.circle",
                    title: "Profil & Backup",
                    message: "PR-Übersicht und lokaler JSON-Export/Import folgen in Phase 5."
                )
                .navigationTitle("Profil")
            }
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem {
                Label("Profil", systemImage: "person.crop.circle")
            }
            .tag(Tab.profile)
        }
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        RootTabView()
            .environmentObject(ExerciseStore(database: db))
            .environmentObject(RoutineStore(database: db))
    }
}
