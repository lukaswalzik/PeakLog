import SwiftUI

struct ExerciseListView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @State private var searchText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var isShowingCreateSheet: Bool = false
    @State private var editingExercise: Exercise? = nil

    private var filteredExercises: [Exercise] {
        exerciseStore.exercises.filter { exercise in
            let matchesGroup = selectedMuscleGroup == nil || exercise.muscleGroup == selectedMuscleGroup
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = trimmedSearch.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(trimmedSearch)
                || exercise.muscleGroup.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || exercise.equipment.displayName.localizedCaseInsensitiveContains(trimmedSearch)
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
                        message: "Ändere den Filter oder lege eine eigene Übung an.",
                        actionTitle: "Neue Übung anlegen"
                    ) {
                        isShowingCreateSheet = true
                    }
                } else {
                    List {
                        ForEach(filteredExercises) { exercise in
                            Button {
                                editingExercise = exercise
                            } label: {
                                ExerciseRowView(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    exerciseStore.archiveOrDelete(exercise)
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Übungen")
            .searchable(text: $searchText, prompt: "Übung, Muskel oder Gerät suchen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Übung")
                }
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                ExerciseFormView { newExercise in
                    exerciseStore.save(newExercise)
                }
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseFormView(existingExercise: exercise) { updatedExercise in
                    exerciseStore.save(updatedExercise)
                }
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: { exerciseStore.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { exerciseStore.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exerciseStore.errorMessage ?? "")
            }
        }
    }

    private var muscleGroupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "Alle (\(exerciseStore.exercises.count))",
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(
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

private struct FilterChip: View {
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

private struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if exercise.isCustom {
                        Text("Eigene")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text("\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(Formatters.restDuration(exercise.defaultRestSeconds))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ExerciseListView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseListView()
            .environmentObject(ExerciseStore(database: .makeInMemory()))
    }
}
