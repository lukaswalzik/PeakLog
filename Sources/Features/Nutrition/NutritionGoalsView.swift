import SwiftUI

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    @State private var draft: NutritionGoals
    @State private var weightText: String

    init(initialGoals: NutritionGoals) {
        _draft = State(initialValue: initialGoals)
        _weightText = State(initialValue: Formatters.weight(initialGoals.weightKg))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Evidenzbasierter Rechner (Mifflin-St Jeor)"),
                    footer: Text("Berechnet deinen Grundumsatz (BMR) nach Mifflin-St Jeor, multipliziert mit dem Aktivitätsfaktor (TDEE) und verteilt Eiweiß (1,6–2,4 g/kg) sowie Fett (0,7–1,0 g/kg) nach evidenzbasierten Empfehlungen für Muskelaufbau & Muskelerhalt.")
                ) {
                    Picker("Geschlecht", selection: $draft.sex) {
                        ForEach(BiologicalSex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }

                    Stepper(value: $draft.ageYears, in: 14...90) {
                        HStack {
                            Text("Alter")
                            Spacer()
                            Text("\(draft.ageYears) Jahre")
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(value: $draft.heightCm, in: 130...225) {
                        HStack {
                            Text("Größe")
                            Spacer()
                            Text("\(draft.heightCm) cm")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Gewicht")
                        Spacer()
                        TextField("80", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: weightText) { val in
                                if let parsed = Formatters.parseWeight(val), parsed > 30, parsed < 300 {
                                    draft.weightKg = parsed
                                }
                            }
                        Text("kg")
                            .foregroundColor(.secondary)
                    }

                    if let latestWeight = bodyweightStore.latestEntry?.entry.weightKg {
                        Button {
                            draft.weightKg = latestWeight
                            weightText = Formatters.weight(latestWeight)
                        } label: {
                            Label("Aktuelles Gewicht übernehmen (\(Formatters.weight(latestWeight)) kg)", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                        }
                    }

                    Picker("Aktivität", selection: $draft.activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    Picker("Ziel", selection: $draft.goalType) {
                        ForEach(NutritionGoalType.allCases) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }

                    Stepper(value: $draft.proteinPerKg, in: 1.4...2.6, step: 0.1) {
                        HStack {
                            Text("Protein-Faktor")
                            Spacer()
                            Text("\(String(format: "%.1f", draft.proteinPerKg)) g/kg")
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(value: $draft.fatPerKg, in: 0.6...1.2, step: 0.05) {
                        HStack {
                            Text("Fett-Faktor")
                            Spacer()
                            Text("\(String(format: "%.2f", draft.fatPerKg)) g/kg")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grundumsatz (BMR): \(Int(round(draft.estimatedBMR))) kcal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Gesamtumsatz (TDEE): \(Int(round(draft.estimatedTDEE))) kcal")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }

                    Button {
                        draft.applyEvidenceBasedCalculation()
                    } label: {
                        Label("Empfehlung berechnen & einsetzen", systemImage: "wand.and.stars")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section(
                    header: Text("Tagesziele (manuell anpassbar)"),
                    footer: Text("Alle Werte kannst du hier jederzeit unabhängig vom Rechner manuell feinjustieren.")
                ) {
                    Stepper(value: $draft.targetCalories, in: 1000...6500, step: 50) {
                        HStack {
                            Text("Kalorienziel")
                            Spacer()
                            Text("\(draft.targetCalories) kcal")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }

                    Stepper(value: $draft.targetProteinGrams, in: 40...350, step: 5) {
                        HStack {
                            Text("Eiweiß")
                            Spacer()
                            Text("\(draft.targetProteinGrams) g")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }

                    Stepper(value: $draft.targetCarbsGrams, in: 20...800, step: 5) {
                        HStack {
                            Text("Kohlenhydrate")
                            Spacer()
                            Text("\(draft.targetCarbsGrams) g")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }

                    Stepper(value: $draft.targetFatGrams, in: 20...200, step: 5) {
                        HStack {
                            Text("Fett")
                            Spacer()
                            Text("\(draft.targetFatGrams) g")
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                    }
                }

                Section(
                    header: Text("Trainingstag vs. Ruhetag"),
                    footer: Text("Wenn aktiviert, erkennt StrongTracker automatisch deine Trainingstage (Kraft oder Cardio) und passt Kalorien & Kohlenhydrate an. Du kannst den Tag im Ernährungs-Tab auch jederzeit per 1 Tap umschalten.")
                ) {
                    Toggle("Extra-Ziele an Trainingstagen", isOn: $draft.useTrainingDayTargets)

                    if draft.useTrainingDayTargets {
                        Stepper(value: $draft.trainingDayCaloriesDelta, in: -400...1000, step: 50) {
                            HStack {
                                Text("Trainingstag Kalorien")
                                Spacer()
                                Text("\(draft.trainingDayCaloriesDelta >= 0 ? "+" : "")\(draft.trainingDayCaloriesDelta) kcal")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }

                        Stepper(value: $draft.trainingDayCarbsDelta, in: -100...250, step: 10) {
                            HStack {
                                Text("Trainingstag Carbs")
                                Spacer()
                                Text("\(draft.trainingDayCarbsDelta >= 0 ? "+" : "")\(draft.trainingDayCarbsDelta) g")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }

                        HStack {
                            Text("Trainingstag gesamt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(draft.effectiveCalories(isTrainingDay: true)) kcal · \(draft.effectiveCarbs(isTrainingDay: true))g KH")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Ziele & Kalorienrechner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        nutritionStore.goals = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
