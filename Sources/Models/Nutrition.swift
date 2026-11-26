import Foundation
import GRDB
import SwiftUI

enum MealType: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Frühstück"
        case .lunch: return "Mittagessen"
        case .dinner: return "Abendessen"
        case .snack: return "Snacks"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "bolt.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .green
        case .dinner: return .indigo
        case .snack: return .purple
        }
    }
}

/// Nutritional values stored per 100 g / 100 ml.
struct FoodItem: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_items"

    var id: String
    var name: String
    var brand: String?
    var barcode: String?
    var servingSizeGrams: Double
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double
    var sugarPer100g: Double
    var saltPer100g: Double
    var vitaminCMgPer100g: Double
    var calciumMgPer100g: Double
    var ironMgPer100g: Double
    var isCustom: Bool
    var isFavorite: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, servingSizeGrams
        case caloriesPer100g, proteinPer100g, carbsPer100g, fatPer100g
        case fiberPer100g, sugarPer100g, saltPer100g
        case vitaminCMgPer100g, calciumMgPer100g, ironMgPer100g
        case isCustom, isFavorite, createdAt
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let brand = Column(CodingKeys.brand)
        static let barcode = Column(CodingKeys.barcode)
        static let servingSizeGrams = Column(CodingKeys.servingSizeGrams)
        static let caloriesPer100g = Column(CodingKeys.caloriesPer100g)
        static let proteinPer100g = Column(CodingKeys.proteinPer100g)
        static let carbsPer100g = Column(CodingKeys.carbsPer100g)
        static let fatPer100g = Column(CodingKeys.fatPer100g)
        static let fiberPer100g = Column(CodingKeys.fiberPer100g)
        static let sugarPer100g = Column(CodingKeys.sugarPer100g)
        static let saltPer100g = Column(CodingKeys.saltPer100g)
        static let vitaminCMgPer100g = Column(CodingKeys.vitaminCMgPer100g)
        static let calciumMgPer100g = Column(CodingKeys.calciumMgPer100g)
        static let ironMgPer100g = Column(CodingKeys.ironMgPer100g)
        static let isCustom = Column(CodingKeys.isCustom)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        servingSizeGrams: Double = 100,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        saltPer100g: Double = 0,
        vitaminCMgPer100g: Double = 0,
        calciumMgPer100g: Double = 0,
        ironMgPer100g: Double = 0,
        isCustom: Bool = true,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingSizeGrams = servingSizeGrams
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.saltPer100g = saltPer100g
        self.vitaminCMgPer100g = vitaminCMgPer100g
        self.calciumMgPer100g = calciumMgPer100g
        self.ironMgPer100g = ironMgPer100g
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        servingSizeGrams = try c.decodeIfPresent(Double.self, forKey: .servingSizeGrams) ?? 100
        caloriesPer100g = try c.decode(Double.self, forKey: .caloriesPer100g)
        proteinPer100g = try c.decode(Double.self, forKey: .proteinPer100g)
        carbsPer100g = try c.decode(Double.self, forKey: .carbsPer100g)
        fatPer100g = try c.decode(Double.self, forKey: .fatPer100g)
        fiberPer100g = try c.decodeIfPresent(Double.self, forKey: .fiberPer100g) ?? 0
        sugarPer100g = try c.decodeIfPresent(Double.self, forKey: .sugarPer100g) ?? 0
        saltPer100g = try c.decodeIfPresent(Double.self, forKey: .saltPer100g) ?? 0
        vitaminCMgPer100g = try c.decodeIfPresent(Double.self, forKey: .vitaminCMgPer100g) ?? 0
        calciumMgPer100g = try c.decodeIfPresent(Double.self, forKey: .calciumMgPer100g) ?? 0
        ironMgPer100g = try c.decodeIfPresent(Double.self, forKey: .ironMgPer100g) ?? 0
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? true
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct SavedMeal: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "saved_meals"

    var id: String
    var name: String
    var notes: String?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let notes = Column(CodingKeys.notes)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
    }
}

struct SavedMealItem: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "saved_meal_items"

    var id: String
    var mealId: String
    var foodItemId: String
    var grams: Double
    var sortOrder: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let mealId = Column(CodingKeys.mealId)
        static let foodItemId = Column(CodingKeys.foodItemId)
        static let grams = Column(CodingKeys.grams)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    init(
        id: String = UUID().uuidString,
        mealId: String,
        foodItemId: String,
        grams: Double,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.mealId = mealId
        self.foodItemId = foodItemId
        self.grams = grams
        self.sortOrder = sortOrder
    }
}

struct SavedMealItemDetail: Identifiable, Equatable, Hashable {
    var item: SavedMealItem
    var food: FoodItem

    var id: String { item.id }

    private var factor: Double { item.grams / 100.0 }
    var calories: Double { food.caloriesPer100g * factor }
    var protein: Double { food.proteinPer100g * factor }
    var carbs: Double { food.carbsPer100g * factor }
    var fat: Double { food.fatPer100g * factor }
}

struct SavedMealWithItems: Identifiable, Equatable, Hashable {
    var meal: SavedMeal
    var items: [SavedMealItemDetail]

    var id: String { meal.id }

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fat } }
}

