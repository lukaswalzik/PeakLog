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

    @State private var mode: InputMode = .photo
    @State private var mealType: MealType
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isShowingCamera: Bool = false
    @State private var photoHint: String = ""
    @State private var mealTextInput: String = ""

    @State private var isAnalyzing: Bool = false
    @State private var estimatedItems: [AIEstimatedFood] = []
    @State private var errorMessage: String? = nil
    @State private var isShowingSettings: Bool = false

    init(initialMealType: MealType) {
        _mealType = State(initialValue: initialMealType)
    }

    private var selectedTotalCalories: Double {
        estimatedItems.filter { $0.isSelected }.reduce(0) { $0 + $1.totalCalories }
    }

    private var selectedTotalProtein: Double {
        estimatedItems.filter { $0.isSelected }.reduce(0) { $0 + $1.totalProtein }
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
            .navigationTitle("Mistral KI-Scanner")
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
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { image in
                    selectedImage = image
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
                            selectedImage = image
                        }
                    }
                }
            }
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
                Text("Hinterlege deinen Key aus console.mistral.ai, um Fotos & Texte zu analysieren.")
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                    Text("Teller oder Nährwerttabelle fotografieren")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Mistral Vision erkennt Zutaten, schätzt Gramm & Makros.")
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
                .buttonStyle(.bordered)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Foto wählen", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            TextField("Optionaler Hinweis (z. B. Mensa Hähnchen-Curry)", text: $photoHint)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

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
                    Text(isAnalyzing ? "Mistral analysiert Foto..." : "Foto mit KI analysieren")
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
                Text("\(Int(round(selectedTotalCalories))) kcal · \(Int(round(selectedTotalProtein)))g E")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            ForEach($estimatedItems) { $item in
                HStack(spacing: 10) {
                    Button {
                        item.isSelected.toggle()
                    } label: {
                        Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(item.isSelected ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(Int(round(item.grams))) g · \(Int(round(item.totalCalories))) kcal · \(Int(round(item.totalProtein)))g E · \(Int(round(item.totalCarbs)))g KH · \(Int(round(item.totalFat)))g F")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Stepper("", value: $item.grams, in: 10...1500, step: 10)
                        .labelsHidden()
                }
                .padding(.vertical, 4)

                if item.id != estimatedItems.last?.id {
                    Divider()
                }
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
            .disabled(!estimatedItems.contains(where: { $0.isSelected }))
        }
        .strongCard()
    }

    private func analyzePhoto() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let items = try await mistral.analyzeMealPhoto(image, hint: photoHint)
                await MainActor.run {
                    estimatedItems = items
                    isAnalyzing = false
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
                    estimatedItems = items
                    isAnalyzing = false
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
        let toLog = estimatedItems.filter { $0.isSelected }
        for item in toLog {
            nutritionStore.logFood(item.toFoodItem(), mealType: mealType, grams: item.grams)
        }
        dismiss()
    }
}
