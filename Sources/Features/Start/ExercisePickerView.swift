import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let onSelect: ([Exercise]) -> Void

    @State private var searchText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var selectedExerciseIds: Set<String> = []
    @State private var selectionOrder: [String] = []

    private var filteredExercises: [Exercise] {
        exerciseStore.exercises.filter { exercise in
            let matchesGroup = selectedMuscleGroup == nil || exercise.muscleGroup == selectedMuscleGroup
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = trimmed.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(trimmed)
                || exercise.muscleGroup.displayName.localizedCaseInsensitiveContains(trimmed)
                || exercise.equipment.displayName.localizedCaseInsensitiveContains(trimmed)
            return matchesGroup && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                muscleGroupFilterBar

                if filteredExercises.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "Keine Übungen gefunden",
                        message: "Passe deine Suche oder den Muskelgruppen-Filter an."
                    )
                } else {
                    List {
                        ForEach(filteredExercises) { exercise in
                            Button {
                                toggleSelection(exercise.id)
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseThumbnailView(exercise: exercise, size: 42)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(exercise.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text("\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedExerciseIds.contains(exercise.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .font(.title3)
                                    }
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Übungen wählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Übung suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) {
                        let exercisesById = Dictionary(
                            uniqueKeysWithValues: exerciseStore.exercises.map { ($0.id, $0) }
                        )
                        let picked = selectionOrder.compactMap { exercisesById[$0] }
                        onSelect(picked)
                        dismiss()
                    }
                    .disabled(selectedExerciseIds.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var addButtonTitle: String {
        selectedExerciseIds.isEmpty ? "Hinzufügen" : "Hinzufügen (\(selectedExerciseIds.count))"
    }

    private func toggleSelection(_ id: String) {
        if selectedExerciseIds.contains(id) {
            selectedExerciseIds.remove(id)
            selectionOrder.removeAll { $0 == id }
        } else {
            selectedExerciseIds.insert(id)
            selectionOrder.append(id)
        }
    }

    private var muscleGroupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PickerFilterChip(
                    title: "Alle",
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases) { group in
                    PickerFilterChip(
                        title: group.displayName,
                        isSelected: selectedMuscleGroup == group
                    ) {
                        selectedMuscleGroup = (selectedMuscleGroup == group) ? nil : group
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct PickerFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
