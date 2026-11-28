import PhotosUI
import SwiftUI
import UIKit

struct AIMealScannerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore
    @ObservedObject private var mistral = MistralAIService.shared

    enum InputMode: String, CaseIterable, Identifiable {
        case photo = "Foto-Scanner"
        case text = "Text / Diktat"

        var id: String { rawValue }
    }

    let autoOpenCamera: Bool

    @State private var mode: InputMode = .photo
    @State private var mealType: MealType
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isShowingCamera: Bool = false
    @State private var hasAutoOpenedCamera: Bool = false
    @State private var photoHint: String = ""
    @State private var mealTextInput: String = ""

    @AppStorage("strongtracker.ai.autoAnalyzePhoto") private var autoAnalyzeOnCapture: Bool = true

    @State private var isAnalyzing: Bool = false
    @State private var estimatedItems: [AIEstimatedFood] = []
    @State private var baseGramsById: [String: Double] = [:]
    @State private var portionMultiplier: Double = 1.0
    @State private var expandedItemId: String? = nil

    @State private var saveAsTemplate: Bool = false
    @State private var templateName: String = ""

    @State private var errorMessage: String? = nil
    @State private var isShowingSettings: Bool = false

    private let portionPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    init(initialMealType: MealType, autoOpenCamera: Bool = false) {
        self.autoOpenCamera = autoOpenCamera
        _mealType = State(initialValue: initialMealType)
    }

    private var selectedItems: [AIEstimatedFood] {
        estimatedItems.filter { $0.isSelected }
    }

    private var selectedTotalCalories: Double {
        selectedItems.reduce(0) { $0 + $1.totalCalories }
    }

    private var selectedTotalProtein: Double {
        selectedItems.reduce(0) { $0 + $1.totalProtein }
    }

    private var selectedTotalCarbs: Double {
        selectedItems.reduce(0) { $0 + $1.totalCarbs }
    }

    private var selectedTotalFat: Double {
        selectedItems.reduce(0) { $0 + $1.totalFat }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !mistral.isConfigured {
                        missingKeyBanner
                    }

                    Picker("Modus", selection: $mode) {
                        ForEach(InputMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Mahlzeit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Mahlzeit", selection: $mealType) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.displayName).tag(meal)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .strongCard(padding: 12)

                    if mode == .photo {
                        photoInputCard
                    } else {
                        textInputCard
                    }

                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if !estimatedItems.isEmpty {
                        resultsCard
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("KI-Foto & Text Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                if autoOpenCamera && !hasAutoOpenedCamera {
                    hasAutoOpenedCamera = true
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isShowingCamera = true
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { image in
                    handleCapturedImage(image)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    MistralSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") { isShowingSettings = false }
                            }
                        }
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            handleCapturedImage(image)
                        }
                    }
                }
            }
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        selectedImage = image
        errorMessage = nil
        if autoAnalyzeOnCapture && mistral.isConfigured && !isAnalyzing {
            analyzePhoto()
        }
    }

    private var missingKeyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mistral API-Key fehlt")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Hinterlege deinen Key aus console.mistral.ai, um Mahlzeiten per Foto & Text zu analysieren.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Einrichten") {
                isShowingSettings = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .strongCard(padding: 12)
    }

    private var photoInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            Group {
                                if isAnalyzing {
                                    ZStack {
                                        Color.black.opacity(0.45)
                                        VStack(spacing: 8) {
                                            ProgressView()
                                                .tint(.white)
                                                .scaleEffect(1.2)
                                            Text("Mistral Vision erkennt Zutaten & Makros...")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        }
                                        .padding(14)
                                        .background(Color.black.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        )

                    if !isAnalyzing {
                        Button {
                            isShowingCamera = true
                        } label: {
                            Label("Neu", systemImage: "camera.rotate")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.65))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .padding(10)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 38))
                        .foregroundColor(.accentColor)
                    Text("Teller oder Nährwerttabelle fotografieren")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Mistral Vision erkennt Zutaten, schätzt Gramm & Makros direkt aus dem Foto.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Kamera", systemImage: "camera.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Mediathek", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            TextField("Optionaler Hinweis (z. B. 200g Hähnchen, wenig Öl)", text: $photoHint)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            Toggle(isOn: $autoAnalyzeOnCapture) {
                Text("Foto direkt nach Aufnahme analysieren")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .tint(.accentColor)

            Button {
                analyzePhoto()
            } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Mistral analysiert Foto..." : (estimatedItems.isEmpty ? "Foto mit KI analysieren" : "Foto erneut analysieren"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedImage == nil || isAnalyzing || !mistral.isConfigured)
        }
        .strongCard()
    }

    private var textInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beschreibe deine Mahlzeit (oder nutze das iOS-Mikrofon auf der Tastatur)")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $mealTextInput)
                .frame(minHeight: 110)
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    Group {
                        if mealTextInput.isEmpty {
                            Text("z. B. 250g Magerquark, 1 Banane, 40g Haferflocken und 1 Scoop Whey")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            Button {
                analyzeText()
            } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Mistral analysiert..." : "Mahlzeit erkennen")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mealTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing || !mistral.isConfigured)
        }
        .strongCard()
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Erkannte Lebensmittel")
                    .font(.headline)
                Spacer()
                Text("\(selectedItems.count)/\(estimatedItems.count) aktiv")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Full macro summary strip
            HStack(spacing: 8) {
                macroSummaryChip(title: "Kalorien", value: "\(Int(round(selectedTotalCalories)))", unit: "kcal", color: .accentColor)
                macroSummaryChip(title: "Eiweiß", value: "\(Int(round(selectedTotalProtein)))", unit: "g", color: .blue)
                macroSummaryChip(title: "Carbs", value: "\(Int(round(selectedTotalCarbs)))", unit: "g", color: .orange)
                macroSummaryChip(title: "Fett", value: "\(Int(round(selectedTotalFat)))", unit: "g", color: .purple)
            }

            // Whole-plate portion scaler
            VStack(alignment: .leading, spacing: 6) {
                Text("Portionsgröße anpassen")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(portionPresets, id: \.self) { mult in
                        let isSelected = abs(portionMultiplier - mult) < 0.01
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            applyPortionMultiplier(mult)
                        } label: {
                            Text(formattedMultiplier(mult))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .foregroundColor(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            ForEach($estimatedItems) { $item in
                let isExpanded = expandedItemId == item.id
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            item.isSelected.toggle()
                        } label: {
                            Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(item.isSelected ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedItemId = isExpanded ? nil : item.id
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Image(systemName: isExpanded ? "chevron.up" : "pencil")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(Int(round(item.grams))) g · \(Int(round(item.totalCalories))) kcal · \(Int(round(item.totalProtein)))g E · \(Int(round(item.totalCarbs)))g KH · \(Int(round(item.totalFat)))g F")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                if let note = item.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Stepper("", value: $item.grams, in: 5...2000, step: 10)
                            .labelsHidden()
                    }

                    if isExpanded {
                        inlineEditor(for: $item)
                    }
                }
                .padding(.vertical, 4)

                if item.id != estimatedItems.last?.id {
                    Divider()
                }
            }

            Divider()

            Toggle(isOn: $saveAsTemplate) {
                Label("Auch als Mahlzeit-Vorlage speichern", systemImage: "bookmark")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .tint(.accentColor)

            if saveAsTemplate {
                TextField("Name der Vorlage (z. B. Hähnchen-Reis-Bowl)", text: $templateName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            Button {
                logSelectedItems()
            } label: {
                Label("Ausgewählte zu \(mealType.displayName) loggen", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedItems.isEmpty)
        }
        .strongCard()
    }

    private func macroSummaryChip(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func inlineEditor(for item: Binding<AIEstimatedFood>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Bezeichnung", text: item.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack(spacing: 8) {
                numericField(title: "Gramm", value: item.grams)
                numericField(title: "kcal/100g", value: item.caloriesPer100g)
            }

            HStack(spacing: 8) {
                numericField(title: "E / 100g", value: item.proteinPer100g)
                numericField(title: "KH / 100g", value: item.carbsPer100g)
                numericField(title: "F / 100g", value: item.fatPer100g)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func numericField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedMultiplier(_ mult: Double) -> String {
        let str = String(format: "%g", mult).replacingOccurrences(of: ".", with: ",")
        return "\(str)×"
    }

    private func applyPortionMultiplier(_ mult: Double) {
        portionMultiplier = mult
        for idx in estimatedItems.indices {
            let id = estimatedItems[idx].id
            let base = baseGramsById[id] ?? estimatedItems[idx].grams
            baseGramsById[id] = base
            estimatedItems[idx].grams = max(5, (base * mult / 5.0).rounded() * 5.0)
        }
    }

    private func storeFreshEstimates(_ items: [AIEstimatedFood]) {
        estimatedItems = items
        portionMultiplier = 1.0
        baseGramsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.grams) })
        expandedItemId = nil
        if templateName.isEmpty, let first = items.first {
            templateName = items.count == 1 ? first.name : "\(first.name) & Beilagen"
        }
    }

    private func analyzePhoto() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let items = try await mistral.analyzeMealPhoto(image, hint: photoHint)
                await MainActor.run {
                    storeFreshEstimates(items)
                    isAnalyzing = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func analyzeText() {
        let query = mealTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let items = try await mistral.analyzeMealText(query)
                await MainActor.run {
                    storeFreshEstimates(items)
                    isAnalyzing = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func logSelectedItems() {
        let toLog = selectedItems
        var savedItemsForTemplate: [SavedMealItem] = []
        let mealId = UUID().uuidString

        for (index, item) in toLog.enumerated() {
            let foodItem = item.toFoodItem()
            nutritionStore.logFood(foodItem, mealType: mealType, grams: item.grams)
            if saveAsTemplate {
                savedItemsForTemplate.append(
                    SavedMealItem(
                        mealId: mealId,
                        foodItemId: foodItem.id,
                        grams: max(1, item.grams),
                        sortOrder: index
                    )
                )
            }
        }

        if saveAsTemplate && !savedItemsForTemplate.isEmpty {
            let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmed.isEmpty ? "KI-Scan \(mealType.displayName)" : trimmed
            let savedMeal = SavedMeal(id: mealId, name: finalName, notes: "Per KI-Foto-Scanner erstellt")
            nutritionStore.saveSavedMeal(savedMeal, items: savedItemsForTemplate)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
