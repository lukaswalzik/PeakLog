import SwiftUI

struct AIRecipeChefSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore
    @ObservedObject private var mistral = MistralAIService.shared

    let remainingCalories: Int
    let remainingProtein: Int
    let remainingCarbs: Int
    let remainingFat: Int
    let defaultMealType: MealType

    @State private var mealType: MealType
    @State private var availableIngredients: String = ""
    @State private var selectedStyle: String = "Schnell (5–10 Min.)"
    @State private var isGenerating: Bool = false
    @State private var recipe: MistralAIService.AIGeneratedRecipe? = nil
    @State private var errorMessage: String? = nil
    @State private var savedMealFeedback: Bool = false

    private let styles = ["Schnell (5–10 Min.)", "High-Protein Bowl/Shake", "Warmes Gericht", "Süßer Protein-Snack"]

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
        _mealType = State(initialValue: defaultMealType)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Offenes Tagesbudget")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        HStack(spacing: 8) {
                            chip("\(max(0, remainingCalories)) kcal", .accentColor)
                            chip("\(max(0, remainingProtein))g E", .blue)
                            chip("\(max(0, remainingCarbs))g KH", .orange)
                            chip("\(max(0, remainingFat))g F", .purple)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(styles, id: \.self) { style in
                                    Button(style) {
                                        selectedStyle = style
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .tint(selectedStyle == style ? .accentColor : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }

                        TextField("Was hast du da? (optional, z. B. Eier, Skyr, Beeren)", text: $availableIngredients)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        Button {
                            generateRecipe()
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "flame.fill")
                                }
                                Text(isGenerating ? "Mistral kocht..." : "Passendes Rezept vorschlagen")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || !mistral.isConfigured)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let recipe = recipe {
                        let totalKcal = recipe.ingredients.reduce(0) { $0 + $1.totalCalories }
                        let totalProt = recipe.ingredients.reduce(0) { $0 + $1.totalProtein }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title)
                                        .font(.headline)
                                    Text("⏱ ca. \(recipe.prepTimeMinutes) Min. · \(Int(round(totalKcal))) kcal · \(Int(round(totalProt)))g Eiweiß")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            Divider()

                            Text("Zutaten")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ForEach(recipe.ingredients) { ing in
                                HStack {
                                    Text("• \(ing.name)")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(round(ing.grams))) g (\(Int(round(ing.totalCalories))) kcal)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !recipe.steps.isEmpty {
                                Divider()
                                Text("Zubereitung")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { idx, step in
                                    Text("\(idx + 1). \(step)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Picker("Loggen zu", selection: $mealType) {
                                ForEach(MealType.allCases) { meal in
                                    Text(meal.displayName).tag(meal)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button {
                                logRecipe(recipe)
                            } label: {
                                Label("Rezept direkt loggen", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button {
                                saveAsMealTemplate(recipe)
                            } label: {
                                Label(
                                    savedMealFeedback ? "Als Mahlzeit gespeichert!" : "Als Vorlage-Mahlzeit speichern",
                                    systemImage: savedMealFeedback ? "checkmark" : "bookmark"
                                )
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(savedMealFeedback)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strongCard()
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("KI-Makro-Koch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func generateRecipe() {
        isGenerating = true
        errorMessage = nil
        savedMealFeedback = false
        Task {
            do {
                let result = try await mistral.generateMacroRecipe(
                    remainingCalories: remainingCalories,
                    remainingProtein: remainingProtein,
                    remainingCarbs: remainingCarbs,
                    remainingFat: remainingFat,
                    availableIngredients: availableIngredients,
                    style: selectedStyle
                )
                await MainActor.run {
                    recipe = result
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func logRecipe(_ recipe: MistralAIService.AIGeneratedRecipe) {
        for ing in recipe.ingredients {
            nutritionStore.logFood(ing.toFoodItem(), mealType: mealType, grams: ing.grams)
        }
        dismiss()
    }

    private func saveAsMealTemplate(_ recipe: MistralAIService.AIGeneratedRecipe) {
        let meal = SavedMeal(name: recipe.title, notes: "KI-Rezept (\(recipe.prepTimeMinutes) Min.)")
        var mealItems: [SavedMealItem] = []
        for (idx, ing) in recipe.ingredients.enumerated() {
            let food = ing.toFoodItem()
            nutritionStore.saveFoodItem(food)
            mealItems.append(SavedMealItem(mealId: meal.id, foodItemId: food.id, grams: ing.grams, sortOrder: idx))
        }
        nutritionStore.saveSavedMeal(meal, items: mealItems)
        savedMealFeedback = true
    }
}
