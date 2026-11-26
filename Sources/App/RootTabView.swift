import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case start
        case history
        case exercises
        case profile
    }

    @State private var selectedTab: Tab = .exercises

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                EmptyStateView(
                    systemImage: "figure.strengthtraining.traditional",
                    title: "Routinen & Schnellstart",
                    message: "Trainingsvorlagen und das Starten von Workouts werden in Phase 2 & 3 ergänzt."
                )
                .navigationTitle("Start")
            }
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
            .tabItem {
                Label("Verlauf", systemImage: "clock.arrow.circlepath")
            }
            .tag(Tab.history)

            ExerciseListView()
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
            .tabItem {
                Label("Profil", systemImage: "person.crop.circle")
            }
            .tag(Tab.profile)
        }
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        RootTabView()
            .environmentObject(ExerciseStore(database: .makeInMemory()))
    }
}
