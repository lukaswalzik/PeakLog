import SwiftUI

struct SavedMealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    struct DraftIngredient: Identifiable, Equatable {
        let id: String
        let food: FoodItem
        var gramsText: String

        var grams: Double {
            max(0, Formatters.parseWeight(gramsText) ?? 0)
        }

        var calories: Double { food.caloriesPer100g * grams / 100.0 }
        var protein: Double { food.proteinPer100g * grams / 100.0 }
        var carbs: Double { food.carbsPer100g * grams / 100.0 }
        var fat: Double { food.fatPer100g * grams / 100.0 }

        init(id: String = UUID().uuidString, food: FoodItem, grams: Double) {
            self.id = id
            self.food = food
            self.gramsText = Formatters.weight(grams)
        }
    }

    let existingMeal: SavedMealWithItems?
    let onSave: (SavedMeal, [SavedMealItem]) -> Void

    @State private var name: String
    @State private var notes: String
    @State private var ingredients: [DraftIngredient]
    @State private var isShowingFoodPicker: Bool = false

    init(
        existingMeal: SavedMealWithItems? = nil,
        prefilledName: String = "",
        prefilledIngredients: [(FoodItem, Double)] = [],
        onSave: @escaping (SavedMeal, [SavedMealItem]) -> Void
    ) {
        self.existingMeal = existingMeal
        self.onSave = onSave

        if let existing = existingMeal {
            _name = State(initialValue: existing.meal.name)
            _notes = State(initialValue: existing.meal.notes ?? "")
            _ingredients = State(initialValue: existing.items.map {
                DraftIngredient(id: $0.item.id, food: $0.food, grams: $0.item.grams)
            })
        } else {
            _name = State(initialValue: prefilledName)
            _notes = State(initialValue: "")
            _ingredients = State(initialValue: prefilledIngredients.map {
                DraftIngredient(food: $0.0, grams: $0.1)
            })
        }
    }

    private var totalCalories: Double { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { ingredients.reduce(0) { $0 + $1.protein } }
    private var totalCarbs: Double { ingredients.reduce(0) { $0 + $1.carbs } }
    private var totalFat: Double { ingredients.reduce(0) { $0 + $1.fat } }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ingredients.isEmpty
            && ingredients.allSatisfy { $0.grams > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Mahlzeit")) {
                    TextField("Name (z. B. Post-Workout Shake, Porridge)", text: $name)
                    TextField("Notizen (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(header: Text("Gesamtnährwerte")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(round(totalCalories))) kcal")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("P \(Int(round(totalProtein)))g · K \(Int(round(totalCarbs)))g · F \(Int(round(totalFat)))g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(ingredients.count) Zutaten")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Zutaten")) {
                    if ingredients.isEmpty {
                        Text("Füge Lebensmittel hinzu, um deine Mahlzeit zusammenzustellen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($ingredients) { $ing in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ing.food.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text("\(Int(round(ing.calories))) kcal · P \(Int(round(ing.protein)))g")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                TextField("100", text: $ing.gramsText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text("g")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            ingredients.remove(atOffsets: offsets)
                        }
                    }

                    Button {
                        isShowingFoodPicker = true
                    } label: {
                        Label("Zutat hinzufügen", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(existingMeal == nil ? "Neue Mahlzeit" : "Mahlzeit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isShowingFoodPicker) {
                IngredientFoodPickerSheet { food in
                    nutritionStore.saveFoodItem(food)
                    ingredients.append(DraftIngredient(food: food, grams: food.servingSizeGrams))
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let mealId = existingMeal?.meal.id ?? UUID().uuidString

        let meal = SavedMeal(
            id: mealId,
            name: trimmedName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: existingMeal?.meal.createdAt ?? Date()
        )

        let items = ingredients.enumerated().map { idx, ing in
            SavedMealItem(
                id: ing.id,
                mealId: mealId,
                foodItemId: ing.food.id,
                grams: max(1, ing.grams),
                sortOrder: idx
            )
        }

        onSave(meal, items)
        dismiss()
    }
}

private struct IngredientFoodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    let onPick: (FoodItem) -> Void

    @State private var searchText: String = ""
    @State private var isOnline: Bool = false
    @State private var onlineResults: [FoodItem] = []
    @State private var isLoading: Bool = false

    private var filteredLocal: [FoodItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nutritionStore.foodItems }
        return nutritionStore.foodItems.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Quelle", selection: $isOnline) {
                    Text("Meine & Basis").tag(false)
                    Text("Online-Suche").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                HStack(spacing: 8) {
                    TextField(isOnline ? "Online suchen (z. B. Hafermilch)…" : "Lokal suchen…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if isOnline { runSearch() }
                        }
                    if isOnline {
                        Button("Suchen") {
                            runSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if isLoading {
                    ProgressView("Suche…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(isOnline ? onlineResults : filteredLocal) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text("P \(Int(round(item.proteinPer100g)))g · K \(Int(round(item.carbsPer100g)))g · F \(Int(round(item.fatPer100g)))g")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(round(item.caloriesPer100g))) kcal")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Zutat wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isLoading = true
        Task {
            let results = (try? await OpenFoodFactsService.searchProducts(query: query)) ?? []
            await MainActor.run {
                onlineResults = results
                isLoading = false
            }
        }
    }
}
