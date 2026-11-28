import Combine
import Foundation
import UIKit

/// Global manager for an active live cardio session.
/// Survives minimizing inside the app (floating banner) and leaving the app (wall-clock timestamps,
/// UserDefaults persistence, HealthKit HR backfill, and Dynamic Island / Lock Screen Live Activity).
final class ActiveCardioManager: ObservableObject {
    private static let persistenceKey = "strongtracker.active_cardio.v1"

    private struct PersistedState: Codable {
        var sessionId: String
        var activityType: CardioActivityType
        var currentZone: HeartRateZone
        var autoZoneEnabled: Bool
        var isRunning: Bool
        var startedAt: Date
        var accumulatedPausedSeconds: TimeInterval
        var pausedAt: Date?
        var lastTickDate: Date
        var zone1Seconds: Int
        var zone2Seconds: Int
        var zone3Seconds: Int
        var zone4Seconds: Int
        var zone5Seconds: Int
        var hrSampleCount: Int
        var hrBpmSum: Int
        var hrMaxBpm: Int?
        var plannedSession: CardioPlanSession?
        var hasTriggeredGoalHaptic: Bool
    }

    @Published private(set) var sessionId: String? = nil
    @Published var isPresentingSheet: Bool = false

    @Published var activityType: CardioActivityType = .walking {
        didSet { persist() }
    }
    @Published var currentZone: HeartRateZone = .z2 {
        didSet { persist() }
    }
    @Published var autoZoneEnabled: Bool = true {
        didSet { persist() }
    }
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var startedAt: Date = Date()
    @Published private(set) var accumulatedPausedSeconds: TimeInterval = 0
    @Published private(set) var pausedAt: Date? = nil
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var zoneSeconds: [HeartRateZone: Int] = [
        .z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0
    ]
    @Published private(set) var plannedSession: CardioPlanSession? = nil
    @Published private(set) var hrSampleCount: Int = 0
    @Published private(set) var hrBpmSum: Int = 0
    @Published private(set) var hrMaxBpm: Int? = nil

    private var lastTickDate: Date = Date()
    private var hasTriggeredGoalHaptic: Bool = false
    private var ticker: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    private weak var cardioStore: CardioStore?
    private weak var heartRateReceiver: HeartRateReceiver?
    private weak var healthKitService: HealthKitService?

    var hasActiveSession: Bool {
        sessionId != nil
    }

    var sessionTitle: String {
        plannedSession?.title ?? activityType.displayName
    }

    var isAutoZoneActive: Bool {
        autoZoneEnabled && (heartRateReceiver?.hasLiveSignal ?? false)
    }

    var avgRecordedHeartRate: Int? {
        guard hrSampleCount > 0 else { return nil }
        return Int((Double(hrBpmSum) / Double(hrSampleCount)).rounded())
    }

    /// Reference start date such that `Date() - effectiveTimerStartDate == elapsedSeconds` while running.
    var effectiveTimerStartDate: Date {
        if isRunning {
            return startedAt.addingTimeInterval(accumulatedPausedSeconds)
        }
        return Date().addingTimeInterval(-TimeInterval(elapsedSeconds))
    }

