import Charts
import SwiftUI

struct ExerciseDetailView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var historyStore: HistoryStore

    let exercise: Exercise

    @State private var stats: ExerciseStats = .empty
    @State private var isShowingEditSheet: Bool = false

    private var currentExercise: Exercise {
        exerciseStore.exercises.first(where: { $0.id == exercise.id }) ?? exercise
    }

    private var chartPoints: [ExerciseProgressPoint] {
        stats.history.filter { $0.bestEstimated1RM > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoCard
                prCards
                chartCard
                historySection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(currentExercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Bearbeiten") {
                    isShowingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            ExerciseFormView(existingExercise: currentExercise) { updated in
                exerciseStore.save(updated)
            }
        }
        .onAppear {
            stats = historyStore.fetchStats(forExerciseId: exercise.id)
        }
        .onChange(of: historyStore.completedWorkouts.count) { _ in
            stats = historyStore.fetchStats(forExerciseId: exercise.id)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(currentExercise.muscleGroup.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())

                Text(currentExercise.equipment.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())

                Spacer()

                Label(Formatters.restDuration(currentExercise.defaultRestSeconds), systemImage: "timer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = currentExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var prCards: some View {
        HStack(spacing: 10) {
            PRCard(
                title: "Bestes 1RM",
                value: stats.bestEstimated1RM.map { "\(Formatters.weight($0)) kg" } ?? "–"
            )
            PRCard(
                title: "Max. Gewicht",
                value: stats.bestWeightKg.map { "\(Formatters.weight($0)) kg" } ?? "–"
            )
            PRCard(
                title: "Bestes Satz-Vol.",
                value: stats.bestSetVolumeKg.map { "\(Formatters.weight($0)) kg" } ?? "–"
            )
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Geschätztes 1RM (Epley)")
                .font(.headline)

            if chartPoints.isEmpty {
                Text("Schließe mindestens einen Arbeitssatz mit Gewicht und Wiederholungen ab, um den Fortschritt im Diagramm zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                Chart(chartPoints) { point in
                    AreaMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verlauf (\(stats.history.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if stats.history.isEmpty {
                Text("Diese Übung wurde noch in keinem abgeschlossenen Workout geloggt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(stats.history.reversed()) { point in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(point.workoutName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(Formatters.shortDate(point.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(point.sets) { workoutSet in
                            HStack {
                                Text(workoutSet.setType.shortBadge ?? "\(workoutSet.setOrder)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(workoutSet.setType == .warmup ? .orange : .primary)
                                    .frame(width: 22, height: 22)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                if let w = workoutSet.weightKg, let r = workoutSet.reps {
                                    Text("\(Formatters.weight(w)) kg × \(r)")
                                        .font(.subheadline)
                                } else if let r = workoutSet.reps {
                                    Text("\(r) Wdh.")
                                        .font(.subheadline)
                                } else {
                                    Text("Abgeschlossen")
                                        .font(.subheadline)
                                }

                                Spacer()

                                if workoutSet.setType != .warmup,
                                   let w = workoutSet.weightKg,
                                   let r = workoutSet.reps,
                                   w > 0, r > 0 {
                                    Text("1RM ~\(Formatters.weight(OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r))) kg")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

private struct PRCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
