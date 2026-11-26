import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case start
        case history
        case exercises
        case profile
    }

    @EnvironmentObject private var activeWorkoutManager: ActiveWorkoutManager
    @EnvironmentObject private var restTimerManager: RestTimerManager
    @State private var selectedTab: Tab = .start

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                StartView()
                    .toolbarBackground(.visible, for: .tabBar)
                    .tabItem {
                        Label("Start", systemImage: "figure.strengthtraining.traditional")
                    }
                    .tag(Tab.start)

                HistoryListView()
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

                ProfileBackupView()
                    .toolbarBackground(.visible, for: .tabBar)
                    .tabItem {
                        Label("Profil", systemImage: "person.crop.circle")
                    }
                    .tag(Tab.profile)
            }

            if let detail = activeWorkoutManager.activeWorkout, !activeWorkoutManager.isPresentingSheet {
                ActiveWorkoutBanner(
                    detail: detail,
                    restTimerManager: restTimerManager
                ) {
                    activeWorkoutManager.isPresentingSheet = true
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 58)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $activeWorkoutManager.isPresentingSheet) {
            ActiveWorkoutView()
        }
        .onChange(of: activeWorkoutManager.hasActiveWorkout) { isActive in
            if !isActive {
                restTimerManager.skip()
            }
        }
    }
}

private struct ActiveWorkoutBanner: View {
    let detail: WorkoutDetail
    @ObservedObject var restTimerManager: RestTimerManager
    let onTap: () -> Void

    private var formattedRest: String {
        let mins = restTimerManager.remainingSeconds / 60
        let secs = restTimerManager.remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.workout.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text("\(Formatters.elapsedDuration(from: detail.workout.startedAt, to: context.date)) · \(detail.completedSetCount)/\(detail.totalSetCount) Sätze")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                if restTimerManager.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(formattedRest)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
                }

                Image(systemName: "chevron.up")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        RootTabView()
            .environmentObject(ExerciseStore(database: db))
            .environmentObject(RoutineStore(database: db))
            .environmentObject(ActiveWorkoutManager(database: db))
            .environmentObject(RestTimerManager())
            .environmentObject(HistoryStore(database: db))
    }
}
