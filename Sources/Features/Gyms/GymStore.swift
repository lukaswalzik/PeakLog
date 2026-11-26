import Foundation
import GRDB

final class GymStore: ObservableObject {
    private static let selectedGymDefaultsKey = "strongtracker.gyms.selected_gym_id"

    @Published private(set) var gyms: [Gym] = []
    @Published var selectedGymId: String? {
        didSet {
            if let id = selectedGymId {
                UserDefaults.standard.set(id, forKey: Self.selectedGymDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedGymDefaultsKey)
            }
        }
    }
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        self.selectedGymId = UserDefaults.standard.string(forKey: Self.selectedGymDefaultsKey)
        startObservation()
    }

    var selectedGym: Gym? {
        guard let id = selectedGymId else { return nil }
        return gyms.first { $0.id == id }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchGyms(in: db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Gyms konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] gyms in
                self?.gyms = gyms
                if let currentId = self?.selectedGymId, !gyms.contains(where: { $0.id == currentId }) {
                    self?.selectedGymId = nil
                }
            }
        )
    }

    func save(_ gym: Gym) {
        do {
            try database.saveGym(gym)
            if selectedGymId == nil {
                selectedGymId = gym.id
            }
        } catch {
            errorMessage = "Gym konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func delete(id: String) {
        do {
            try database.deleteGym(id: id)
            if selectedGymId == id {
                selectedGymId = nil
            }
        } catch {
            errorMessage = "Gym konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
