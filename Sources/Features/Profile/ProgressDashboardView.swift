import Charts
import SwiftUI

struct ProgressDashboardView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    enum Period: String, CaseIterable, Identifiable {
        case days30 = "30T"
        case days90 = "90T"
        case months6 = "6M"
        case all = "Alle"

        var id: String { rawValue }

        var cutoffDate: Date? {
            let cal = Calendar.current
            switch self {
            case .days30: return cal.date(byAdding: .day, value: -30, to: Date())
            case .days90: return cal.date(byAdding: .day, value: -90, to: Date())
            case .months6: return cal.date(byAdding: .month, value: -6, to: Date())
            case .all: return nil
            }
        }
    }

    struct StrengthPoint: Identifiable {
        let id: String
        let date: Date
        let volumeKg: Double
        let averageTop1RM: Double
    }

    struct ExerciseGain: Identifiable {
        let exercise: Exercise
        let start1RM: Double
        let latest1RM: Double

        var id: String { exercise.id }

        var deltaKg: Double { latest1RM - start1RM }
        var deltaPercent: Double {
            guard start1RM > 0 else { return 0 }
            return ((latest1RM - start1RM) / start1RM) * 100.0
        }
    }

    @State private var selectedPeriod: Period = .days90
    @State private var showVolumeInsteadOf1RM: Bool = false

    private var filteredWorkoutsAscending: [WorkoutDetail] {
        let cutoff = selectedPeriod.cutoffDate
        return historyStore.completedWorkouts
            .filter { detail in
                guard let cutoff = cutoff else { return true }
                return detail.workout.startedAt >= cutoff
            }
            .sorted { $0.workout.startedAt < $1.workout.startedAt }
    }

    private var filteredWeightsAscending: [BodyweightEntry] {
        let cutoff = selectedPeriod.cutoffDate
        return bodyweightStore.entries
            .map { $0.entry }
            .filter { entry in
                guard let cutoff = cutoff else { return true }
                return entry.recordedAt >= cutoff
            }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var strengthPoints: [StrengthPoint] {
        filteredWorkoutsAscending.compactMap { detail -> StrengthPoint? in
            var exerciseBest1RMs: [Double] = []
            for ex in detail.exercises {
                let best = ex.sets
                    .filter { $0.isCompleted && $0.setType != .warmup }
                    .compactMap { s -> Double? in
                        guard let w = s.weightKg, let r = s.reps, w > 0, r > 0 else { return nil }
                        return OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                    }
                    .max()
                if let best = best {
                    exerciseBest1RMs.append(best)
                }
            }
            let avg1RM = exerciseBest1RMs.isEmpty
                ? 0
                : exerciseBest1RMs.reduce(0, +) / Double(exerciseBest1RMs.count)

            guard detail.totalVolumeKg > 0 || avg1RM > 0 else { return nil }
            return StrengthPoint(
                id: detail.id,
                date: detail.workout.startedAt,
                volumeKg: detail.totalVolumeKg,
                averageTop1RM: avg1RM
            )
        }
    }

    private var exerciseGains: [ExerciseGain] {
        var recordsByExercise: [String: (exercise: Exercise, values: [Double])] = [:]

        for detail in filteredWorkoutsAscending {
            for ex in detail.exercises {
                let best = ex.sets
                    .filter { $0.isCompleted && $0.setType != .warmup }
                    .compactMap { s -> Double? in
                        guard let w = s.weightKg, let r = s.reps, w > 0, r > 0 else { return nil }
                        return OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                    }
                    .max()

                if let best = best {
                    if var existing = recordsByExercise[ex.exercise.id] {
                        existing.values.append(best)
                        recordsByExercise[ex.exercise.id] = existing
                    } else {
                        recordsByExercise[ex.exercise.id] = (ex.exercise, [best])
                    }
                }
            }
        }

        return recordsByExercise.values.compactMap { item -> ExerciseGain? in
            guard item.values.count >= 2,
                  let first = item.values.first,
                  let last = item.values.last else {
                return nil
            }
            return ExerciseGain(exercise: item.exercise, start1RM: first, latest1RM: last)
        }
        .sorted { $0.deltaPercent > $1.deltaPercent }
    }

    private var averageStrengthTrendPercent: Double? {
        if !exerciseGains.isEmpty {
            let sum = exerciseGains.reduce(0.0) { $0 + $1.deltaPercent }
            return sum / Double(exerciseGains.count)
        }
        guard strengthPoints.count >= 2,
              let first = strengthPoints.first?.volumeKg,
              let last = strengthPoints.last?.volumeKg,
              first > 0 else {
            return nil
        }
        return ((last - first) / first) * 100.0
    }

    private var bodyweightDeltaKg: Double? {
        guard filteredWeightsAscending.count >= 2,
              let first = filteredWeightsAscending.first?.weightKg,
              let last = filteredWeightsAscending.last?.weightKg else {
            return nil
        }
        return last - first
    }

    private var weightYDomain: ClosedRange<Double> {
        let weights = filteredWeightsAscending.map { $0.weightKg }
        guard let minW = weights.min(), let maxW = weights.max() else { return 60...100 }
        let pad = max(0.8, (maxW - minW) * 0.2)
        return (minW - pad)...(maxW + pad)
    }

    private var weeklyMuscleGroupSets: [(group: MuscleGroup, sets: Int)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var counts: [MuscleGroup: Int] = [:]
        for detail in historyStore.completedWorkouts where detail.workout.startedAt >= cutoff {
            for ex in detail.exercises {
                let workingSets = ex.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                counts[ex.exercise.muscleGroup, default: 0] += workingSets
            }
        }
        return MuscleGroup.allCases
            .filter { $0 != .other }
            .map { ($0, counts[$0] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Zeitraum", selection: $selectedPeriod) {
                    ForEach(Period.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                trendSummaryRow
                weeklyMuscleVolumeCard
                strengthChartCard
                bodyweightChartCard
                topGainsSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Fortschritt & Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weeklyMuscleVolumeCard: some View {
        let totalSets = weeklyMuscleGroupSets.reduce(0) { $0 + $1.sets }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wochen-Volumen (letzte 7 Tage)")
                        .font(.headline)
                    Text("Arbeitssätze pro Muskelgruppe · Richtwert 10–20 Sätze")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(totalSets) Sätze")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }

            Chart {
                RuleMark(y: .value("Ziel Min", 10))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.green.opacity(0.6))

                ForEach(weeklyMuscleGroupSets, id: \.group.id) { item in
                    BarMark(
                        x: .value("Muskel", item.group.displayName),
                        y: .value("Sätze", item.sets)
                    )
                    .foregroundStyle(item.group.accentColor)
                    .cornerRadius(6)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 170)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var trendSummaryRow: some View {
        HStack(spacing: 10) {
            TrendBannerTile(
                title: "Kraft-Trend",
                value: formattedStrengthTrend,
                subtitle: strengthTrendSubtitle,
                trendDirection: strengthDirection,
                positiveIsUp: true
            )

            TrendBannerTile(
                title: "Gewichts-Trend",
                value: formattedWeightTrend,
                subtitle: weightTrendSubtitle,
                trendDirection: weightDirection,
                positiveIsUp: false
            )
        }
    }

    private var formattedStrengthTrend: String {
        guard let pct = averageStrengthTrendPercent else { return "–" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))%"
    }

    private var strengthTrendSubtitle: String {
        guard let pct = averageStrengthTrendPercent else { return "Min. 2 Workouts nötig" }
        if pct > 0.5 { return "Aufwärtstrend" }
        if pct < -0.5 { return "Abwärtstrend" }
        return "Stabil"
    }

    private var strengthDirection: Int {
        guard let pct = averageStrengthTrendPercent else { return 0 }
        if pct > 0.5 { return 1 }
        if pct < -0.5 { return -1 }
        return 0
    }

    private var formattedWeightTrend: String {
        guard let delta = bodyweightDeltaKg else { return "–" }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Formatters.weight(delta)) kg"
    }

    private var weightTrendSubtitle: String {
        guard let delta = bodyweightDeltaKg else { return "Min. 2 Einträge nötig" }
        if delta < -0.15 { return "Abwärtstrend" }
        if delta > 0.15 { return "Aufwärtstrend" }
        return "Stabil"
    }

    private var weightDirection: Int {
        guard let delta = bodyweightDeltaKg else { return 0 }
        if delta > 0.15 { return 1 }
        if delta < -0.15 { return -1 }
        return 0
    }

    private var strengthChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kraftentwicklung")
                        .font(.headline)
                    Text(showVolumeInsteadOf1RM ? "Trainings-Volumen (kg)" : "Ø geschätztes 1RM (kg)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Metrik", selection: $showVolumeInsteadOf1RM) {
                    Text("1RM").tag(false)
                    Text("Volumen").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if strengthPoints.isEmpty {
                Text("Schließe Workouts mit Gewicht und Wiederholungen ab, um deine Kraftkurve zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart(strengthPoints) { point in
                    let yVal = showVolumeInsteadOf1RM ? point.volumeKg : point.averageTop1RM
                    AreaMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", yVal)
                    )
                    .foregroundStyle(Color.blue.opacity(0.16))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", yVal)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", yVal)
                    )
                    .foregroundStyle(Color.blue)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var bodyweightChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Körpergewicht")
                        .font(.headline)
                    if let latest = filteredWeightsAscending.last {
                        Text("Aktuell \(Formatters.weight(latest.weightKg)) kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Verlauf über Zeit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if bodyweightDeltaKg != nil {
                    Text(formattedWeightTrend)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background((weightDirection < 0 ? Color.green : Color.orange).opacity(0.16))
                        .foregroundColor(weightDirection < 0 ? .green : .orange)
                        .clipShape(Capsule())
                }
            }

            if filteredWeightsAscending.isEmpty {
                Text("Trage dein Körpergewicht unter „Profil → Körpergewicht & Fotos“ ein, um den Trend-Graphen zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart(filteredWeightsAscending) { entry in
                    AreaMark(
                        x: .value("Datum", entry.recordedAt),
                        yStart: .value("Min", weightYDomain.lowerBound),
                        yEnd: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.green.opacity(0.16))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", entry.recordedAt),
                        y: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", entry.recordedAt),
                        y: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.green)
                }
                .chartYScale(domain: weightYDomain)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var topGainsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kraftsteigerung nach Übung")
                .font(.headline)
                .padding(.horizontal, 4)

            if exerciseGains.isEmpty {
                Text("Sobald du eine Übung mindestens zweimal im gewählten Zeitraum trainiert hast, siehst du hier deine prozentuale Steigerung.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
            } else {
                ForEach(exerciseGains.prefix(8)) { gain in
                    NavigationLink {
                        ExerciseDetailView(exercise: gain.exercise)
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseThumbnailView(exercise: gain.exercise, size: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(gain.exercise.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("\(Formatters.weight(gain.start1RM)) kg → \(Formatters.weight(gain.latest1RM)) kg (1RM)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            let isPositive = gain.deltaKg >= 0
                            HStack(spacing: 3) {
                                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text("\(isPositive ? "+" : "")\(String(format: "%.1f", gain.deltaPercent))%")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((isPositive ? Color.green : Color.red).opacity(0.15))
                            .foregroundColor(isPositive ? .green : .red)
                            .clipShape(Capsule())
                        }
                        .strongCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TrendBannerTile: View {
    let title: String
    let value: String
    let subtitle: String
    let trendDirection: Int
    let positiveIsUp: Bool

    private var badgeColor: Color {
        if trendDirection == 0 { return .secondary }
        let isGood = positiveIsUp ? (trendDirection > 0) : (trendDirection < 0)
        return isGood ? .green : .orange
    }

    private var arrowIcon: String {
        if trendDirection > 0 { return "arrow.up.right" }
        if trendDirection < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: arrowIcon)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(badgeColor)
                    .padding(6)
                    .background(badgeColor.opacity(0.14))
                    .clipShape(Circle())
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(trendDirection == 0 ? .primary : badgeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
    }
}
