import Foundation
import GRDB

final class NutritionStore: ObservableObject {
    private static let goalsDefaultsKey = "strongtracker.nutrition.goals.v1"

    @Published var selectedDate: Date = Date() {
        didSet {
            startDayObservation(for: selectedDate)
        }
    }
    @Published private(set) var foodItems: [FoodItem] = []
    @Published private(set) var dayEntries: [FoodLogEntryDetail] = []
    @Published var goals: NutritionGoals {
        didSet {
            persistGoals()
        }
    }
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var foodsCancellable: AnyDatabaseCancellable?
    private var dayCancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        if let data = UserDefaults.standard.data(forKey: Self.goalsDefaultsKey),
           let decoded = try? JSONDecoder().decode(NutritionGoals.self, from: data) {
            self.goals = decoded
        } else {
            var initial = NutritionGoals()
            initial.applyEvidenceBasedCalculation()
            self.goals = initial
        }
        startFoodsObservation()
        startDayObservation(for: selectedDate)
    }

    var dayTotals: DailyNutritionTotals {
        DailyNutritionTotals.from(dayEntries)
    }

    func entries(for mealType: MealType) -> [FoodLogEntryDetail] {
        dayEntries.filter { $0.entry.mealType == mealType }
    }

    func calories(for mealType: MealType) -> Double {
        entries(for: mealType).reduce(0) { $0 + $1.calories }
    }

    func shiftSelectedDate(byDays days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = next
        }
    }

    private func persistGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: Self.goalsDefaultsKey)
        }
    }

    private func startFoodsObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchFoodItems(in: db)
        }

        foodsCancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Lebensmittel konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] items in
                self?.foodItems = items
            }
        )
    }

    private func startDayObservation(for date: Date) {
        dayCancellable?.cancel()
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchFoodLogEntries(forDay: date, in: db)
        }

        dayCancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Tages-Log konnte nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] entries in
                self?.dayEntries = entries
            }
        )
    }

    func findLocalFood(byBarcode barcode: String) -> FoodItem? {
        try? database.findFoodItem(byBarcode: barcode)
    }

    func saveFoodItem(_ item: FoodItem) {
        do {
            try database.saveFoodItem(item)
        } catch {
            errorMessage = "Lebensmittel konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func logFood(_ item: FoodItem, mealType: MealType, grams: Double, date: Date? = nil) {
        do {
            try database.saveFoodItem(item)
            let targetDate = date ?? selectedDate
            let entry = FoodLogEntry(
                foodItemId: item.id,
                loggedAt: targetDate,
                mealType: mealType,
                grams: max(1, grams)
            )
            try database.saveFoodLogEntry(entry)
        } catch {
            errorMessage = "Eintrag konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteLogEntry(id: String) {
        do {
            try database.deleteFoodLogEntry(id: id)
        } catch {
            errorMessage = "Eintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
