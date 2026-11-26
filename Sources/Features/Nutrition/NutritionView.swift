import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var nutritionStore: NutritionStore

    @State private var addSheetMeal: MealType? = nil
    @State private var openScannerDirectly: Bool = false
    @State private var isShowingGoalsSheet: Bool = false
    @State private var showMicrosExpanded: Bool = false

    private var totals: DailyNutritionTotals {
        nutritionStore.dayTotals
    }

    private var goals: NutritionGoals {
        nutritionStore.goals
    }

    private var remainingCalories: Int {
        goals.targetCalories - Int(round(totals.calories))
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(nutritionStore.selectedDate) {
            return "Heute"
        } else if cal.isDateInYesterday(nutritionStore.selectedDate) {
            return "Gestern"
        } else if cal.isDateInTomorrow(nutritionStore.selectedDate) {
            return "Morgen"
        }
        return Formatters.shortDate(nutritionStore.selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateSwitcherBar
                    caloriesAndMacrosCard
                    micronutrientsCard
                    mealsSection
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Ernährung")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isShowingGoalsSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Ziele & Kalorienrechner")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        openScannerDirectly = true
                        addSheetMeal = defaultMealForCurrentHour()
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title3)
                    }
                    .accessibilityLabel("Barcode scannen")
                }
            }
            .sheet(item: $addSheetMeal) { meal in
                AddFoodSheetView(
                    initialMealType: meal,
                    startWithScanner: openScannerDirectly
                )
                .onDisappear {
                    openScannerDirectly = false
                }
            }
            .sheet(isPresented: $isShowingGoalsSheet) {
                NutritionGoalsView(initialGoals: nutritionStore.goals)
            }
        }
    }

    private var dateSwitcherBar: some View {
        HStack {
            Button {
                nutritionStore.shiftSelectedDate(byDays: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .padding(8)
            }

            Spacer()

            Button {
                nutritionStore.selectedDate = Date()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                    Text(dateLabel)
                        .font(.headline)
                }
                .foregroundColor(.primary)
            }

            Spacer()

            Button {
                nutritionStore.shiftSelectedDate(byDays: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .padding(8)
            }
        }
        .strongCard(padding: 8)
    }

    private var caloriesAndMacrosCard: some View {
        let calorieProgress = goals.targetCalories > 0
            ? min(1.0, totals.calories / Double(goals.targetCalories))
            : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(round(totals.calories))) / \(goals.targetCalories) kcal")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    if remainingCalories >= 0 {
                        Text("Noch \(remainingCalories) kcal übrig")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(abs(remainingCalories)) kcal über Ziel")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button {
                    isShowingGoalsSheet = true
                } label: {
                    Text("Ziele")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ProgressView(value: calorieProgress)
                .progressViewStyle(.linear)
                .tint(remainingCalories < 0 ? .orange : .accentColor)

            HStack(spacing: 12) {
                MacroProgressColumn(
                    title: "Eiweiß",
                    current: totals.protein,
                    target: Double(goals.targetProteinGrams),
                    color: .blue
                )
                MacroProgressColumn(
                    title: "Kohlenhydrate",
                    current: totals.carbs,
                    target: Double(goals.targetCarbsGrams),
                    color: .orange
                )
                MacroProgressColumn(
                    title: "Fett",
                    current: totals.fat,
                    target: Double(goals.targetFatGrams),
                    color: .purple
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var micronutrientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMicrosExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Mikronährstoffe & Ballaststoffe", systemImage: "leaf.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("Ballastst. \(Int(round(totals.fiber)))g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: showMicrosExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showMicrosExpanded {
                Divider()
                VStack(spacing: 8) {
                    MicroRow(name: "Ballaststoffe", current: totals.fiber, target: 30, unit: "g", color: .green)
                    MicroRow(name: "Zucker", current: totals.sugar, target: 50, unit: "g", color: .pink)
                    MicroRow(name: "Salz", current: totals.salt, target: 6, unit: "g", color: .gray)
                    MicroRow(name: "Vitamin C", current: totals.vitaminCMg, target: 100, unit: "mg", color: .orange)
                    MicroRow(name: "Kalzium", current: totals.calciumMg, target: 1000, unit: "mg", color: .cyan)
                    MicroRow(name: "Eisen", current: totals.ironMg, target: 12, unit: "mg", color: .red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var mealsSection: some View {
        VStack(spacing: 12) {
            ForEach(MealType.allCases) { meal in
                let items = nutritionStore.entries(for: meal)
                let mealKcal = Int(round(nutritionStore.calories(for: meal)))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: meal.systemImage)
                            .foregroundColor(meal.accentColor)
                        Text(meal.displayName)
                            .font(.headline)
                        Spacer()
                        Text("\(mealKcal) kcal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Button {
                            openScannerDirectly = false
                            addSheetMeal = meal
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.leading, 4)
                    }

                    if !items.isEmpty {
                        Divider()
                        ForEach(items) { detail in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(detail.food.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text("\(Formatters.weight(detail.entry.grams)) g · P \(Int(round(detail.protein)))g · K \(Int(round(detail.carbs)))g · F \(Int(round(detail.fat)))g")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(Int(round(detail.calories))) kcal")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Button(role: .destructive) {
                                    nutritionStore.deleteLogEntry(id: detail.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .strongCard()
            }
        }
    }

    private func defaultMealForCurrentHour() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

private struct MacroProgressColumn: View {
    let title: String
    let current: Double
    let target: Double
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, current / target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(Int(round(current))) / \(Int(round(target))) g")
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MicroRow: View {
    let name: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, current / target)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                Spacer()
                Text("\(Formatters.weight(current)) / \(Formatters.weight(target)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)
        }
    }
}
