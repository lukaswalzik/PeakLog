import Charts
import SwiftUI
import UIKit

struct NutritionView: View {
    @EnvironmentObject private var nutritionStore: NutritionStore
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore

    @State private var addSheetMeal: MealType? = nil
    @State private var openScannerDirectly: Bool = false
    @State private var isShowingGoalsSheet: Bool = false
    @State private var isShowingAdaptiveTDEE: Bool = false
    @State private var isShowingMacroHelper: Bool = false
    @State private var isShowingAIScanner: Bool = false
    @State private var openAIScannerCamera: Bool = false
    @State private var isShowingRecipeChef: Bool = false
    @State private var isShowingDayTemplates: Bool = false
    @State private var showMicrosExpanded: Bool = false
    @State private var showWeeklyTrendExpanded: Bool = false
    @State private var mealToSaveAsTemplate: MealType? = nil
    @State private var isShowingAddSupplementAlert: Bool = false
    @State private var newSupplementName: String = ""
    @State private var newSupplementDosage: String = ""
    @State private var copyFeedbackMessage: String? = nil

    private var totals: DailyNutritionTotals {
        nutritionStore.dayTotals
    }

    private var goals: NutritionGoals {
        nutritionStore.goals
    }

    private var autoDetectedTrainingDay: Bool {
        let cal = Calendar.current
        let day = nutritionStore.selectedDate
        let hasWorkout = historyStore.completedWorkouts.contains { cal.isDate($0.workout.startedAt, inSameDayAs: day) }
        if hasWorkout { return true }
        return cardioStore.sessions.contains { cal.isDate($0.startedAt, inSameDayAs: day) }
    }

    private var isTrainingDay: Bool {
        nutritionStore.isTrainingDay(date: nutritionStore.selectedDate, autoDetected: autoDetectedTrainingDay)
    }

    private var effectiveTargetCalories: Int {
        goals.effectiveCalories(isTrainingDay: isTrainingDay)
    }

    private var effectiveTargetCarbs: Int {
        goals.effectiveCarbs(isTrainingDay: isTrainingDay)
    }

