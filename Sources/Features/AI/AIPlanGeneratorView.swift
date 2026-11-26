import SwiftUI

struct AIPlanGeneratorView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var routineStore: RoutineStore
    @ObservedObject private var mistral = MistralAIService.shared

    @State private var daysPerWeek: Int = 4
    @State private var durationMinutes: Int = 60
    @State private var focusText: String = "Hypertrophie, ausgewogener Ober-/Unterkörper oder Push/Pull/Beine"

    @State private var isGenerating: Bool = false
    @State private var generatedRoutines: [MistralAIService.AIGeneratedRoutine] = []
    @State private var errorMessage: String? = nil
    @State private var savedConfirmation: Bool = false

    private let focusPresets = [
        "Ausgewogene Hypertrophie",
        "Fokus Oberkörper, Schultern & Rücken",
        "Push / Pull / Beine",
        "Ganzkörper (zeiteffizient)"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !mistral.isConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mistral API-Key benötigt", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Hinterlege zuerst deinen Key unter Profil → Mistral KI-Einstellungen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Deine Vorgaben")
                        .font(.headline)

                    Stepper(value: $daysPerWeek, in: 2...6) {
                        HStack {
                            Text("Trainingstage / Woche")
                            Spacer()
                            Text("\(daysPerWeek) Tage")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }

                    Stepper(value: $durationMinutes, in: 30...120, step: 15) {
                        HStack {
                            Text("Dauer pro Einheit")
                            Spacer()
                            Text("ca. \(durationMinutes) Min.")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(focusPresets, id: \.self) { preset in
                                Button(preset) {
                                    focusText = preset
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    TextField("Fokus / Sonderwünsche (z. B. kein Kreuzheben)", text: $focusText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button {
                        generatePlan()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Mistral erstellt Trainingsplan..." : "Plan mit KI erstellen")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || !mistral.isConfigured)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .strongCard()

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !generatedRoutines.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Vorgeschlagener Plan (\(generatedRoutines.count) Routinen)")
                                .font(.headline)
                            Spacer()
                        }

                        ForEach(generatedRoutines) { plan in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(plan.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                                if let notes = plan.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                ForEach(plan.exercises) { ex in
                                    HStack {
                                        Text("• \(ex.exerciseName)")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(ex.targetSets)×\(ex.targetReps)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            saveAllAsRoutines()
                        } label: {
                            Label(
                                savedConfirmation ? "Routinen gespeichert!" : "Alle als Routinen speichern",
                                systemImage: savedConfirmation ? "checkmark.circle.fill" : "square.and.arrow.down.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(savedConfirmation)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("KI-Trainingsplan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generatePlan() {
        isGenerating = true
        errorMessage = nil
        savedConfirmation = false
        let availableNames = exerciseStore.exercises
            .filter { !$0.isArchived }
            .map { $0.name }

        Task {
            do {
                let plans = try await mistral.generateTrainingPlan(
                    daysPerWeek: daysPerWeek,
                    durationMinutes: durationMinutes,
                    focus: focusText,
                    availableExerciseNames: availableNames
                )
                await MainActor.run {
                    generatedRoutines = plans
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func saveAllAsRoutines() {
        let baseSort = routineStore.routines.count
        let allExercises = exerciseStore.exercises.filter { !$0.isArchived }

        for (routineIdx, plan) in generatedRoutines.enumerated() {
            let routine = Routine(
                name: plan.name,
                notes: plan.notes,
                sortOrder: baseSort + routineIdx
            )

            var routineExercises: [RoutineExercise] = []
            for (exIdx, spec) in plan.exercises.enumerated() {
                let matched = allExercises.first {
                    $0.name.localizedCaseInsensitiveCompare(spec.exerciseName) == .orderedSame
                } ?? allExercises.first {
                    $0.name.localizedCaseInsensitiveContains(spec.exerciseName) ||
                    spec.exerciseName.localizedCaseInsensitiveContains($0.name)
                }

                let exerciseId: String
                if let matched = matched {
                    exerciseId = matched.id
                } else {
                    let created = Exercise(
                        name: spec.exerciseName,
                        muscleGroup: .other,
                        equipment: .other,
                        defaultRestSeconds: spec.restSeconds,
                        isCustom: true
                    )
                    exerciseStore.save(created)
                    exerciseId = created.id
                }

                routineExercises.append(
                    RoutineExercise(
                        routineId: routine.id,
                        exerciseId: exerciseId,
                        sortOrder: exIdx,
                        targetSets: spec.targetSets,
                        targetReps: spec.targetReps,
                        restSeconds: spec.restSeconds
                    )
                )
            }

            routineStore.saveRoutine(routine, exercises: routineExercises)
        }

        savedConfirmation = true
    }
}
