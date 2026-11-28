import Foundation
import GRDB

final class CardioStore: ObservableObject {
    private static let maxHRDefaultsKey = "strongtracker.cardio.max_heart_rate"
    private static let plansDefaultsKey = "strongtracker.cardio.plans.v1"

    @Published private(set) var sessions: [CardioSession] = []
    @Published private(set) var plans: [CardioPlan] = []
    @Published var errorMessage: String?

    @Published var maxHeartRate: Int {
        didSet {
            UserDefaults.standard.set(maxHeartRate, forKey: Self.maxHRDefaultsKey)
        }
    }

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    /// Hook invoked whenever a cardio session is saved (e.g. for Apple Health workout export).
    var onSessionSaved: ((CardioSession) -> Void)?

    init(database: AppDatabase) {
        self.database = database
        let stored = UserDefaults.standard.integer(forKey: Self.maxHRDefaultsKey)
        self.maxHeartRate = (120...220).contains(stored) ? stored : 190
        self.plans = Self.loadPlans()
        startObservation()
    }

    var activePlan: CardioPlan? {
        plans.first(where: { $0.isActive }) ?? plans.first
    }

    var sessionsThisWeek: [CardioSession] {
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = .current
        let now = Date()
        let comps = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let startOfWeek = isoCal.date(from: comps) else { return [] }
        return sessions.filter { $0.startedAt >= startOfWeek }
    }

    var minutesThisWeek: Int {
        sessionsThisWeek.reduce(0) { $0 + $1.durationSeconds } / 60
    }

    func hasCompletedPlannedSessionThisWeek(_ planned: CardioPlanSession) -> Bool {
        let lowerTitle = planned.title.lowercased()
        return sessionsThisWeek.contains { session in
            if let notes = session.notes?.lowercased(), notes.contains(lowerTitle) {
                return true
            }
            return false
        }
    }

    var totalSessionsCount: Int {
        sessions.count
    }

    var totalDurationMinutes: Int {
        sessions.reduce(0) { $0 + $1.durationSeconds } / 60
    }

    func filteredSessions(days: Int?) -> [CardioSession] {
        guard let days = days else { return sessions }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sessions.filter { $0.startedAt >= cutoff }
    }

    func zoneTotals(forDays days: Int?) -> [(zone: HeartRateZone, seconds: Int)] {
        let relevant = filteredSessions(days: days)
        return HeartRateZone.allCases.map { zone in
            let sum = relevant.reduce(0) { $0 + $1.seconds(for: zone) }
            return (zone, sum)
        }
    }

    var standaloneSessions: [CardioSession] {
        sessions.filter { $0.workoutId == nil }
    }

    var linkedSessions: [CardioSession] {
        sessions.filter { $0.workoutId != nil }
    }

    func sessions(forWorkoutId workoutId: String) -> [CardioSession] {
        sessions
            .filter { $0.workoutId == workoutId }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func linkSession(_ session: CardioSession, toWorkoutId workoutId: String?) {
        var updated = session
        updated.workoutId = workoutId
        do {
            try database.saveCardioSession(updated)
        } catch {
            errorMessage = "Cardio-Verknüpfung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    // MARK: - Cardio Plans Persistence & CRUD

    private static func loadPlans() -> [CardioPlan] {
        if let data = UserDefaults.standard.data(forKey: plansDefaultsKey),
           let decoded = try? JSONDecoder().decode([CardioPlan].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        let starter = [CardioPlan.defaultStarterPlan()]
        if let encoded = try? JSONEncoder().encode(starter) {
            UserDefaults.standard.set(encoded, forKey: plansDefaultsKey)
        }
        return starter
    }

    private func persistPlans() {
        if let encoded = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(encoded, forKey: Self.plansDefaultsKey)
        }
    }

    func savePlan(_ plan: CardioPlan) {
        var normalized = plan
        normalized.updatedAt = Date()
        normalized.sessions = plan.sessions.enumerated().map { idx, item in
            var copy = item
            copy.sortOrder = idx
            return copy
        }

        if let existingIdx = plans.firstIndex(where: { $0.id == normalized.id }) {
            plans[existingIdx] = normalized
        } else {
            if plans.isEmpty {
                normalized.isActive = true
            }
            plans.append(normalized)
        }

        if normalized.isActive {
            for idx in plans.indices {
                plans[idx].isActive = (plans[idx].id == normalized.id)
            }
        } else if !plans.contains(where: { $0.isActive }), !plans.isEmpty {
            plans[0].isActive = true
        }
        persistPlans()
    }

    func setActivePlan(id: String) {
        for idx in plans.indices {
            plans[idx].isActive = (plans[idx].id == id)
        }
        persistPlans()
    }

    func deletePlan(id: String) {
        plans.removeAll { $0.id == id }
        if !plans.contains(where: { $0.isActive }), !plans.isEmpty {
            plans[0].isActive = true
        }
        persistPlans()
    }

    func duplicatePlan(_ plan: CardioPlan) {
        var copy = plan
        copy.id = UUID().uuidString
        copy.name = "\(plan.name) (Kopie)"
        copy.isActive = true
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.sessions = plan.sessions.map { s in
            var sCopy = s
            sCopy.id = UUID().uuidString
            return sCopy
        }
        savePlan(copy)
    }

    func restoreDefaultStarterPlan() {
        var starter = CardioPlan.defaultStarterPlan()
        starter.isActive = true
        if let idx = plans.firstIndex(where: { $0.id == starter.id }) {
            plans[idx] = starter
            setActivePlan(id: starter.id)
        } else {
            savePlan(starter)
        }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchCardioSessions(in: db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Cardio-Einheiten konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] sessions in
                self?.sessions = sessions
            }
        )
    }

    func save(_ session: CardioSession) {
        do {
            try database.saveCardioSession(session)
            onSessionSaved?(session)
        } catch {
            errorMessage = "Cardio-Einheit konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func delete(id: String) {
        do {
            try database.deleteCardioSession(id: id)
        } catch {
            errorMessage = "Cardio-Einheit konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
