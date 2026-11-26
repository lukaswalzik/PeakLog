import SwiftUI

struct AddFoodSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    enum SourceTab: String, CaseIterable, Identifiable {
        case local = "Meine & Basis"
        case online = "Online-Suche"

        var id: String { rawValue }
    }

    let initialMealType: MealType
    var startWithScanner: Bool = false

    @State private var selectedMealType: MealType
    @State private var sourceTab: SourceTab = .local
    @State private var searchText: String = ""
    @State private var onlineResults: [FoodItem] = []
    @State private var isSearchingOnline: Bool = false
    @State private var onlineError: String? = nil

    @State private var isShowingScanner: Bool = false
    @State private var isLookingUpBarcode: Bool = false
    @State private var isShowingCustomFoodForm: Bool = false
    @State private var notFoundBarcode: String? = nil

    @State private var selectedFoodForLogging: FoodItem? = nil
    @State private var gramsText: String = "100"

    init(initialMealType: MealType, startWithScanner: Bool = false) {
        self.initialMealType = initialMealType
        self.startWithScanner = startWithScanner
        _selectedMealType = State(initialValue: initialMealType)
    }

    private var filteredLocalFoods: [FoodItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nutritionStore.foodItems }
        return nutritionStore.foodItems.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || (item.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (item.barcode?.contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Meal & Quick actions header
                VStack(spacing: 10) {
                    Picker("Mahlzeit", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { meal in
                            Text(meal.displayName).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("Barcode scannen", systemImage: "barcode.viewfinder")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            notFoundBarcode = nil
                            isShowingCustomFoodForm = true
                        } label: {
                            Label("Eigenes anlegen", systemImage: "plus.circle")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Picker("Quelle", selection: $sourceTab) {
                        ForEach(SourceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground))

                if isLookingUpBarcode {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Suche Barcode in Open Food Facts…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sourceTab == .local {
                    localList
                } else {
                    onlineList
                }
            }
            .navigationTitle("Lebensmittel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: sourceTab == .local ? "Lokal suchen…" : "Open Food Facts durchsuchen…")
            .onSubmit(of: .search) {
                if sourceTab == .online {
                    performOnlineSearch()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                if startWithScanner {
                    isShowingScanner = true
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView { code in
                    handleScannedBarcode(code)
                }
            }
            .sheet(isPresented: $isShowingCustomFoodForm) {
                CustomFoodFormView(prefilledBarcode: notFoundBarcode) { newFood in
                    nutritionStore.saveFoodItem(newFood)
                    openPortionPicker(for: newFood)
                }
            }
            .sheet(item: $selectedFoodForLogging) { food in
                PortionLogSheet(
                    food: food,
                    mealType: selectedMealType,
                    initialGrams: food.servingSizeGrams
                ) { grams in
                    nutritionStore.logFood(food, mealType: selectedMealType, grams: grams)
                    dismiss()
                }
            }
            .alert(
                "Produkt nicht gefunden",
                isPresented: Binding(
                    get: { notFoundBarcode != nil && !isShowingCustomFoodForm },
                    set: { if !$0 { notFoundBarcode = nil } }
                )
            ) {
                Button("Selbst anlegen") {
                    isShowingCustomFoodForm = true
                }
                Button("Abbrechen", role: .cancel) {
                    notFoundBarcode = nil
                }
            } message: {
                Text("Der Barcode \(notFoundBarcode ?? "") wurde in Open Food Facts nicht gefunden. Möchtest du das Lebensmittel selbst anlegen?")
            }
        }
    }

    private var localList: some View {
        Group {
            if filteredLocalFoods.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Lokal nichts gefunden",
                    message: "Wechsle zur Online-Suche (Open Food Facts) oder lege ein eigenes Lebensmittel an.",
                    actionTitle: "Online suchen"
                ) {
                    sourceTab = .online
                    performOnlineSearch()
                }
            } else {
                List(filteredLocalFoods) { item in
                    Button {
                        openPortionPicker(for: item)
                    } label: {
                        FoodItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private var onlineList: some View {
        VStack(spacing: 0) {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    performOnlineSearch()
                } label: {
                    Label("„\(searchText)“ in Open Food Facts suchen", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if isSearchingOnline {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Durchsuche Open Food Facts…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = onlineError {
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "Suche fehlgeschlagen",
                    message: error
                )
            } else if onlineResults.isEmpty {
                EmptyStateView(
                    systemImage: "globe",
                    title: "Open Food Facts Suche",
                    message: "Gib oben einen Produktnamen ein (z. B. „Magerquark“, „Alpro“, „ESN“) und tippe auf Suchen."
                )
            } else {
                List(onlineResults) { item in
                    Button {
                        openPortionPicker(for: item)
                    } label: {
                        FoodItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func openPortionPicker(for item: FoodItem) {
        gramsText = Formatters.weight(item.servingSizeGrams)
        selectedFoodForLogging = item
    }

    private func performOnlineSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingOnline = true
        onlineError = nil

        Task {
            do {
                let results = try await OpenFoodFactsService.searchProducts(query: query)
                await MainActor.run {
                    onlineResults = results
                    isSearchingOnline = false
                }
            } catch {
                await MainActor.run {
                    onlineError = error.localizedDescription
                    isSearchingOnline = false
                }
            }
        }
    }

    private func handleScannedBarcode(_ code: String) {
        if let local = nutritionStore.findLocalFood(byBarcode: code) {
            openPortionPicker(for: local)
            return
        }

        isLookingUpBarcode = true
        Task {
            do {
                let product = try await OpenFoodFactsService.fetchProduct(barcode: code)
                await MainActor.run {
                    isLookingUpBarcode = false
                    nutritionStore.saveFoodItem(product)
                    openPortionPicker(for: product)
                }
            } catch {
                await MainActor.run {
                    isLookingUpBarcode = false
                    notFoundBarcode = code
                }
            }
        }
    }
}

private struct FoodItemRow: View {
    let item: FoodItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let brand = item.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("P \(Int(round(item.proteinPer100g)))g · K \(Int(round(item.carbsPer100g)))g · F \(Int(round(item.fatPer100g)))g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(round(item.caloriesPer100g)))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text("kcal/100g")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct PortionLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let food: FoodItem
    let mealType: MealType
    let onConfirm: (Double) -> Void

    @State private var gramsText: String

    init(food: FoodItem, mealType: MealType, initialGrams: Double, onConfirm: @escaping (Double) -> Void) {
        self.food = food
        self.mealType = mealType
        self.onConfirm = onConfirm
        _gramsText = State(initialValue: Formatters.weight(initialGrams))
    }

    private var grams: Double {
        max(0, Formatters.parseWeight(gramsText) ?? 0)
    }

    private var factor: Double { grams / 100.0 }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(food.name)) {
                    HStack {
                        Text("Menge")
                        Spacer()
                        TextField("100", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("g")
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        quickGramButton(grams: food.servingSizeGrams, label: "Portion (\(Int(food.servingSizeGrams))g)")
                        quickGramButton(grams: 100, label: "100g")
                        quickGramButton(grams: 200, label: "200g")
                    }
                }

                Section(header: Text("Nährwerte für \(Formatters.weight(grams)) g")) {
                    HStack {
                        Text("Kalorien")
                        Spacer()
                        Text("\(Int(round(food.caloriesPer100g * factor))) kcal")
                            .fontWeight(.bold)
                    }
                    HStack {
                        Text("Eiweiß")
                        Spacer()
                        Text("\(Formatters.weight(food.proteinPer100g * factor)) g")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Kohlenhydrate")
                        Spacer()
                        Text("\(Formatters.weight(food.carbsPer100g * factor)) g")
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Fett")
                        Spacer()
                        Text("\(Formatters.weight(food.fatPer100g * factor)) g")
                            .foregroundColor(.purple)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(mealType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        onConfirm(grams)
                        dismiss()
                    }
                    .disabled(grams <= 0)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func quickGramButton(grams: Double, label: String) -> some View {
        Button(label) {
            gramsText = Formatters.weight(grams)
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
