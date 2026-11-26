import PhotosUI
import SwiftUI
import UIKit

struct CustomFoodFormView: View {
    @Environment(\.dismiss) private var dismiss

    let prefilledBarcode: String?
    let onSave: (FoodItem) -> Void

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var barcode: String
    @State private var servingGramsText: String = "100"

    @State private var kcalText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""

    @State private var fiberText: String = ""
    @State private var sugarText: String = ""
    @State private var saltText: String = ""
    @State private var vitaminCText: String = ""
    @State private var calciumText: String = ""
    @State private var ironText: String = ""

    @State private var isShowingCamera: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isScanningLabel: Bool = false
    @State private var scanStatusMessage: String? = nil

    init(prefilledBarcode: String? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.prefilledBarcode = prefilledBarcode
        self.onSave = onSave
        _barcode = State(initialValue: prefilledBarcode ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Formatters.parseWeight(kcalText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if MistralAIService.shared.isConfigured {
                    Section(
                        header: Text("KI-Nährwerttabellen-Scanner"),
                        footer: Text("Fotografiere die Nährwerttabelle auf der Verpackung – Mistral füllt alle Werte automatisch aus.")
                    ) {
                        HStack(spacing: 12) {
                            Button {
                                isShowingCamera = true
                            } label: {
                                Label("Kamera", systemImage: "camera.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isScanningLabel)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("Foto wählen", systemImage: "photo")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isScanningLabel)

                            if isScanningLabel {
                                Spacer()
                                ProgressView()
                            }
                        }

                        if let msg = scanStatusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Lebensmittel")) {
                    TextField("Name (z. B. Protein Pudding Schoko)", text: $name)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Barcode (optional)", text: $barcode)
                        .keyboardType(.numberPad)
                    HStack {
                        Text("Standard-Portion")
                        Spacer()
                        TextField("100", text: $servingGramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Makronährstoffe pro 100 g")) {
                    nutrientField("Kalorien", text: $kcalText, unit: "kcal")
                    nutrientField("Eiweiß", text: $proteinText, unit: "g")
                    nutrientField("Kohlenhydrate", text: $carbsText, unit: "g")
                    nutrientField("Fett", text: $fatText, unit: "g")
                }

                Section(header: Text("Mikronährstoffe pro 100 g (optional)")) {
                    nutrientField("Ballaststoffe", text: $fiberText, unit: "g")
                    nutrientField("Zucker", text: $sugarText, unit: "g")
                    nutrientField("Salz", text: $saltText, unit: "g")
                    nutrientField("Vitamin C", text: $vitaminCText, unit: "mg")
                    nutrientField("Kalzium", text: $calciumText, unit: "mg")
                    nutrientField("Eisen", text: $ironText, unit: "mg")
                }
            }
            .navigationTitle("Eigenes Lebensmittel")
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
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { image in
                    scanLabelImage(image)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            scanLabelImage(image)
                        }
                    }
                }
            }
        }
    }

    private func scanLabelImage(_ image: UIImage) {
        isScanningLabel = true
        scanStatusMessage = "Mistral liest Nährwerttabelle..."
        Task {
            do {
                let result = try await MistralAIService.shared.scanNutritionLabel(image)
                await MainActor.run {
                    if let n = result.name, !n.isEmpty, name.isEmpty { name = n }
                    if let b = result.brand, !b.isEmpty, brand.isEmpty { brand = b }
                    if let s = result.servingSizeGrams, s > 0 { servingGramsText = Formatters.weight(s) }
                    if let v = result.caloriesPer100g { kcalText = Formatters.weight(v) }
                    if let v = result.proteinPer100g { proteinText = Formatters.weight(v) }
                    if let v = result.carbsPer100g { carbsText = Formatters.weight(v) }
                    if let v = result.fatPer100g { fatText = Formatters.weight(v) }
                    if let v = result.fiberPer100g { fiberText = Formatters.weight(v) }
                    if let v = result.sugarPer100g { sugarText = Formatters.weight(v) }
                    if let v = result.saltPer100g { saltText = Formatters.weight(v) }
                    scanStatusMessage = "Werte erkannt! Bitte kurz prüfen & speichern."
                    isScanningLabel = false
                }
            } catch {
                await MainActor.run {
                    scanStatusMessage = error.localizedDescription
                    isScanningLabel = false
                }
            }
        }
    }

    private func nutrientField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = FoodItem(
            name: trimmedName,
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            barcode: trimmedBarcode.isEmpty ? nil : trimmedBarcode,
            servingSizeGrams: max(1, Formatters.parseWeight(servingGramsText) ?? 100),
            caloriesPer100g: max(0, Formatters.parseWeight(kcalText) ?? 0),
            proteinPer100g: max(0, Formatters.parseWeight(proteinText) ?? 0),
            carbsPer100g: max(0, Formatters.parseWeight(carbsText) ?? 0),
            fatPer100g: max(0, Formatters.parseWeight(fatText) ?? 0),
            fiberPer100g: max(0, Formatters.parseWeight(fiberText) ?? 0),
            sugarPer100g: max(0, Formatters.parseWeight(sugarText) ?? 0),
            saltPer100g: max(0, Formatters.parseWeight(saltText) ?? 0),
            vitaminCMgPer100g: max(0, Formatters.parseWeight(vitaminCText) ?? 0),
            calciumMgPer100g: max(0, Formatters.parseWeight(calciumText) ?? 0),
            ironMgPer100g: max(0, Formatters.parseWeight(ironText) ?? 0),
            isCustom: true
        )
        onSave(item)
        dismiss()
    }
}
