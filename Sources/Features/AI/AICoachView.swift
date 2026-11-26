import SwiftUI

struct AICoachView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore
    @EnvironmentObject private var nutritionStore: NutritionStore
    @ObservedObject private var mistral = MistralAIService.shared

    @State private var customQuestion: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    private let quickPrompts: [(title: String, icon: String, prompt: String)] = [
        ("4-Wochen-Analyse", "chart.bar.doc.horizontal", "Analysiere meine letzten 4 Wochen Training, Volumen, Kraftentwicklung und Ernährung. Was läuft gut und was sollte ich nächste Woche konkret verbessern?"),
        ("Schwachstellen & Balance", "figure.strengthtraining.traditional", "Prüfe mein wöchentliches Muskelgruppen-Volumen und meine Push/Pull-Balance. Welche Muskelgruppen bekommen zu wenig oder zu viel Volumen?"),
        ("Ernährung & Recomp", "fork.knife", "Bewerte meinen Kalorien- und Protein-Durchschnitt im Vergleich zu meinem Ziel und meinem Gewichtsverlauf. Muss ich Kalorien oder Protein anpassen?")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !mistral.isConfigured {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Mistral API-Key benötigt", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Füge zuerst deinen Mistral API-Key in den Einstellungen hinzu, damit der KI-Coach deine Trainings- & Ernährungsdaten auswerten kann.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        NavigationLink("Mistral KI-Einstellungen öffnen") {
                            MistralSettingsView()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Schnell-Analysen")
                        .font(.headline)

                    ForEach(quickPrompts, id: \.title) { item in
                        Button {
                            askCoach(question: item.prompt)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                                Text(item.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || !mistral.isConfigured)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .strongCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Eigene Frage an deinen Coach")
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField("z. B. Soll ich nächste Woche Deload machen?", text: $customQuestion)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            let q = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else { return }
                            askCoach(question: q)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || !mistral.isConfigured)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .strongCard()

                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Mistral analysiert deine Daten...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .strongCard()
                }

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !mistral.lastCoachReport.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Coach-Auswertung", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        Divider()
                        Text(mistral.lastCoachReport)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("KI-Coach (Mistral)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    MistralSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private func askCoach(question: String) {
        isLoading = true
        errorMessage = nil
        let summary = buildAnonymizedDataSummary()
        Task {
            do {
                _ = try await mistral.generateCoachingReport(dataSummary: summary, question: question)
                await MainActor.run {
                    isLoading = false
                    customQuestion = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func buildAnonymizedDataSummary() -> String {
        let cal = Calendar.current
        let cutoff28 = cal.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let cutoff7 = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let workouts28 = historyStore.completedWorkouts.filter { $0.workout.startedAt >= cutoff28 }
        let workouts7 = workouts28.filter { $0.workout.startedAt >= cutoff7 }
        let cardio28 = cardioStore.sessions.filter { $0.startedAt >= cutoff28 }

        var weeklySets: [MuscleGroup: Int] = [:]
        for w in workouts7 {
            for ex in w.exercises {
                let working = ex.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                weeklySets[ex.exercise.muscleGroup, default: 0] += working
            }
        }
        let muscleVolumeStr = MuscleGroup.allCases
            .filter { $0 != .other }
            .map { "\($0.displayName): \(weeklySets[$0] ?? 0) Sätze" }
            .joined(separator: ", ")

        let weights28 = bodyweightStore.entries
            .map { $0.entry }
            .filter { $0.recordedAt >= cutoff28 }
            .sorted { $0.recordedAt < $1.recordedAt }
        let weightInfo: String
        if let first = weights28.first, let last = weights28.last, weights28.count >= 2 {
            let delta = last.weightKg - first.weightKg
            weightInfo = "Start \(Formatters.weight(first.weightKg)) kg → Aktuell \(Formatters.weight(last.weightKg)) kg (\(delta >= 0 ? "+" : "")\(Formatters.weight(delta)) kg in 28 Tagen)"
        } else if let latest = bodyweightStore.latestEntry?.entry {
            weightInfo = "Aktuell \(Formatters.weight(latest.weightKg)) kg"
        } else {
            weightInfo = "Keine Gewichtseinträge"
        }

        let goals = nutritionStore.goals
        let avgKcal = nutritionStore.averageWeeklyCalories
        let avgProt = nutritionStore.averageWeeklyProtein

        return """
        - Profil: \(goals.sex.displayName), \(goals.ageYears) J., \(goals.heightCm) cm, Ziel: \(goals.goalType.displayName)
        - Kraft-Workouts: \(workouts28.count) in 28 Tagen (\(workouts7.count) in den letzten 7 Tagen)
        - Cardio-Sessions (28T): \(cardio28.count)
        - Wochen-Volumen (7T Arbeitssätze): \(muscleVolumeStr)
        - Körpergewicht: \(weightInfo)
        - Ernährung (7T Ø): \(avgKcal) kcal (Ziel: \(goals.targetCalories) kcal), \(avgProt) g Protein (Ziel: \(goals.targetProteinGrams) g)
        """
    }
}
