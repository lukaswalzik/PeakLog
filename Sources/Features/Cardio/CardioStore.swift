import Foundation
import GRDB

final class CardioStore: ObservableObject {
    private static let maxHRDefaultsKey = "strongtracker.cardio.max_heart_rate"

    @Published private(set) var sessions: [CardioSession] = []
    @Published var errorMessage: String?

    @Published var maxHeartRate: Int {
        didSet {
            UserDefaults.standard.set(maxHeartRate, forKey: Self.maxHRDefaultsKey)
        }
    }

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        let stored = UserDefaults.standard.integer(forKey: Self.maxHRDefaultsKey)
        self.maxHeartRate = (120...220).contains(stored) ? stored : 190
        startObservation()
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
