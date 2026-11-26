import SwiftUI

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
