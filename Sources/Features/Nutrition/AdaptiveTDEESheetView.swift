import SwiftUI

struct AdaptiveTDEESheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutritionStore: NutritionStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    @State private var appliedBanner: Bool = false

    private struct AdaptiveResult {
        let avgDailyCalories: Double
        let startWeightKg: Double
        let endWeightKg: Double
        let weightDeltaKg: Double
        let spanDays: Double
        let loggedNutritionDays: Int
        let weighInCount: Int
        let adaptiveTDEE: Int
        let confidence: String
        let confidenceColor: Color
    }

    private var formulaTDEE: Int {
        Int(round(nutritionStore.goals.estimatedTDEE))
    }

    private var analysis: AdaptiveResult? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let validNutritionDays = nutritionStore.monthlyPoints.filter { $0.calories >= 800 }
        let weights = bodyweightStore.entries
            .map { $0.entry }
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }

        guard validNutritionDays.count >= 5, weights.count >= 2,
              let firstWeightDate = weights.first?.recordedAt,
              let lastWeightDate = weights.last?.recordedAt else {
            return nil
        }

        let spanDays = max(5.0, lastWeightDate.timeIntervalSince(firstWeightDate) / 86400.0)
        guard spanDays >= 5.0 else { return nil }

        // Smooth start and end weight using up to 3 measurements on each end
        let sliceCount = min(3, max(1, weights.count / 2))
        let startAvg = weights.prefix(sliceCount).reduce(0.0) { $0 + $1.weightKg } / Double(sliceCount)
        let endAvg = weights.suffix(sliceCount).reduce(0.0) { $0 + $1.weightKg } / Double(sliceCount)
        let weightDelta = endAvg - startAvg

        let avgCals = validNutritionDays.reduce(0.0) { $0 + $1.calories } / Double(validNutritionDays.count)
        // 1 kg body mass ≈ 7700 kcal
        let dailyEnergyBalance = (weightDelta * 7700.0) / spanDays
        let rawTDEE = avgCals - dailyEnergyBalance
        let clampedTDEE = max(1300, min(5500, Int(round(rawTDEE / 10.0) * 10.0)))

        let (confidence, color): (String, Color)
        if validNutritionDays.count >= 14 && weights.count >= 6 && spanDays >= 14 {
            confidence = "Hoch"
            color = .green
        } else if validNutritionDays.count >= 8 && weights.count >= 4 {
            confidence = "Mittel"
            color = .orange
        } else {
            confidence = "Vorläufig"
            color = .blue
        }

        return AdaptiveResult(
            avgDailyCalories: avgCals,
            startWeightKg: startAvg,
            endWeightKg: endAvg,
            weightDeltaKg: weightDelta,
            spanDays: spanDays,
            loggedNutritionDays: validNutritionDays.count,
            weighInCount: weights.count,
            adaptiveTDEE: clampedTDEE,
            confidence: confidence,
            confidenceColor: color
        )
    }

    private var loggedDaysCount: Int {
        nutritionStore.monthlyPoints.filter { $0.calories >= 800 }.count
    }

    private var recentWeighInsCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return bodyweightStore.entries.filter { $0.entry.recordedAt >= cutoff }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let result = analysis {
                        let recommendedTarget = max(
                            1200,
                            Int(round(Double(result.adaptiveTDEE) + nutritionStore.goals.goalType.calorieDelta))
                        )
                        let diffVsFormula = result.adaptiveTDEE - formulaTDEE

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Dein adaptiver TDEE", systemImage: "waveform.path.ecg")
                                    .font(.headline)
                                Spacer()
                                Text("Genauigkeit: \(result.confidence)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(result.confidenceColor.opacity(0.16))
                                    .foregroundColor(result.confidenceColor)
                                    .clipShape(Capsule())
                            }

                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(result.adaptiveTDEE)")
                                    .font(.system(size: 40, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundColor(.accentColor)
                                Text("kcal / Tag")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Text("Formel-Schätzung (Mifflin-St Jeor): \(formulaTDEE) kcal (\(diffVsFormula >= 0 ? "+" : "")\(diffVsFormula) kcal Abweichung)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Divider()

                            HStack(spacing: 12) {
                                statBox(title: "Ø Aufnahme", value: "\(Int(round(result.avgDailyCalories))) kcal")
                                statBox(
                                    title: "Gewichtstrend",
                                    value: "\(result.weightDeltaKg >= 0 ? "+" : "")\(Formatters.weight(result.weightDeltaKg)) kg"
                                )
                                statBox(title: "Datenbasis", value: "\(result.loggedNutritionDays)T / \(result.weighInCount)W")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strongCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Empfohlenes Tagesziel")
                                .font(.headline)
                            Text("Für dein Ziel „\(nutritionStore.goals.goalType.displayName)“ empfiehlt der adaptive Algorithmus:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("\(recommendedTarget) kcal")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Spacer()
                                Button {
                                    applyAdaptiveTarget(calories: recommendedTarget)
                                } label: {
                                    Label(appliedBanner ? "Übernommen!" : "Ziel übernehmen", systemImage: appliedBanner ? "checkmark" : "arrow.down.circle.fill")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(appliedBanner ? .green : .accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strongCard()
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.title)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Noch zu wenig Daten")
                                        .font(.headline)
                                    Text("Der adaptive TDEE-Rechner lernt deinen echten Verbrauch aus Kalorien + Gewichtsverlauf.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                progressRequirementRow(
                                    title: "Getrackte Ernährungstage (min. 5)",
                                    current: min(5, loggedDaysCount),
                                    target: 5
                                )
                                progressRequirementRow(
                                    title: "Gewichtseinträge über ≥ 5 Tage (min. 2)",
                                    current: min(2, recentWeighInsCount),
                                    target: 2
                                )
                            }

                            Text("Aktueller Formel-TDEE: \(formulaTDEE) kcal/Tag. Sobald genug Einträge vorhanden sind, erscheint hier dein echter Stoffwechsel-Verbrauch.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strongCard()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wie funktioniert das?")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Ähnlich wie bei MacroFactor vergleicht StrongTracker deine durchschnittliche Kalorienzufuhr der letzten 28 Tage mit deinem geglätteten Gewichtstrend (1 kg ≈ 7.700 kcal). So werden individuelle Unterschiede bei NEAT, Körperbau und Stoffwechsel automatisch ausgeglichen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Adaptiver TDEE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func progressRequirementRow(title: String, current: Int, target: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text("\(current) / \(target)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(current >= target ? .green : .secondary)
            }
            ProgressView(value: Double(current), total: Double(target))
                .tint(current >= target ? .green : .accentColor)
        }
    }

    private func applyAdaptiveTarget(calories: Int) {
        var updated = nutritionStore.goals
        updated.targetCalories = calories
        let remainingKcal = max(0, calories - (updated.targetProteinGrams * 4) - (updated.targetFatGrams * 9))
        updated.targetCarbsGrams = max(20, remainingKcal / 4)
        nutritionStore.goals = updated
        appliedBanner = true
    }
}
