import ActivityKit
import Combine
import Foundation

/// Synchronizes active workouts, live heart rate, and rest timer countdowns
/// with the iOS Lock Screen Live Activity and iPhone 14 Pro Dynamic Island.
final class WorkoutLiveActivityManager: ObservableObject {
    private static let enabledDefaultsKey = "strongtracker.live_activity.enabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            syncState(forceImmediate: true)
        }
    }

    @Published private(set) var isActivityActive: Bool = false
    @Published private(set) var lastError: String? = nil

    var areSystemActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private weak var activeWorkoutManager: ActiveWorkoutManager?
    private weak var restTimerManager: RestTimerManager?
    private weak var heartRateReceiver: HeartRateReceiver?
    private weak var cardioStore: CardioStore?

    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var lastPushedState: WorkoutActivityAttributes.ContentState?
    private var lastUpdateAt: Date = .distantPast
    private var cancellables: Set<AnyCancellable> = []

    init() {
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        }
    }

    func bind(
        workoutManager: ActiveWorkoutManager,
        restTimerManager: RestTimerManager,
        heartRateReceiver: HeartRateReceiver,
        cardioStore: CardioStore
    ) {
        self.activeWorkoutManager = workoutManager
        self.restTimerManager = restTimerManager
        self.heartRateReceiver = heartRateReceiver
        self.cardioStore = cardioStore

        cancellables.removeAll()

        workoutManager.$activeWorkout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        restTimerManager.$targetEndDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        restTimerManager.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        heartRateReceiver.$currentBPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: false)
            }
            .store(in: &cancellables)

        cardioStore.$maxHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: false)
            }
            .store(in: &cancellables)

        syncState(forceImmediate: true)
    }

    // MARK: - Sync & Lifecycle

    private func syncState(forceImmediate: Bool) {
        guard isEnabled,
              areSystemActivitiesEnabled,
              let detail = activeWorkoutManager?.activeWorkout else {
            endAllActivities()
            return
        }

        let newState = buildContentState(from: detail)

        // Attach to an existing Activity for this workout if app was restarted mid-workout
        if currentActivity == nil || currentActivity?.attributes.workoutId != detail.workout.id {
            if let existing = Activity<WorkoutActivityAttributes>.activities.first(where: {
                $0.attributes.workoutId == detail.workout.id
            }) {
                currentActivity = existing
                isActivityActive = true
            } else {
                startNewActivity(for: detail, initialState: newState)
                return
            }
        }

        guard let activity = currentActivity else { return }

        if let prev = lastPushedState, prev == newState {
            return
        }

        // Throttle heart-rate-only updates to respect ActivityKit update budget
        if !forceImmediate, let prev = lastPushedState {
            let structuralChanged =
                prev.workoutName != newState.workoutName
                || prev.currentExerciseName != newState.currentExerciseName
                || prev.completedSets != newState.completedSets
                || prev.totalSets != newState.totalSets
                || prev.restStartDate != newState.restStartDate
                || prev.restEndDate != newState.restEndDate
                || (prev.heartRateBPM == nil) != (newState.heartRateBPM == nil)

            if !structuralChanged {
                let elapsed = Date().timeIntervalSince(lastUpdateAt)
                let bpmDelta = abs((prev.heartRateBPM ?? 0) - (newState.heartRateBPM ?? 0))
                if elapsed < 2.0 && bpmDelta < 3 {
                    return
                }
            }
        }

        lastPushedState = newState
        lastUpdateAt = Date()
        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    private func startNewActivity(
        for detail: WorkoutDetail,
        initialState: WorkoutActivityAttributes.ContentState
    ) {
        // Clean up any stale activities belonging to older workouts
        let stale = Activity<WorkoutActivityAttributes>.activities.filter {
            $0.attributes.workoutId != detail.workout.id
        }
        if !stale.isEmpty {
            Task {
                for act in stale {
                    await act.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        let attributes = WorkoutActivityAttributes(
            workoutId: detail.workout.id,
            startedAt: detail.workout.startedAt
        )

        do {
            let activity = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            lastPushedState = initialState
            lastUpdateAt = Date()
            isActivityActive = true
            lastError = nil
        } catch {
            isActivityActive = false
            lastError = "Live Activity konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    private func endAllActivities() {
        let all = Activity<WorkoutActivityAttributes>.activities
        currentActivity = nil
        lastPushedState = nil
        isActivityActive = false
        guard !all.isEmpty else { return }

        Task {
            for activity in all {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func buildContentState(from detail: WorkoutDetail) -> WorkoutActivityAttributes.ContentState {
        let currentExercise = detail.exercises.first(where: { ex in
            ex.sets.contains { !$0.isCompleted }
        })?.exercise.name ?? detail.exercises.last?.exercise.name

        let bpm = heartRateReceiver?.currentBPM
        let maxHR = cardioStore?.maxHeartRate ?? 190
        let zoneShort = bpm.flatMap { HeartRateZone.zone(for: $0, maxHR: maxHR)?.shortName }

        let restStart: Date?
        let restEnd: Date?
        if let timer = restTimerManager,
           timer.isRunning,
           let end = timer.targetEndDate,
           end > Date(),
           timer.totalDuration > 0 {
            let computedStart = end.addingTimeInterval(-timer.totalDuration)
            restStart = computedStart < end ? computedStart : Date()
            restEnd = end
        } else {
            restStart = nil
            restEnd = nil
        }

        return WorkoutActivityAttributes.ContentState(
            workoutName: detail.workout.name,
            currentExerciseName: currentExercise,
            completedSets: detail.completedSetCount,
            totalSets: detail.totalSetCount,
            totalVolumeKg: detail.totalVolumeKg,
            heartRateBPM: bpm,
            heartRateZoneShort: zoneShort,
            restStartDate: restStart,
            restEndDate: restEnd
        )
    }
}
