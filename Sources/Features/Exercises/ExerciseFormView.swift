import SwiftUI

struct ExerciseFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingExercise: Exercise?
    let onSave: (Exercise) -> Void

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var equipment: Equipment
    @State private var defaultRestSeconds: Int
    @State private var notes: String

    init(existingExercise: Exercise? = nil, onSave: @escaping (Exercise) -> Void) {
        self.existingExercise = existingExercise
        self.onSave = onSave
        _name = State(initialValue: existingExercise?.name ?? "")
        _muscleGroup = State(initialValue: existingExercise?.muscleGroup ?? .chest)
        _equipment = State(initialValue: existingExercise?.equipment ?? .barbell)
        _defaultRestSeconds = State(initialValue: existingExercise?.defaultRestSeconds ?? 90)
        _notes = State(initialValue: existingExercise?.notes ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Allgemein")) {
                    TextField("Übungsname (z. B. Schrägbankdrücken)", text: $name)

                    Picker("Muskelgruppe", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }

                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }

                Section(header: Text("Pausentimer")) {
                    Stepper(
                        value: $defaultRestSeconds,
                        in: 15...300,
                        step: 15
                    ) {
                        HStack {
                            Text("Standard-Pause")
                            Spacer()
                            Text(Formatters.restDuration(defaultRestSeconds))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. Bank auf Stufe 3, Griffbreite schulterbreit", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingExercise == nil ? "Neue Übung" : "Übung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
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

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let exercise = Exercise(
            id: existingExercise?.id ?? UUID().uuidString,
            name: trimmedName,
            muscleGroup: muscleGroup,
            equipment: equipment,
            defaultRestSeconds: defaultRestSeconds,
            isCustom: existingExercise?.isCustom ?? true,
            isArchived: existingExercise?.isArchived ?? false,
            notes: normalizedNotes,
            createdAt: existingExercise?.createdAt ?? Date()
        )
        onSave(exercise)
        dismiss()
    }
}

struct ExerciseFormView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseFormView { _ in }
    }
}
