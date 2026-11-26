import SwiftUI

struct AddFoodSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    enum SourceTab: String, CaseIterable, Identifiable {
        case local = "Lebensmittel"
        case meals = "Mahlzeiten"
        case online = "Online"

        var id: String { rawValue }
    }

    let initialMealType: MealType
    var startWithScanner: Bool = false

    @State private var selectedMealType: MealType
    @State private var sourceTab: SourceTab = .local
    @State private var showFavoritesOnly: Bool = false
    @State private var searchText: String = ""

    @State private var onlineResults: [FoodItem] = []
    @State private var hasSearchedOnline: Bool = false
    @State private var isSearchingOnline: Bool = false
    @State private var onlineError: String? = nil

    @State private var isShowingScanner: Bool = false
    @State private var isLookingUpBarcode: Bool = false
    @State private var isShowingCustomFoodForm: Bool = false
    @State private var notFoundBarcode: String? = nil

    @State private var isShowingCreateMeal: Bool = false
    @State private var editingMeal: SavedMealWithItems? = nil
    @State private var selectedMealForLogging: SavedMealWithItems? = nil

    @State private var selectedFoodForLogging: FoodItem? = nil

    init(initialMealType: MealType, startWithScanner: Bool = false) {
        self.initialMealType = initialMealType
        self.startWithScanner = startWithScanner
        _selectedMealType = State(initialValue: initialMealType)
    }

    private var filteredLocalFoods: [FoodItem] {
        let base = showFavoritesOnly ? nutritionStore.favoriteFoods : nutritionStore.foodItems
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || (item.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (item.barcode?.contains(trimmed) ?? false)
        }
    }

    private var filteredSavedMeals: [SavedMealWithItems] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nutritionStore.savedMeals }
        return nutritionStore.savedMeals.filter {
            $0.meal.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            Label("Barcode", systemImage: "barcode.viewfinder")
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
                            Label("Eigenes", systemImage: "plus.circle")
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

                    // Direct always-visible search bar (reliable for both local & online search)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(searchPlaceholder, text: $searchText)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    if sourceTab == .online {
                                        performOnlineSearch()
                                    }
                                }
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    onlineResults = []
                                    hasSearchedOnline = false
                                    onlineError = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if sourceTab == .online {
                            Button("Suchen") {
                                performOnlineSearch()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingOnline)
                        } else if sourceTab == .local {
                            Button {
                                showFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                    .foregroundColor(showFavoritesOnly ? .yellow : .secondary)
                                    .padding(8)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .accessibilityLabel("Nur Favoriten anzeigen")
                        }
                    }
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
                } else {
                    switch sourceTab {
                    case .local:
                        localList
                    case .meals:
                        savedMealsList
                    case .online:
                        onlineList
                    }
                }
            }
            .navigationTitle("Lebensmittel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onChange(of: sourceTab) { newTab in
                if newTab == .online && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onlineResults.isEmpty {
                    performOnlineSearch()
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
                    selectedFoodForLogging = newFood
                }
            }
            .sheet(isPresented: $isShowingCreateMeal) {
                SavedMealEditorView { meal, items in
                    nutritionStore.saveSavedMeal(meal, items: items)
                }
            }
            .sheet(item: $editingMeal) { meal in
                SavedMealEditorView(existingMeal: meal) { updatedMeal, items in
                    nutritionStore.saveSavedMeal(updatedMeal, items: items)
                }
            }
            .sheet(item: $selectedMealForLogging) { meal in
                SavedMealLogSheet(meal: meal, mealType: selectedMealType) { multiplier in
                    nutritionStore.logSavedMeal(meal, mealType: selectedMealType, multiplier: multiplier)
                    dismiss()
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

    private var searchPlaceholder: String {
        switch sourceTab {
        case .local: return showFavoritesOnly ? "Favoriten durchsuchen…" : "Meine & Basis durchsuchen…"
        case .meals: return "Mahlzeiten durchsuchen…"
        case .online: return "Produktname (z. B. Magerquark, ESN)…"
        }
    }

    private var localList: some View {
        Group {
            if filteredLocalFoods.isEmpty {
                EmptyStateView(
                    systemImage: showFavoritesOnly ? "star" : "magnifyingglass",
                    title: showFavoritesOnly ? "Keine Favoriten" : "Lokal nichts gefunden",
                    message: showFavoritesOnly
                        ? "Tippe bei einem Lebensmittel auf den Stern, um es als Favorit ganz oben anzuheften."
                        : "Wechsle zur Online-Suche (Open Food Facts) oder lege ein eigenes Lebensmittel an.",
                    actionTitle: showFavoritesOnly ? "Alle anzeigen" : "Online suchen"
                ) {
                    if showFavoritesOnly {
                        showFavoritesOnly = false
                    } else {
                        sourceTab = .online
                        performOnlineSearch()
                    }
                }
            } else {
                List(filteredLocalFoods) { item in
                    FoodItemRow(
                        item: item,
                        isFavorite: item.isFavorite,
                        onSelect: {
                            selectedFoodForLogging = item
                        },
                        onToggleFavorite: {
                            nutritionStore.toggleFavorite(for: item)
                        }
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private var savedMealsList: some View {
        VStack(spacing: 0) {
            Button {
                isShowingCreateMeal = true
            } label: {
                Label("Neue Mahlzeit zusammenstellen", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if filteredSavedMeals.isEmpty {
                EmptyStateView(
                    systemImage: "takeoutbag.and.cup.and.straw.fill",
                    title: "Noch keine Mahlzeiten",
                    message: "Stelle z. B. dein Standard-Frühstück oder deinen Post-Workout-Shake aus mehreren Lebensmitteln zusammen und logge ihn künftig mit 1 Tipp."
                )
            } else {
                List {
                    ForEach(filteredSavedMeals) { saved in
                        Button {
                            selectedMealForLogging = saved
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(saved.meal.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("\(saved.items.count) Zutaten · P \(Int(round(saved.totalProtein)))g · K \(Int(round(saved.totalCarbs)))g · F \(Int(round(saved.totalFat)))g")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(round(saved.totalCalories)))")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text("kcal")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                nutritionStore.deleteSavedMeal(id: saved.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button {
                                editingMeal = saved
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var onlineList: some View {
        Group {
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
                    message: error,
                    actionTitle: "Erneut versuchen"
                ) {
                    performOnlineSearch()
                }
            } else if onlineResults.isEmpty {
                EmptyStateView(
                    systemImage: "globe",
                    title: hasSearchedOnline ? "Keine Treffer" : "Open Food Facts Online-Suche",
                    message: hasSearchedOnline
                        ? "Für „\(searchText)“ wurden keine Produkte gefunden. Probiere einen kürzeren Begriff oder lege das Produkt selbst an."
                        : "Gib oben einen Produktnamen ein (z. B. „Magerquark“, „Alpro“, „ESN“) und tippe auf Suchen."
                )
            } else {
                List(onlineResults) { item in
                    let isFav = nutritionStore.foodItems.first(where: { $0.id == item.id })?.isFavorite ?? false
                    FoodItemRow(
                        item: item,
                        isFavorite: isFav,
                        onSelect: {
                            selectedFoodForLogging = item
                        },
                        onToggleFavorite: {
                            nutritionStore.toggleFavorite(for: item)
                        }
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private func performOnlineSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingOnline = true
        hasSearchedOnline = true
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
            selectedFoodForLogging = local
            return
        }

        isLookingUpBarcode = true
        Task {
            do {
                let product = try await OpenFoodFactsService.fetchProduct(barcode: code)
                await MainActor.run {
                    isLookingUpBarcode = false
                    nutritionStore.saveFoodItem(product)
                    selectedFoodForLogging = product
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
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.5))
                    .font(.body)
            }
            .buttonStyle(.plain)

            Button(action: onSelect) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
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
                            .foregroundColor(.primary)
                        Text("kcal/100g")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct SavedMealLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let meal: SavedMealWithItems
    let mealType: MealType
    let onConfirm: (Double) -> Void

    @State private var multiplier: Double = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(meal.meal.name)) {
                    HStack(spacing: 8) {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                            Button("\(Formatters.weight(value))×") {
                                multiplier = value
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(multiplier == value ? .accentColor : .gray.opacity(0.3))
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Text("Gesamt (\(Formatters.weight(multiplier))×)")
                        Spacer()
                        Text("\(Int(round(meal.totalCalories * multiplier))) kcal")
                            .fontWeight(.bold)
                    }

                    Text("Eiweiß \(Int(round(meal.totalProtein * multiplier)))g · KH \(Int(round(meal.totalCarbs * multiplier)))g · Fett \(Int(round(meal.totalFat * multiplier)))g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Enthaltene Zutaten")) {
                    ForEach(meal.items) { detail in
                        HStack {
                            Text(detail.food.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Formatters.weight(detail.item.grams * multiplier)) g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                        onConfirm(multiplier)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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
