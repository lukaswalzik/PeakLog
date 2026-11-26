import Foundation
import GRDB

final class BodyweightStore: ObservableObject {
    @Published private(set) var entries: [BodyweightEntryWithPhotos] = []
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var cancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservation()
    }

    var latestEntry: BodyweightEntryWithPhotos? {
        entries.first
    }

    var oldestEntry: BodyweightEntryWithPhotos? {
        entries.last
    }

    var deltaFromStartKg: Double? {
        guard entries.count >= 2,
              let latest = latestEntry?.entry.weightKg,
              let oldest = oldestEntry?.entry.weightKg else {
            return nil
        }
        return latest - oldest
    }

    var allPhotosTimeline: [PhotoTimelineItem] {
        entries.flatMap { item in
            item.photos.map { photo in
                PhotoTimelineItem(
                    photo: photo,
                    recordedAt: item.entry.recordedAt,
                    weightKg: item.entry.weightKg
                )
            }
        }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchBodyweightEntriesWithPhotos(in: db)
        }

        cancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Körpergewicht konnte nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] entries in
                self?.entries = entries
            }
        )
    }

    func saveEntry(
        _ entry: BodyweightEntry,
        photos: [BodyweightPhoto],
        removedFilenames: [String] = []
    ) {
        do {
            try database.saveBodyweightEntry(entry, photos: photos)
            for filename in removedFilenames {
                MediaStorage.shared.deleteImage(filename: filename, in: .bodyweight)
            }
        } catch {
            errorMessage = "Eintrag konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteEntry(id: String) {
        do {
            let removedFiles = try database.deleteBodyweightEntry(id: id)
            for filename in removedFiles {
                MediaStorage.shared.deleteImage(filename: filename, in: .bodyweight)
            }
        } catch {
            errorMessage = "Eintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