    init() {
        restoreIfPresent()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.hasActiveSession else { return }
            self.catchUpWallClock(now: Date())
            self.startTickerIfNeeded()
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.hasActiveSession else { return }
            self.catchUpWallClock(now: Date())
            self.persist()
        }
    }

    deinit {
        ticker?.invalidate()
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = backgroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func bind(
        cardioStore: CardioStore,
        heartRateReceiver: HeartRateReceiver,
        healthKitService: HealthKitService
    ) {
        self.cardioStore = cardioStore
        self.heartRateReceiver = heartRateReceiver
        self.healthKitService = healthKitService

        cancellables.removeAll()

        heartRateReceiver.sampleSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.handleIncomingHeartRate(reading.bpm)
            }
            .store(in: &cancellables)

        if hasActiveSession {
            catchUpWallClock(now: Date())
            startTickerIfNeeded()
        }
    }

    // MARK: - Lifecycle

    func start(plannedSession: CardioPlanSession? = nil, activityType: CardioActivityType? = nil) {
        let now = Date()
        self.sessionId = UUID().uuidString
        self.plannedSession = plannedSession
        self.activityType = plannedSession?.activityType ?? activityType ?? .walking
        self.autoZoneEnabled = true
        self.isRunning = true
        self.startedAt = now
        self.accumulatedPausedSeconds = 0
        self.pausedAt = nil
        self.lastTickDate = now
        self.elapsedSeconds = 0
        self.hasTriggeredGoalHaptic = false
        self.zoneSeconds = [.z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0]
        self.hrSampleCount = 0
        self.hrBpmSum = 0
        self.hrMaxBpm = nil

        if let bpm = heartRateReceiver?.currentBPM, autoZoneEnabled {
            let maxHR = cardioStore?.maxHeartRate ?? 190
            self.currentZone = HeartRateZone.clampedZone(for: bpm, maxHR: maxHR)
            self.hrSampleCount = 1
            self.hrBpmSum = bpm
            self.hrMaxBpm = bpm
        } else {
            self.currentZone = plannedSession?.targetZone ?? .z2
        }

        self.isPresentingSheet = true
        startTickerIfNeeded()
        persist()
    }

    func togglePause() {
        guard hasActiveSession else { return }
        let now = Date()
        if isRunning {
            catchUpWallClock(now: now)
            isRunning = false
            pausedAt = now
            ticker?.invalidate()
            ticker = nil
        } else {
            if let paused = pausedAt {
                accumulatedPausedSeconds += max(0, now.timeIntervalSince(paused))
            }
            pausedAt = nil
            lastTickDate = now
            isRunning = true
            startTickerIfNeeded()
        }
        persist()
    }

    func selectZoneManually(_ zone: HeartRateZone) {
        guard !isAutoZoneActive else { return }
        catchUpWallClock(now: Date())
        currentZone = zone
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persist()
    }

    func finish() {
        guard hasActiveSession else { return }
        let finishDate = Date()
        catchUpWallClock(now: finishDate)

        let capturedStart = startedAt
        let capturedDuration = max(60, elapsedSeconds)
        let capturedType = activityType
        let capturedPlanned = plannedSession
        let capturedZones = zoneSeconds
        let capturedAvgHR = avgRecordedHeartRate
        let capturedMaxHR = hrMaxBpm
        let maxHR = cardioStore?.maxHeartRate ?? 190

        var sessionNotes: String? = nil
        if let planned = capturedPlanned {
            sessionNotes = planned.intensityGuide.isEmpty
                ? planned.title
                : "\(planned.title) · \(planned.intensityGuide)"
        }

        let buildAndSave: (Int?, Int?, [HeartRateZone: Int]) -> Void = { [weak self] avgHR, maxRecordedHR, zones in
            let session = CardioSession(
                activityType: capturedType,
                startedAt: capturedStart,
                durationSeconds: capturedDuration,
                avgHeartRate: avgHR,
                maxHeartRate: maxRecordedHR,
                zone1Seconds: zones[.z1] ?? 0,
                zone2Seconds: zones[.z2] ?? 0,
                zone3Seconds: zones[.z3] ?? 0,
                zone4Seconds: zones[.z4] ?? 0,
                zone5Seconds: zones[.z5] ?? 0,
                notes: sessionNotes
            )
            self?.cardioStore?.save(session)
        }

        // Clear active session immediately so UI & Live Activity close responsively
        clearActiveSession()

        // If HealthKit is connected, backfill any HR samples written while PeakLog was backgrounded
        if let hk = healthKitService, hk.isConnected {
            hk.fetchHeartRateSamples(from: capturedStart, to: finishDate) { samples in
                DispatchQueue.main.async {
                    guard !samples.isEmpty else {
                        buildAndSave(capturedAvgHR, capturedMaxHR, capturedZones)
                        return
                    }
                    let bpms = samples.map { $0.bpm }
                    let avg = Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded())
                    let maxBpm = bpms.max()
                    // Estimate proportional zone seconds from HealthKit samples if we have rich coverage
                    if samples.count >= 5 {
                        var counts: [HeartRateZone: Int] = [.z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0]
                        for s in samples {
                            let z = HeartRateZone.clampedZone(for: s.bpm, maxHR: maxHR)
                            counts[z, default: 0] += 1
                        }
                        var computedZones: [HeartRateZone: Int] = [:]
                        for z in HeartRateZone.allCases {
                            let ratio = Double(counts[z] ?? 0) / Double(samples.count)
                            computedZones[z] = Int((Double(capturedDuration) * ratio).rounded())
                        }
                        buildAndSave(avg, maxBpm, computedZones)
                    } else {
                        buildAndSave(capturedAvgHR ?? avg, max(capturedMaxHR ?? 0, maxBpm ?? 0), capturedZones)
                    }
                }
            }
        } else {
            buildAndSave(capturedAvgHR, capturedMaxHR, capturedZones)
        }
    }

    func discard() {
        clearActiveSession()
    }

    // MARK: - Internal Clock & Heart Rate

    private func handleIncomingHeartRate(_ bpm: Int) {
        guard hasActiveSession, isRunning else { return }
        catchUpWallClock(now: Date())
        hrSampleCount += 1
        hrBpmSum += bpm
        hrMaxBpm = hrMaxBpm.map { max($0, bpm) } ?? bpm

        if autoZoneEnabled {
            let maxHR = cardioStore?.maxHeartRate ?? 190
            let nextZone = HeartRateZone.clampedZone(for: bpm, maxHR: maxHR)
            if nextZone != currentZone {
                currentZone = nextZone
            }
        }
    }

    private func startTickerIfNeeded() {
        ticker?.invalidate()
        guard hasActiveSession && isRunning else {
            ticker = nil
            return
        }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.catchUpWallClock(now: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func catchUpWallClock(now: Date = Date()) {
        guard hasActiveSession else { return }

        let totalActive: TimeInterval
        if isRunning {
            totalActive = max(0, now.timeIntervalSince(startedAt) - accumulatedPausedSeconds)
            let delta = Int(floor(now.timeIntervalSince(lastTickDate)))
            if delta > 0 {
                zoneSeconds[currentZone, default: 0] += delta
                lastTickDate = lastTickDate.addingTimeInterval(TimeInterval(delta))
            }
        } else if let paused = pausedAt {
            totalActive = max(0, paused.timeIntervalSince(startedAt) - accumulatedPausedSeconds)
        } else {
            totalActive = TimeInterval(elapsedSeconds)
        }

        let newElapsed = Int(floor(totalActive))
        if newElapsed != elapsedSeconds {
            elapsedSeconds = newElapsed
        }

        if let targetMins = plannedSession?.targetDurationMinutes,
           !hasTriggeredGoalHaptic,
           elapsedSeconds >= targetMins * 60 {
            hasTriggeredGoalHaptic = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            persist()
        }
    }

    private func clearActiveSession() {
        ticker?.invalidate()
        ticker = nil
        sessionId = nil
        isPresentingSheet = false
        isRunning = false
        pausedAt = nil
        accumulatedPausedSeconds = 0
        elapsedSeconds = 0
        plannedSession = nil
        hrSampleCount = 0
        hrBpmSum = 0
        hrMaxBpm = nil
        hasTriggeredGoalHaptic = false
        zoneSeconds = [.z1: 0, .z2: 0, .z3: 0, .z4: 0, .z5: 0]
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    // MARK: - Persistence

    private func persist() {
        guard let sessionId = sessionId else { return }
        let state = PersistedState(
            sessionId: sessionId,
            activityType: activityType,
            currentZone: currentZone,
            autoZoneEnabled: autoZoneEnabled,
            isRunning: isRunning,
            startedAt: startedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            pausedAt: pausedAt,
            lastTickDate: lastTickDate,
            zone1Seconds: zoneSeconds[.z1] ?? 0,
            zone2Seconds: zoneSeconds[.z2] ?? 0,
            zone3Seconds: zoneSeconds[.z3] ?? 0,
            zone4Seconds: zoneSeconds[.z4] ?? 0,
            zone5Seconds: zoneSeconds[.z5] ?? 0,
            hrSampleCount: hrSampleCount,
            hrBpmSum: hrBpmSum,
            hrMaxBpm: hrMaxBpm,
            plannedSession: plannedSession,
            hasTriggeredGoalHaptic: hasTriggeredGoalHaptic
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func restoreIfPresent() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        // Ignore stale sessions older than 12 hours
        if Date().timeIntervalSince(state.startedAt) > 12 * 3600 {
            UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
            return
        }

        self.sessionId = state.sessionId
        self.activityType = state.activityType
        self.currentZone = state.currentZone
        self.autoZoneEnabled = state.autoZoneEnabled
        self.isRunning = state.isRunning
        self.startedAt = state.startedAt
        self.accumulatedPausedSeconds = state.accumulatedPausedSeconds
        self.pausedAt = state.pausedAt
        self.lastTickDate = state.lastTickDate
        self.zoneSeconds = [
            .z1: state.zone1Seconds,
            .z2: state.zone2Seconds,
            .z3: state.zone3Seconds,
            .z4: state.zone4Seconds,
            .z5: state.zone5Seconds
        ]
        self.hrSampleCount = state.hrSampleCount
        self.hrBpmSum = state.hrBpmSum
        self.hrMaxBpm = state.hrMaxBpm
        self.plannedSession = state.plannedSession
        self.hasTriggeredGoalHaptic = state.hasTriggeredGoalHaptic
        catchUpWallClock(now: Date())
    }
}
