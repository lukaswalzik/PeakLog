import Foundation
import GRDB

final class WellnessStore: ObservableObject {
    private static let waterGoalDefaultsKey = "strongtracker.wellness.water_goal_ml"

    @Published var selectedDayKey: String = DayKeyFormatter.string(from: Date()) {
        didSet {
            startDayObservation(dayKey: selectedDayKey)
        }
    }
    @Published var dailyWaterGoalMl: Int {
        didSet {
            UserDefaults.standard.set(dailyWaterGoalMl, forKey: Self.waterGoalDefaultsKey)
        }
    }

    @Published private(set) var waterMl: Int = 0
    @Published private(set) var supplements: [Supplement] = []
    @Published private(set) var takenSupplementIds: Set<String> = []
    @Published private(set) var measurements: [BodyMeasurement] = []
    @Published private(set) var readinessLogs: [ReadinessLog] = []
    @Published private(set) var saunaSessions: [SaunaSession] = []
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var globalCancellable: AnyDatabaseCancellable?
    private var dayCancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        let savedGoal = UserDefaults.standard.integer(forKey: Self.waterGoalDefaultsKey)
        self.dailyWaterGoalMl = (1000...8000).contains(savedGoal) ? savedGoal : 3000
        startGlobalObservation()
        startDayObservation(dayKey: selectedDayKey)
    }

    var latestReadiness: ReadinessLog? {
        readinessLogs.first
    }

    var latestMeasurement: BodyMeasurement? {
        measurements.first
    }

    var saunaSessionsThisWeek: [SaunaSession] {
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = .current
        let comps = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let startOfWeek = isoCal.date(from: comps) else { return [] }
        return saunaSessions.filter { $0.startedAt >= startOfWeek }
    }

    var saunaMinutesThisWeek: Int {
        saunaSessionsThisWeek.reduce(0) { $0 + $1.totalDurationMinutes }
    }

    var totalSaunaMinutes: Int {
        saunaSessions.reduce(0) { $0 + $1.totalDurationMinutes }
    }

    func setSelectedDate(_ date: Date) {
        let key = DayKeyFormatter.string(from: date)
        if key != selectedDayKey {
            selectedDayKey = key
        }
    }

    private func startGlobalObservation() {
        let observation = ValueObservation.tracking { db -> ([Supplement], [BodyMeasurement], [ReadinessLog], [SaunaSession]) in
            let supps = try AppDatabase.fetchSupplements(in: db)
            let meas = try AppDatabase.fetchBodyMeasurements(in: db)
            let read = try AppDatabase.fetchReadinessLogs(in: db)
            let sauna = try AppDatabase.fetchSaunaSessions(in: db)
            return (supps, meas, read, sauna)
        }

        globalCancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Wellness-Daten konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] supps, meas, read, sauna in
                self?.supplements = supps
                self?.measurements = meas
                self?.readinessLogs = read
                self?.saunaSessions = sauna
            }
        )
    }

    private func startDayObservation(dayKey: String) {
        dayCancellable?.cancel()
        let observation = ValueObservation.tracking { db -> (Int, Set<String>) in
            let ml = try AppDatabase.fetchWaterMilliliters(forDayKey: dayKey, in: db)
            let taken = try AppDatabase.fetchTakenSupplementIds(forDayKey: dayKey, in: db)
            return (ml, taken)
        }

        dayCancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Tagesdaten konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] ml, taken in
                self?.waterMl = ml
                self?.takenSupplementIds = taken
            }
        )
    }

    func adjustWater(deltaMl: Int) {
        do {
            try database.adjustWater(forDayKey: selectedDayKey, deltaMl: deltaMl)
        } catch {
            errorMessage = "Wasser konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func adjustTodayWater(deltaMl: Int) {
        let todayKey = DayKeyFormatter.string(from: Date())
        do {
            try database.adjustWater(forDayKey: todayKey, deltaMl: deltaMl)
        } catch {
            errorMessage = "Wasser konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func toggleSupplement(_ supplement: Supplement) {
        do {
            try database.toggleSupplementTaken(supplementId: supplement.id, dayKey: selectedDayKey)
        } catch {
            errorMessage = "Supplement-Status konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func saveSupplement(_ supplement: Supplement) {
        do {
            try database.saveSupplement(supplement)
        } catch {
            errorMessage = "Supplement konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteSupplement(id: String) {
        do {
            try database.deleteSupplement(id: id)
        } catch {
            errorMessage = "Supplement konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func saveMeasurement(_ measurement: BodyMeasurement) {
        do {
            try database.saveBodyMeasurement(measurement)
        } catch {
            errorMessage = "Körpermaße konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteMeasurement(id: String) {
        do {
            try database.deleteBodyMeasurement(id: id)
        } catch {
            errorMessage = "Eintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func saveReadiness(_ log: ReadinessLog) {
        do {
            try database.saveReadinessLog(log)
        } catch {
            errorMessage = "Readiness konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteReadiness(id: String) {
        do {
            try database.deleteReadinessLog(id: id)
        } catch {
            errorMessage = "Eintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func saveSaunaSession(_ session: SaunaSession) {
        do {
            try database.saveSaunaSession(session)
        } catch {
            errorMessage = "Sauna-Session konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteSaunaSession(id: String) {
        do {
            try database.deleteSaunaSession(id: id)
        } catch {
            errorMessage = "Sauna-Session konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
