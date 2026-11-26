import SwiftUI

struct ReplaceExerciseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let currentExercise: Exercise
    let onReplace: (Exercise) -> Void

    @State private var searchText: String = ""

    private var filteredExercises: [Exercise] {
        let base = exerciseStore.exercises.filter { !$0.isArchived && $0.id != currentExercise.id }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.muscleGroup.displayName.localizedCaseInsensitiveContains(query) ||
            $0.equipment.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var sameMuscleAlternatives: [Exercise] {
        filteredExercises.filter { $0.muscleGroup == currentExercise.muscleGroup }
    }

    private var otherExercises: [Exercise] {
        filteredExercises.filter { $0.muscleGroup != currentExercise.muscleGroup }
    }

    var body: some View {
        NavigationStack {
            List {
                if !sameMuscleAlternatives.isEmpty {
                    Section("Passende Alternativen (\(currentExercise.muscleGroup.displayName))") {
                        ForEach(sameMuscleAlternatives) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }

                if !otherExercises.isEmpty {
                    Section("Weitere Übungen") {
                        ForEach(otherExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Alternative suchen...")
            .navigationTitle("Übung ersetzen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            onReplace(exercise)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ExerciseThumbnailView(exercise: exercise, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
        }
    }
}
