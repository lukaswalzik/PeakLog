import SwiftUI

struct MacroHelperSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    let remainingCalories: Int
    let remainingProtein: Int
    let remainingCarbs: Int
    let remainingFat: Int
    let defaultMealType: MealType

    @State private var selectedMealType: MealType
    @State private var loggedFeedbackId: String? = nil

    init(
        remainingCalories: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        remainingFat: Int,
        defaultMealType: MealType
    ) {
        self.remainingCalories = remainingCalories
        self.remainingProtein = remainingProtein
        self.remainingCarbs = remainingCarbs
        self.remainingFat = remainingFat
        self.defaultMealType = defaultMealType
        _selectedMealType = State(initialValue: defaultMealType)
    }

    private struct FoodSuggestion: Identifiable {
        let food: FoodItem
        let suggestedGrams: Double
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let reason: String

        var id: String { food.id }
    }

    private var suggestions: [FoodSuggestion] {
        let maxKcal = max(150.0, Double(remainingCalories > 0 ? remainingCalories : 350))
        let needProtein = Double(max(0, remainingProtein))
        let needCarbs = Double(max(0, remainingCarbs))

        let candidates = nutritionStore.foodItems.filter { $0.caloriesPer100g > 15 }
        let scored: [(FoodSuggestion, Double)] = candidates.compactMap { food in
            // Compute ideal grams to fill either protein gap or calorie budget nicely
            var grams: Double = food.servingSizeGrams > 0 ? food.servingSizeGrams : 100
            if needProtein >= 15 && food.proteinPer100g >= 10 {
                let targetGramsForProtein = (needProtein / food.proteinPer100g) * 100.0
                let maxGramsForKcal = (maxKcal / max(1, food.caloriesPer100g)) * 100.0
                grams = min(targetGramsForProtein, maxGramsForKcal, 350.0)
            } else {
                let maxGramsForKcal = (maxKcal / max(1, food.caloriesPer100g)) * 100.0
                grams = min(grams, maxGramsForKcal)
            }
            // Round to nice 10g steps, minimum 25g
            grams = max(25, (grams / 10.0).rounded() * 10.0)

            let factor = grams / 100.0
            let kcal = food.caloriesPer100g * factor
            let prot = food.proteinPer100g * factor
            let carb = food.carbsPer100g * factor
            let fat = food.fatPer100g * factor

            if remainingCalories > 80 && kcal > Double(remainingCalories) * 1.15 {
                return nil
            }

            // Score higher if favorite, high protein density when protein is needed, or good carb match
            var score = 0.0
            if food.isFavorite { score += 35 }
            if needProtein >= 12 {
                let proteinDensity = (food.proteinPer100g * 4.0) / max(1, food.caloriesPer100g)
                score += proteinDensity * 60.0 + min(prot, needProtein) * 0.8
            } else if needCarbs >= 25 {
                let carbDensity = (food.carbsPer100g * 4.0) / max(1, food.caloriesPer100g)
                score += carbDensity * 50.0
            } else {
                score += 20
            }

            let reason: String
            if food.isFavorite && prot >= 15 {
                reason = "Favorit · Protein-Boost"
            } else if food.isFavorite {
                reason = "Dein Favorit"
            } else if (food.proteinPer100g * 4.0) / max(1, food.caloriesPer100g) >= 0.45 {
                reason = "Top Protein/kcal"
            } else {
                reason = "Passt ins Rest-Budget"
            }

            let suggestion = FoodSuggestion(
                food: food,
                suggestedGrams: grams,
                calories: kcal,
                protein: prot,
                carbs: carb,
                fat: fat,
                reason: reason
            )
            return (suggestion, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map { $0.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Offenes Tagesbudget") {
                    HStack(spacing: 10) {
                        budgetChip(title: "kcal", value: "\(remainingCalories)", color: remainingCalories >= 0 ? .accentColor : .orange)
                        budgetChip(title: "Eiweiß", value: "\(remainingProtein)g", color: .blue)
                        budgetChip(title: "Carbs", value: "\(remainingCarbs)g", color: .orange)
                        budgetChip(title: "Fett", value: "\(remainingFat)g", color: .purple)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

                    Picker("Hinzufügen zu", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { meal in
                            Text(meal.displayName).tag(meal)
                        }
                    }
                }

                if !nutritionStore.savedMeals.isEmpty {
                    let fittingMeals = nutritionStore.savedMeals.filter {
                        remainingCalories <= 0 || $0.totalCalories <= Double(remainingCalories) * 1.15
                    }
                    if !fittingMeals.isEmpty {
                        Section("Passende gespeicherte Mahlzeiten") {
                            ForEach(fittingMeals.prefix(4)) { meal in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meal.meal.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("\(Int(round(meal.totalCalories))) kcal · \(Int(round(meal.totalProtein)))g E · \(Int(round(meal.totalCarbs)))g KH")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Loggen") {
                                        nutritionStore.logSavedMeal(meal, mealType: selectedMealType)
                                        loggedFeedbackId = meal.id
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Passende Lebensmittel-Vorschläge") {
                    if suggestions.isEmpty {
                        Text("Dein Tagesbudget ist bereits ausgeschöpft oder es wurden noch keine passenden Lebensmittel gefunden.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(suggestions) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        if item.food.isFavorite {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                        Text(item.food.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    Text("\(Int(item.suggestedGrams)) g · \(Int(round(item.calories))) kcal · \(Int(round(item.protein)))g E · \(Int(round(item.carbs)))g KH")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.reason)
                                        .font(.caption2)
                                        .foregroundColor(.accentColor)
                                }

                                Spacer()

                                Button {
                                    nutritionStore.logFood(
                                        item.food,
                                        mealType: selectedMealType,
                                        grams: item.suggestedGrams
                                    )
                                    loggedFeedbackId = item.id
                                } label: {
                                    Image(systemName: loggedFeedbackId == item.id ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(loggedFeedbackId == item.id ? .green : .accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Was fehlt mir noch?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func budgetChip(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
