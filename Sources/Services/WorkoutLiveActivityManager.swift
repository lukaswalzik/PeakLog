import ActivityKit
import Combine
import Foundation

/// Synchronizes active strength workouts AND live cardio sessions, live heart rate,
/// and rest timer countdowns with the iOS Lock Screen Live Activity and iPhone 14 Pro Dynamic Island.
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
    private weak var activeCardioManager: ActiveCardioManager?
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
        cardioManager: ActiveCardioManager,
        restTimerManager: RestTimerManager,
        heartRateReceiver: HeartRateReceiver,
        cardioStore: CardioStore
    ) {
        self.activeWorkoutManager = workoutManager
        self.activeCardioManager = cardioManager
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

        cardioManager.$sessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        cardioManager.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        cardioManager.$activityType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: true)
            }
            .store(in: &cancellables)

        cardioManager.$currentZone
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState(forceImmediate: false)
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

        heartRateReceiver.sampleSubject
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

    private enum ActiveTarget {
        case strength(WorkoutDetail)
        case cardio(ActiveCardioManager, String)

        var activityId: String {
            switch self {
            case .strength(let detail): return detail.workout.id
            case .cardio(_, let id): return "cardio-\(id)"
            }
        }

        var startedAt: Date {
            switch self {
            case .strength(let detail): return detail.workout.startedAt
            case .cardio(let mgr, _): return mgr.startedAt
            }
        }
    }

    private func resolveActiveTarget() -> ActiveTarget? {
        // Prefer cardio if active & strength isn't, or if user is actively in a cardio session
        if let cardio = activeCardioManager, let cid = cardio.sessionId {
            // If both exist, prefer whichever sheet is active, else strength
            if activeWorkoutManager?.activeWorkout == nil || cardio.isPresentingSheet {
                return .cardio(cardio, cid)
            }
        }
        if let detail = activeWorkoutManager?.activeWorkout {
            return .strength(detail)
        }
        if let cardio = activeCardioManager, let cid = cardio.sessionId {
            return .cardio(cardio, cid)
        }
        return nil
    }

    private func syncState(forceImmediate: Bool) {
        guard isEnabled,
              areSystemActivitiesEnabled,
              let target = resolveActiveTarget() else {
            endAllActivities()
            return
        }

        let newState: WorkoutActivityAttributes.ContentState
        switch target {
        case .strength(let detail):
            newState = buildStrengthState(from: detail)
        case .cardio(let mgr, _):
            newState = buildCardioState(from: mgr)
        }

        let targetId = target.activityId

        if currentActivity == nil || currentActivity?.attributes.workoutId != targetId {
            if let existing = Activity<WorkoutActivityAttributes>.activities.first(where: {
                $0.attributes.workoutId == targetId
            }) {
                currentActivity = existing
                isActivityActive = true
            } else {
                startNewActivity(id: targetId, startedAt: target.startedAt, initialState: newState)
                return
            }
        }

        guard let activity = currentActivity else { return }

        if let prev = lastPushedState, prev == newState {
            return
        }

        // Throttle rapid heart-rate-only updates slightly to stay well within ActivityKit budget
        if !forceImmediate, let prev = lastPushedState {
            let structuralChanged =
                prev.isCardio != newState.isCardio
                || prev.workoutName != newState.workoutName
                || prev.currentExerciseName != newState.currentExerciseName
                || prev.completedSets != newState.completedSets
                || prev.totalSets != newState.totalSets
                || prev.restStartDate != newState.restStartDate
                || prev.restEndDate != newState.restEndDate
                || prev.isPaused != newState.isPaused
                || prev.heartRateZoneShort != newState.heartRateZoneShort
                || prev.targetZoneGuidance != newState.targetZoneGuidance
                || (prev.heartRateBPM == nil) != (newState.heartRateBPM == nil)

            if !structuralChanged {
                let elapsed = Date().timeIntervalSince(lastUpdateAt)
                let bpmDelta = abs((prev.heartRateBPM ?? 0) - (newState.heartRateBPM ?? 0))
                if elapsed < 1.5 && bpmDelta < 2 {
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
        id: String,
        startedAt: Date,
        initialState: WorkoutActivityAttributes.ContentState
    ) {
        let stale = Activity<WorkoutActivityAttributes>.activities.filter {
            $0.attributes.workoutId != id
        }
        if !stale.isEmpty {
            Task {
                for act in stale {
                    await act.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        let attributes = WorkoutActivityAttributes(
            workoutId: id,
            startedAt: startedAt
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

    private func buildStrengthState(from detail: WorkoutDetail) -> WorkoutActivityAttributes.ContentState {
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
            isCardio: false,
            activityIconName: "dumbbell.fill",
            workoutName: detail.workout.name,
            currentExerciseName: currentExercise,
            completedSets: detail.completedSetCount,
            totalSets: detail.totalSetCount,
            totalVolumeKg: detail.totalVolumeKg,
            heartRateBPM: bpm,
            heartRateZoneShort: zoneShort,
            restStartDate: restStart,
            restEndDate: restEnd,
            isPaused: false,
            effectiveTimerStartDate: detail.workout.startedAt,
            targetDurationMinutes: nil,
            targetZoneShort: nil,
            targetZoneGuidance: nil
        )
    }

    private func buildCardioState(from cardio: ActiveCardioManager) -> WorkoutActivityAttributes.ContentState {
        let bpm = heartRateReceiver?.currentBPM
        let maxHR = cardioStore?.maxHeartRate ?? 190
        let zoneShort = bpm.flatMap { HeartRateZone.zone(for: $0, maxHR: maxHR)?.shortName } ?? cardio.currentZone.shortName

        var guidance: String? = nil
        if let planned = cardio.plannedSession, let liveBpm = bpm {
            let bounds = planned.targetZone.percentBounds
            let low = Int(round(Double(maxHR) * bounds.0))
            let high = Int(round(Double(maxHR) * bounds.1))
            if liveBpm >= low && liveBpm <= high {
                guidance = "Im Zielbereich"
            } else if liveBpm < low {
                guidance = "Etwas zügiger"
            } else {
                guidance = "Etwas ruhiger"
            }
        }

        let subtitle: String?
        if let guide = cardio.plannedSession?.intensityGuide, !guide.isEmpty {
            subtitle = guide
        } else {
            subtitle = cardio.currentZone.title
        }

        return WorkoutActivityAttributes.ContentState(
            isCardio: true,
            activityIconName: cardio.activityType.systemImage,
            workoutName: cardio.sessionTitle,
            currentExerciseName: subtitle,
            completedSets: 0,
            totalSets: 0,
            totalVolumeKg: 0,
            heartRateBPM: bpm,
            heartRateZoneShort: zoneShort,
            restStartDate: nil,
            restEndDate: nil,
            isPaused: !cardio.isRunning,
            effectiveTimerStartDate: cardio.effectiveTimerStartDate,
            targetDurationMinutes: cardio.plannedSession?.targetDurationMinutes,
            targetZoneShort: cardio.plannedSession?.targetZone.shortName,
            targetZoneGuidance: guidance
        )
    }
}
