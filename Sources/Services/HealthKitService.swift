import Foundation
import HealthKit
import UIKit

struct HealthKitDailySummary: Equatable {
    var stepsToday: Int? = nil
    var activeCaloriesToday: Int? = nil
    var restingHeartRate: Int? = nil
    var hrvMs: Int? = nil
    var latestWeightKg: Double? = nil
    var latestWeightDate: Date? = nil
    var updatedAt: Date? = nil
}

struct HealthKitWeightSample: Equatable {
    let date: Date
    let weightKg: Double
}

/// Manages Apple HealthKit authorization, real-time live heart rate streaming
/// (e.g. from AirPods HF Bridge / Apple Watch), daily recovery metrics,
/// bodyweight import, and workout export.
final class HealthKitService: ObservableObject {
    private static let authorizedDefaultsKey = "strongtracker.healthkit.authorized"
    private static let liveHREnabledDefaultsKey = "strongtracker.healthkit.live_hr_enabled"
    private static let exportWorkoutsDefaultsKey = "strongtracker.healthkit.export_workouts_enabled"

    let isAvailable: Bool

    @Published private(set) var isConnected: Bool {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: Self.authorizedDefaultsKey)
        }
    }

    @Published var liveHeartRateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveHeartRateEnabled, forKey: Self.liveHREnabledDefaultsKey)
            updateHeartRateStreamingState()
        }
    }

    @Published var exportWorkoutsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(exportWorkoutsEnabled, forKey: Self.exportWorkoutsDefaultsKey)
        }
    }

    @Published private(set) var isStreamingHeartRate: Bool = false
    @Published private(set) var lastHeartRateBPM: Int? = nil
    @Published private(set) var lastHeartRateAt: Date? = nil
    @Published private(set) var heartRateSamplesReceived: Int = 0
    @Published private(set) var dailySummary: HealthKitDailySummary = HealthKitDailySummary()
    @Published private(set) var isLoadingSummary: Bool = false
    @Published private(set) var lastError: String? = nil

    private let store: HKHealthStore?
    private weak var heartRateReceiver: HeartRateReceiver?
    private var anchoredHRQuery: HKAnchoredObjectQuery?
    private var observerHRQuery: HKObserverQuery?
    private var pollTimer: Timer?
    private var seenSampleUUIDs: [UUID] = []
    private var seenUUIDSet: Set<UUID> = []
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    init(autoStart: Bool = true) {
        let available = HKHealthStore.isHealthDataAvailable()
        self.isAvailable = available
        self.store = available ? HKHealthStore() : nil

        let storedConnected = available && UserDefaults.standard.bool(forKey: Self.authorizedDefaultsKey)
        self.isConnected = storedConnected

        if UserDefaults.standard.object(forKey: Self.liveHREnabledDefaultsKey) == nil {
            self.liveHeartRateEnabled = true
        } else {
            self.liveHeartRateEnabled = UserDefaults.standard.bool(forKey: Self.liveHREnabledDefaultsKey)
        }

        if UserDefaults.standard.object(forKey: Self.exportWorkoutsDefaultsKey) == nil {
            self.exportWorkoutsEnabled = true
        } else {
            self.exportWorkoutsEnabled = UserDefaults.standard.bool(forKey: Self.exportWorkoutsDefaultsKey)
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.updateHeartRateStreamingState()
            self.refreshDailySummary()
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Pause foreground polling timer in background while keeping anchored query registered.
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
        }

        if autoStart && storedConnected {
            refreshDailySummary()
        }
    }

    deinit {
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = backgroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        stopLiveHeartRateStreaming()
    }

    // MARK: - Wiring

    func bindHeartRateReceiver(_ receiver: HeartRateReceiver) {
        self.heartRateReceiver = receiver
        updateHeartRateStreamingState()
    }

    // MARK: - Authorization

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .bodyMass,
            .stepCount,
            .activeEnergyBurned
        ]
        for id in identifiers {
            if let qType = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(qType)
            }
        }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling
        ]
        for id in identifiers {
            if let qType = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(qType)
            }
        }
        return types
    }

    func requestAuthorization() {
        guard isAvailable, let store = store else {
            lastError = "Apple Health ist auf diesem Gerät nicht verfügbar."
            return
        }

        lastError = nil
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.lastError = "Apple Health Autorisierung fehlgeschlagen: \(error.localizedDescription)"
                    return
                }
                guard success else {
                    self.lastError = "Apple Health Zugriff wurde nicht freigegeben."
                    return
                }
                self.isConnected = true
                self.lastError = nil
                self.updateHeartRateStreamingState()
                self.refreshDailySummary()
            }
        }
    }

    func disconnect() {
        isConnected = false
        stopLiveHeartRateStreaming()
        lastHeartRateBPM = nil
        lastHeartRateAt = nil
        dailySummary = HealthKitDailySummary()
        lastError = nil
    }

    // MARK: - Live Heart Rate Streaming

    func updateHeartRateStreamingState() {
        if isAvailable && isConnected && liveHeartRateEnabled {
            startLiveHeartRateStreaming()
        } else {
            stopLiveHeartRateStreaming()
        }
    }

    private func startLiveHeartRateStreaming() {
        guard let store = store,
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        // Restart anchored query cleanly
        if let existing = anchoredHRQuery {
            store.stop(existing)
            anchoredHRQuery = nil
        }

        let startDate = Date().addingTimeInterval(-20)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "HealthKit HF-Abfrage: \(error.localizedDescription)"
                }
                return
            }
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "HealthKit HF-Update: \(error.localizedDescription)"
                }
                return
            }
            self?.processHeartRateSamples(samples)
        }

        anchoredHRQuery = query
        store.execute(query)

        // Also register an HKObserverQuery + immediate background delivery so iOS wakes
        // PeakLog when new HealthKit HR samples arrive while the app is minimized (updating Dynamic Island).
        if let existingObs = observerHRQuery {
            store.stop(existingObs)
            observerHRQuery = nil
        }

        let obsQuery = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self = self, error == nil else {
                completionHandler()
                return
            }
            self.pollLatestHeartRateSample(completion: {
                // Give main-queue Combine subscribers & ActivityKit update a brief window before ending background wake
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    completionHandler()
                }
            })
        }
        observerHRQuery = obsQuery
        store.execute(obsQuery)
        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isStreamingHeartRate = true
            self.startForegroundPollTimer()
        }
    }

    private func stopLiveHeartRateStreaming() {
        if let store = store {
            if let existing = anchoredHRQuery {
                store.stop(existing)
            }
            if let existingObs = observerHRQuery {
                store.stop(existingObs)
            }
        }
        anchoredHRQuery = nil
        observerHRQuery = nil
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
            self?.isStreamingHeartRate = false
        }
    }

    private func startForegroundPollTimer() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollLatestHeartRateSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        pollLatestHeartRateSample()
    }

    private func pollLatestHeartRateSample(completion: (() -> Void)? = nil) {
        guard isConnected && liveHeartRateEnabled,
              let store = store,
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion?()
            return
        }

        let startDate = Date().addingTimeInterval(-30)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: 5,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            self?.processHeartRateSamples(samples)
            completion?()
        }
        store.execute(query)
    }

    /// Fetches all HealthKit heart rate samples in a given time range (used to backfill
    /// samples written while PeakLog was minimized during a cardio or strength session).
    func fetchHeartRateSamples(
        from startDate: Date,
        to endDate: Date,
        completion: @escaping ([(date: Date, bpm: Int)]) -> Void
    ) {
        guard isAvailable,
              isConnected,
              let store = store,
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion([])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let quantitySamples = samples as? [HKQuantitySample] else {
                completion([])
                return
            }
            let mapped: [(date: Date, bpm: Int)] = quantitySamples.compactMap { sample in
                let bpm = Int(sample.quantity.doubleValue(for: Self.bpmUnit).rounded())
                guard HeartRateReceiver.validBPMRange.contains(bpm) else { return nil }
                return (sample.endDate, bpm)
            }
            completion(mapped)
        }
        store.execute(query)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        let sorted = quantitySamples.sorted { $0.endDate < $1.endDate }
        let now = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isConnected && self.liveHeartRateEnabled else { return }

            for sample in sorted {
                // Only treat samples from the last 20 seconds as live readings
                guard now.timeIntervalSince(sample.endDate) <= 20.0 else { continue }
                guard !self.seenUUIDSet.contains(sample.uuid) else { continue }

                self.seenUUIDSet.insert(sample.uuid)
                self.seenSampleUUIDs.append(sample.uuid)
                if self.seenSampleUUIDs.count > 250 {
                    let removed = self.seenSampleUUIDs.removeFirst()
                    self.seenUUIDSet.remove(removed)
                }

                let bpmDouble = sample.quantity.doubleValue(for: Self.bpmUnit)
                let bpm = Int(bpmDouble.rounded())
                guard HeartRateReceiver.validBPMRange.contains(bpm) else { continue }

                self.lastHeartRateBPM = bpm
                self.lastHeartRateAt = sample.endDate
                self.heartRateSamplesReceived += 1
                self.lastError = nil

                self.heartRateReceiver?.ingestExternalReading(
                    bpm: bpm,
                    recordedAt: sample.endDate,
                    source: .appleHealth
                )
            }
        }
    }

    // MARK: - Daily Metrics & Bodyweight Import

    func refreshDailySummary() {
        guard isAvailable && isConnected, let store = store else { return }

        DispatchQueue.main.async {
            self.isLoadingSummary = true
        }

        let group = DispatchGroup()
        var stepsToday: Int? = nil
        var activeCaloriesToday: Int? = nil
        var restingHR: Int? = nil
        var hrvMs: Int? = nil
        var latestWeightKg: Double? = nil
        var latestWeightDate: Date? = nil

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: todayPredicate, options: .cumulativeSum) { _, stats, _ in
                if let sum = stats?.sumQuantity() {
                    stepsToday = Int(sum.doubleValue(for: .count()).rounded())
                }
                group.leave()
            }
            store.execute(q)
        }

        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: todayPredicate, options: .cumulativeSum) { _, stats, _ in
                if let sum = stats?.sumQuantity() {
                    activeCaloriesToday = Int(sum.doubleValue(for: .kilocalorie()).rounded())
                }
                group.leave()
            }
            store.execute(q)
        }

        if let rhrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            fetchLatestQuantitySample(store: store, type: rhrType) { sample in
                if let s = sample {
                    restingHR = Int(s.quantity.doubleValue(for: Self.bpmUnit).rounded())
                }
                group.leave()
            }
        }

        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            fetchLatestQuantitySample(store: store, type: hrvType) { sample in
                if let s = sample {
                    hrvMs = Int(s.quantity.doubleValue(for: .secondUnit(with: .milli)).rounded())
                }
                group.leave()
            }
        }

        if let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            group.enter()
            fetchLatestQuantitySample(store: store, type: weightType) { sample in
                if let s = sample {
                    latestWeightKg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    latestWeightDate = s.endDate
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.dailySummary = HealthKitDailySummary(
                stepsToday: stepsToday,
                activeCaloriesToday: activeCaloriesToday,
                restingHeartRate: restingHR,
                hrvMs: hrvMs,
                latestWeightKg: latestWeightKg,
                latestWeightDate: latestWeightDate,
                updatedAt: Date()
            )
            self.isLoadingSummary = false
        }
    }

    private func fetchLatestQuantitySample(
        store: HKHealthStore,
        type: HKQuantityType,
        completion: @escaping (HKQuantitySample?) -> Void
    ) {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            completion(samples?.first as? HKQuantitySample)
        }
        store.execute(q)
    }

    func fetchRecentBodyweightSamples(days: Int = 90, completion: @escaping ([HealthKitWeightSample]) -> Void) {
        guard isAvailable && isConnected,
              let store = store,
              let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let results: [HealthKitWeightSample] = (samples as? [HKQuantitySample] ?? []).map { sample in
                let kg = (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 100.0).rounded() / 100.0
                return HealthKitWeightSample(date: sample.endDate, weightKg: kg)
            }
            DispatchQueue.main.async {
                completion(results)
            }
        }
        store.execute(query)
    }

    // MARK: - Workout Export to Apple Health

    func saveStrengthWorkout(
        id: String,
        name: String,
        startedAt: Date,
        finishedAt: Date,
        totalVolumeKg: Double
    ) {
        guard isAvailable && isConnected && exportWorkoutsEnabled,
              let store = store,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            return
        }

        let end = finishedAt > startedAt ? finishedAt : startedAt.addingTimeInterval(60)
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: startedAt) { success, _ in
            guard success else { return }
            let metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: id,
                "StrongTrackerWorkoutName": name,
                "StrongTrackerVolumeKg": totalVolumeKg
            ]
            builder.addMetadata(metadata) { _, _ in
                builder.endCollection(withEnd: end) { success, _ in
                    guard success else { return }
                    builder.finishWorkout { _, _ in }
                }
            }
        }
    }

    func saveCardioSession(_ session: CardioSession) {
        guard isAvailable && isConnected && exportWorkoutsEnabled,
              let store = store,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            return
        }

        let start = session.startedAt
        let end = start.addingTimeInterval(TimeInterval(max(60, session.durationSeconds)))
        let config = HKWorkoutConfiguration()
        config.activityType = Self.hkActivityType(for: session.activityType)
        config.locationType = Self.hkLocationType(for: session.activityType)

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: start) { success, _ in
            guard success else { return }

            var samples: [HKSample] = []
            if let kcal = session.calories, kcal > 0,
               let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(
                    HKQuantitySample(
                        type: energyType,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                        start: start,
                        end: end
                    )
                )
            }
            if let distKm = session.distanceKm, distKm > 0 {
                let distId: HKQuantityTypeIdentifier = (session.activityType == .cycling || session.activityType == .ergometer)
                    ? .distanceCycling
                    : .distanceWalkingRunning
                if let distType = HKObjectType.quantityType(forIdentifier: distId) {
                    samples.append(
                        HKQuantitySample(
                            type: distType,
                            quantity: HKQuantity(unit: .meter(), doubleValue: distKm * 1000.0),
                            start: start,
                            end: end
                        )
                    )
                }
            }

            let finishStep = {
                builder.addMetadata([HKMetadataKeyExternalUUID: session.id]) { _, _ in
                    builder.endCollection(withEnd: end) { success, _ in
                        guard success else { return }
                        builder.finishWorkout { _, _ in }
                    }
                }
            }

            if samples.isEmpty {
                finishStep()
            } else {
                builder.add(samples) { _, _ in
                    finishStep()
                }
            }
        }
    }

    private static func hkActivityType(for type: CardioActivityType) -> HKWorkoutActivityType {
        switch type {
        case .running, .treadmill: return .running
        case .cycling, .ergometer: return .cycling
        case .rowing: return .rowing
        case .stairmaster: return .stairClimbing
        case .swimming: return .swimming
        case .hiit: return .highIntensityIntervalTraining
        case .walking: return .walking
        case .other: return .other
        }
    }

    private static func hkLocationType(for type: CardioActivityType) -> HKWorkoutSessionLocationType {
        switch type {
        case .treadmill, .ergometer, .stairmaster, .rowing:
            return .indoor
        case .running, .cycling, .walking:
            return .outdoor
        case .swimming, .hiit, .other:
            return .unknown
        }
    }
}