struct FoodLogEntry: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_log_entries"

    var id: String
    var foodItemId: String
    var loggedAt: Date
    var mealType: MealType
    var grams: Double

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let foodItemId = Column(CodingKeys.foodItemId)
        static let loggedAt = Column(CodingKeys.loggedAt)
        static let mealType = Column(CodingKeys.mealType)
        static let grams = Column(CodingKeys.grams)
    }

    init(
        id: String = UUID().uuidString,
        foodItemId: String,
        loggedAt: Date = Date(),
        mealType: MealType = .lunch,
        grams: Double = 100
    ) {
        self.id = id
        self.foodItemId = foodItemId
        self.loggedAt = loggedAt
        self.mealType = mealType
        self.grams = grams
    }
}

struct FoodLogEntryDetail: Identifiable, Equatable, Hashable {
    var entry: FoodLogEntry
    var food: FoodItem

    var id: String { entry.id }

    private var factor: Double { entry.grams / 100.0 }

    var calories: Double { food.caloriesPer100g * factor }
    var protein: Double { food.proteinPer100g * factor }
    var carbs: Double { food.carbsPer100g * factor }
    var fat: Double { food.fatPer100g * factor }
    var fiber: Double { food.fiberPer100g * factor }
    var sugar: Double { food.sugarPer100g * factor }
    var salt: Double { food.saltPer100g * factor }
    var vitaminCMg: Double { food.vitaminCMgPer100g * factor }
    var calciumMg: Double { food.calciumMgPer100g * factor }
    var ironMg: Double { food.ironMgPer100g * factor }
}

struct DailyNutritionTotals: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var salt: Double = 0
    var vitaminCMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0

    static func from(_ items: [FoodLogEntryDetail]) -> DailyNutritionTotals {
        items.reduce(into: DailyNutritionTotals()) { totals, item in
            totals.calories += item.calories
            totals.protein += item.protein
            totals.carbs += item.carbs
            totals.fat += item.fat
            totals.fiber += item.fiber
            totals.sugar += item.sugar
            totals.salt += item.salt
            totals.vitaminCMg += item.vitaminCMg
            totals.calciumMg += item.calciumMg
            totals.ironMg += item.ironMg
        }
    }
}

// MARK: - Evidence-Based Nutrition Goals & Calculator

enum BiologicalSex: String, CaseIterable, Codable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: return "Männlich"
        case .female: return "Weiblich"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sedentary: return "Wenig aktiv (Büro)"
        case .light: return "Leicht aktiv (1–3× Training)"
        case .moderate: return "Moderat aktiv (3–5× Training)"
        case .active: return "Sehr aktiv (6–7× Training)"
        case .veryActive: return "Extrem aktiv (Körperliche Arbeit + Sport)"
        }
    }

    var palFactor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum NutritionGoalType: String, CaseIterable, Codable, Identifiable {
    case cutFast
    case cutModerate
    case maintain
    case leanBulk
    case bulk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cutFast: return "Starkes Defizit (−600 kcal)"
        case .cutModerate: return "Moderates Defizit (−400 kcal)"
        case .maintain: return "Halten / Recomp (±0 kcal)"
        case .leanBulk: return "Lean Bulk (+250 kcal)"
        case .bulk: return "Aufbau (+450 kcal)"
        }
    }

    var calorieDelta: Double {
        switch self {
        case .cutFast: return -600
        case .cutModerate: return -400
        case .maintain: return 0
        case .leanBulk: return 250
        case .bulk: return 450
        }
    }
}

struct NutritionGoals: Codable, Equatable {
    var targetCalories: Int = 2500
    var targetProteinGrams: Int = 160
    var targetCarbsGrams: Int = 290
    var targetFatGrams: Int = 75

    // Calculator profile inputs
    var sex: BiologicalSex = .male
    var ageYears: Int = 28
    var heightCm: Int = 180
    var weightKg: Double = 80.0
    var activityLevel: ActivityLevel = .moderate
    var goalType: NutritionGoalType = .leanBulk
    var proteinPerKg: Double = 2.0
    var fatPerKg: Double = 0.85

    /// Evidence-based Mifflin-St Jeor BMR
    var estimatedBMR: Double {
        let base = (10.0 * weightKg) + (6.25 * Double(heightCm)) - (5.0 * Double(ageYears))
        return sex == .male ? base + 5.0 : base - 161.0
    }

    /// Estimated Total Daily Energy Expenditure (TDEE)
    var estimatedTDEE: Double {
        estimatedBMR * activityLevel.palFactor
    }

    /// Recommended targets based on Mifflin-St Jeor + ISSN/Helms hypertrophy protein & fat guidelines
    mutating func applyEvidenceBasedCalculation() {
        let calories = max(1200, Int(round(estimatedTDEE + goalType.calorieDelta)))
        let protein = max(60, Int(round(weightKg * proteinPerKg)))
        let fat = max(35, Int(round(weightKg * fatPerKg)))
        let remainingKcal = max(0, calories - (protein * 4) - (fat * 9))
        let carbs = remainingKcal / 4

        targetCalories = calories
        targetProteinGrams = protein
        targetFatGrams = fat
        targetCarbsGrams = carbs
    }
}