    private var remainingCalories: Int {
        effectiveTargetCalories - Int(round(totals.calories))
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
                    waterAndSupplementsCard
                    weeklyTrendCard
                    micronutrientsCard
                    mealsSection
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Ernährung")
            .onAppear {
                wellnessStore.setSelectedDate(nutritionStore.selectedDate)
            }
            .onChange(of: nutritionStore.selectedDate) { newDate in
                wellnessStore.setSelectedDate(newDate)
            }
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
                    HStack(spacing: 14) {
                        Button {
                            openAIScannerCamera = true
                            isShowingAIScanner = true
                        } label: {
                            Image(systemName: "camera.viewfinder")
                                .font(.title3)
                        }
                        .accessibilityLabel("Mahlzeit fotografieren (KI)")

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
            .sheet(isPresented: $isShowingAdaptiveTDEE) {
                AdaptiveTDEESheetView()
            }
            .sheet(isPresented: $isShowingAIScanner) {
                AIMealScannerSheetView(
                    initialMealType: defaultMealForCurrentHour(),
                    autoOpenCamera: openAIScannerCamera
                )
                .onDisappear {
                    openAIScannerCamera = false
                }
            }
            .sheet(isPresented: $isShowingRecipeChef) {
                AIRecipeChefSheetView(
                    remainingCalories: remainingCalories,
                    remainingProtein: goals.targetProteinGrams - Int(round(totals.protein)),
                    remainingCarbs: effectiveTargetCarbs - Int(round(totals.carbs)),
                    remainingFat: goals.targetFatGrams - Int(round(totals.fat)),
                    defaultMealType: defaultMealForCurrentHour()
                )
            }
            .sheet(isPresented: $isShowingDayTemplates) {
                DayTemplatesSheetView()
            }
            .sheet(isPresented: $isShowingMacroHelper) {
                MacroHelperSheetView(
                    remainingCalories: remainingCalories,
                    remainingProtein: goals.targetProteinGrams - Int(round(totals.protein)),
                    remainingCarbs: effectiveTargetCarbs - Int(round(totals.carbs)),
                    remainingFat: goals.targetFatGrams - Int(round(totals.fat)),
                    defaultMealType: defaultMealForCurrentHour()
                )
            }
            .sheet(item: $mealToSaveAsTemplate) { meal in
                let logged = nutritionStore.entries(for: meal)
                SavedMealEditorView(
                    prefilledName: "Mein \(meal.displayName)",
                    prefilledIngredients: logged.map { ($0.food, $0.entry.grams) }
                ) { savedMeal, items in
                    nutritionStore.saveSavedMeal(savedMeal, items: items)
                }
            }
            .alert("Neues Supplement", isPresented: $isShowingAddSupplementAlert) {
                TextField("Name (z. B. Zink)", text: $newSupplementName)
                TextField("Dosierung (optional, z. B. 25 mg)", text: $newSupplementDosage)
                Button("Hinzufügen") {
                    let trimmed = newSupplementName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let dosage = newSupplementDosage.trimmingCharacters(in: .whitespacesAndNewlines)
                    let supp = Supplement(
                        name: trimmed,
                        dosage: dosage.isEmpty ? nil : dosage,
                        sortOrder: wellnessStore.supplements.count
                    )
                    wellnessStore.saveSupplement(supp)
                    newSupplementName = ""
                    newSupplementDosage = ""
                }
                Button("Abbrechen", role: .cancel) {
                    newSupplementName = ""
                    newSupplementDosage = ""
                }
            }
            .alert(
                "Hinweis",
                isPresented: Binding(
                    get: { copyFeedbackMessage != nil },
                    set: { if !$0 { copyFeedbackMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copyFeedbackMessage ?? "")
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
        let calorieProgress = effectiveTargetCalories > 0
            ? min(1.0, totals.calories / Double(effectiveTargetCalories))
            : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(round(totals.calories))) / \(effectiveTargetCalories) kcal")
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

                if goals.useTrainingDayTargets {
                    Button {
                        nutritionStore.toggleTrainingDayOverride(
                            for: nutritionStore.selectedDate,
                            currentValue: isTrainingDay
                        )
                    } label: {
                        Label(
                            isTrainingDay ? "Trainingstag" : "Ruhetag",
                            systemImage: isTrainingDay ? "flame.fill" : "moon.fill"
                        )
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background((isTrainingDay ? Color.green : Color.secondary).opacity(0.16))
                        .foregroundColor(isTrainingDay ? .green : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
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
                    target: Double(effectiveTargetCarbs),
                    color: .orange
                )
                MacroProgressColumn(
                    title: "Fett",
                    current: totals.fat,
                    target: Double(goals.targetFatGrams),
                    color: .purple
                )
            }

            HStack(spacing: 10) {
                Button {
                    openAIScannerCamera = false
                    isShowingAIScanner = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder")
                        Text("KI-Foto-Scan")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button {
                        isShowingRecipeChef = true
                    } label: {
                        Label("KI-Makro-Koch (Rezept-Idee)", systemImage: "flame.fill")
                    }

                    Button {
                        isShowingMacroHelper = true
                    } label: {
                        Label("Was fehlt? (Makro-Helfer)", systemImage: "wand.and.stars")
                    }

                    Button {
                        isShowingDayTemplates = true
                    } label: {
                        Label("Tages-Vorlagen", systemImage: "doc.on.doc")
                    }

                    Button {
                        isShowingAdaptiveTDEE = true
                    } label: {
                        Label("Adaptiver TDEE-Rechner", systemImage: "waveform.path.ecg")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Tools & KI")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var waterAndSupplementsCard: some View {
        let waterProgress = wellnessStore.dailyWaterGoalMl > 0
            ? min(1.0, Double(wellnessStore.waterMl) / Double(wellnessStore.dailyWaterGoalMl))
            : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Wasser", systemImage: "drop.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan)
                Spacer()
                Text("\(wellnessStore.waterMl) / \(wellnessStore.dailyWaterGoalMl) ml")
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            ProgressView(value: waterProgress)
                .progressViewStyle(.linear)
                .tint(.cyan)

            HStack(spacing: 8) {
                Button("-250 ml") {
                    wellnessStore.adjustWater(deltaMl: -250)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("+250 ml") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    wellnessStore.adjustWater(deltaMl: 250)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .controlSize(.small)

                Button("+500 ml") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    wellnessStore.adjustWater(deltaMl: 500)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)

                Spacer()
            }

            Divider()

            HStack {
                Label("Supplements", systemImage: "pills.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    isShowingAddSupplementAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.subheadline)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(wellnessStore.supplements) { supp in
                        let isTaken = wellnessStore.takenSupplementIds.contains(supp.id)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            wellnessStore.toggleSupplement(supp)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                Text(supp.dosage.map { "\(supp.name) (\($0))" } ?? supp.name)
                                    .font(.caption)
                                    .fontWeight(isTaken ? .semibold : .regular)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isTaken ? Color.green.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                            .foregroundColor(isTaken ? .green : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                wellnessStore.deleteSupplement(id: supp.id)
                            } label: {
                                Label("Supplement entfernen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var weeklyTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showWeeklyTrendExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("7-Tage-Trend", systemImage: "chart.bar.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    if nutritionStore.averageWeeklyCalories > 0 {
                        Text("Ø \(nutritionStore.averageWeeklyCalories) kcal · \(nutritionStore.averageWeeklyProtein)g P")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: showWeeklyTrendExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showWeeklyTrendExpanded {
                Divider()
                Chart {
                    RuleMark(y: .value("Ziel", goals.targetCalories))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.6))

                    ForEach(nutritionStore.weeklyPoints) { point in
                        BarMark(
                            x: .value("Tag", point.date, unit: .day),
                            y: .value("kcal", point.calories)
                        )
                        .foregroundStyle(point.calories > Double(goals.targetCalories) ? Color.orange : Color.accentColor)
                        .cornerRadius(5)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 150)
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

                    if items.isEmpty {
                        Button {
                            let count = nutritionStore.copyMealFromYesterday(mealType: meal)
                            if count == 0 {
                                copyFeedbackMessage = "Für \(meal.displayName) gab es am Vortag keine Einträge."
                            }
                        } label: {
                            Label("Von gestern kopieren", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
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

                        Divider()
                        Button {
                            mealToSaveAsTemplate = meal
                        } label: {
                            Label("Als Vorlage-Mahlzeit speichern", systemImage: "bookmark.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
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
