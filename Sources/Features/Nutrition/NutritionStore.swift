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
    @Published private(set) var savedMeals: [SavedMealWithItems] = []
    @Published private(set) var dayEntries: [FoodLogEntryDetail] = []
    @Published var goals: NutritionGoals {
        didSet {
            persistGoals()
        }
    }
    @Published var errorMessage: String?

    private let database: AppDatabase
    private var foodsCancellable: AnyDatabaseCancellable?
    private var mealsCancellable: AnyDatabaseCancellable?
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
        startSavedMealsObservation()
        startDayObservation(for: selectedDate)
    }

    var dayTotals: DailyNutritionTotals {
        DailyNutritionTotals.from(dayEntries)
    }

    var favoriteFoods: [FoodItem] {
        foodItems.filter { $0.isFavorite }
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

    private func startSavedMealsObservation() {
        let observation = ValueObservation.tracking { db in
            try AppDatabase.fetchSavedMealsWithItems(in: db)
        }

        mealsCancellable = observation.start(
            in: database.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                self?.errorMessage = "Gespeicherte Mahlzeiten konnten nicht geladen werden: \(error.localizedDescription)"
            },
            onChange: { [weak self] meals in
                self?.savedMeals = meals
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

    func toggleFavorite(for item: FoodItem) {
        do {
            if !foodItems.contains(where: { $0.id == item.id }) {
                var copy = item
                copy.isFavorite = true
                try database.saveFoodItem(copy)
            } else {
                try database.toggleFoodFavorite(id: item.id, isFavorite: !item.isFavorite)
            }
        } catch {
            errorMessage = "Favorit konnte nicht geändert werden: \(error.localizedDescription)"
        }
    }

    func logFood(_ item: FoodItem, mealType: MealType, grams: Double, date: Date? = nil) {
        do {
            // Preserve existing favorite flag if food already exists locally
            var itemToSave = item
            if let existing = foodItems.first(where: { $0.id == item.id }) {
                itemToSave.isFavorite = existing.isFavorite
            }
            try database.saveFoodItem(itemToSave)
            let targetDate = date ?? selectedDate
            let entry = FoodLogEntry(
                foodItemId: itemToSave.id,
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

    func saveSavedMeal(_ meal: SavedMeal, items: [SavedMealItem]) {
        do {
            try database.saveSavedMeal(meal, items: items)
        } catch {
            errorMessage = "Mahlzeit konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteSavedMeal(id: String) {
        do {
            try database.deleteSavedMeal(id: id)
        } catch {
            errorMessage = "Mahlzeit konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func logSavedMeal(_ meal: SavedMealWithItems, mealType: MealType, multiplier: Double = 1.0, date: Date? = nil) {
        do {
            try database.logSavedMeal(meal, mealType: mealType, multiplier: multiplier, date: date ?? selectedDate)
        } catch {
            errorMessage = "Mahlzeit konnte nicht geloggt werden: \(error.localizedDescription)"
        }
    }
}
