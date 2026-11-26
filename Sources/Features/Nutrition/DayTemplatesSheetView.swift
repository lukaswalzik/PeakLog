import SwiftUI

struct DayTemplatesSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore

    @State private var newTemplateName: String = ""
    @State private var isShowingSaveAlert: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section(
                    header: Text("Aktuellen Tag sichern"),
                    footer: Text("Speichert alle heute eingetragenen Mahlzeiten (Frühstück, Mittag, Abendessen, Snacks) als wiederverwendbare Tages-Vorlage.")
                ) {
                    Button {
                        newTemplateName = "Standard-Tag"
                        isShowingSaveAlert = true
                    } label: {
                        Label("Aktuellen Tag als Vorlage speichern (\(nutritionStore.dayEntries.count) Einträge)", systemImage: "square.and.arrow.down")
                            .fontWeight(.semibold)
                    }
                    .disabled(nutritionStore.dayEntries.isEmpty)
                }

                Section("Gespeicherte Tages-Vorlagen") {
                    if nutritionStore.dayTemplates.isEmpty {
                        Text("Noch keine Tages-Vorlagen gespeichert. Logge einen typischen Tag und speichere ihn oben ab.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(nutritionStore.dayTemplates) { tpl in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tpl.template.name)
                                        .font(.headline)
                                    Text("\(tpl.items.count) Einträge · \(Int(round(tpl.totalCalories))) kcal · \(Int(round(tpl.totalProtein)))g Eiweiß")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Laden") {
                                    nutritionStore.applyDayTemplate(tpl)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button(role: .destructive) {
                                    nutritionStore.deleteDayTemplate(id: tpl.id)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tages-Vorlagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Tages-Vorlage speichern", isPresented: $isShowingSaveAlert) {
                TextField("z. B. Trainingstag oder Uni-Tag", text: $newTemplateName)
                Button("Speichern") {
                    nutritionStore.saveCurrentDayAsTemplate(name: newTemplateName)
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}
