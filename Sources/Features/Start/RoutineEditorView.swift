import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    struct DraftExercise: Identifiable, Equatable {
        let id: String
        let exercise: Exercise
        var targetSets: Int
        var targetReps: Int
        var restSeconds: Int

        init(
            id: String = UUID().uuidString,
            exercise: Exercise,
            targetSets: Int = 3,
            targetReps: Int = 8,
            restSeconds: Int? = nil
        ) {
            self.id = id
            self.exercise = exercise
            self.targetSets = targetSets
            self.targetReps = targetReps
            self.restSeconds = restSeconds ?? exercise.defaultRestSeconds
        }
    }

    let existingRoutine: RoutineWithExercises?
    let nextSortOrder: Int
    let onSave: (Routine, [RoutineExercise]) -> Void

    @State private var name: String
    @State private var notes: String
    @State private var items: [DraftExercise]
    @State private var isShowingExercisePicker: Bool = false

    init(
        existingRoutine: RoutineWithExercises? = nil,
        nextSortOrder: Int = 0,
        onSave: @escaping (Routine, [RoutineExercise]) -> Void
    ) {
        self.existingRoutine = existingRoutine
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave

        _name = State(initialValue: existingRoutine?.routine.name ?? "")
        _notes = State(initialValue: existingRoutine?.routine.notes ?? "")
        _items = State(initialValue: existingRoutine?.exercises.map { detail in
            DraftExercise(
                id: detail.routineExercise.id,
                exercise: detail.exercise,
                targetSets: detail.routineExercise.targetSets,
                targetReps: detail.routineExercise.targetReps ?? 0,
                restSeconds: detail.effectiveRestSeconds
            )
        } ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Allgemein")) {
                    TextField("Routinenname (z. B. Push A, Ganzkörper)", text: $name)
                    TextField("Notizen (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(
                    header: HStack {
                        Text("Übungen (\(items.count))")
                        Spacer()
                        if items.count > 1 {
                            EditButton()
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                ) {
                    if items.isEmpty {
                        Text("Noch keine Übungen hinzugefügt.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach($items) { $item in
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.exercise.name)
                                        .font(.headline)
                                    Text("\(item.exercise.muscleGroup.displayName) · \(item.exercise.equipment.displayName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Stepper(value: $item.targetSets, in: 1...12) {
                                    HStack {
                                        Text("Sätze")
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(item.targetSets)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Stepper(value: $item.targetReps, in: 0...30) {
                                    HStack {
                                        Text("Ziel-Wdh.")
                                            .font(.subheadline)
                                        Spacer()
                                        Text(item.targetReps == 0 ? "Offen" : "\(item.targetReps)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Stepper(value: $item.restSeconds, in: 15...300, step: 15) {
                                    HStack {
                                        Text("Pause")
                                            .font(.subheadline)
                                        Spacer()
                                        Text(Formatters.restDuration(item.restSeconds))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove(perform: moveItems)
                        .onDelete(perform: deleteItems)
                    }

                    Button {
                        isShowingExercisePicker = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(existingRoutine == nil ? "Neue Routine" : "Routine bearbeiten")
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
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerView { pickedExercises in
                    let newDrafts = pickedExercises.map { DraftExercise(exercise: $0) }
                    items.append(contentsOf: newDrafts)
                }
            }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let routineId = existingRoutine?.routine.id ?? UUID().uuidString
        let routine = Routine(
            id: routineId,
            name: trimmedName,
            notes: normalizedNotes,
            sortOrder: existingRoutine?.routine.sortOrder ?? nextSortOrder,
            createdAt: existingRoutine?.routine.createdAt ?? Date(),
            updatedAt: Date()
        )

        let routineExercises = items.enumerated().map { index, item in
            RoutineExercise(
                id: item.id,
                routineId: routineId,
                exerciseId: item.exercise.id,
                sortOrder: index,
                targetSets: item.targetSets,
                targetReps: item.targetReps == 0 ? nil : item.targetReps,
                restSeconds: item.restSeconds,
                notes: nil
            )
        }

        onSave(routine, routineExercises)
        dismiss()
    }
}

struct RoutineEditorView_Previews: PreviewProvider {
    static var previews: some View {
        RoutineEditorView { _, _ in }
            .environmentObject(ExerciseStore(database: .makeInMemory()))
    }
}
