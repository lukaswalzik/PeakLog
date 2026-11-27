import Charts
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore

    let detail: WorkoutDetail

    @State private var isShowingDeleteAlert: Bool = false
    @State private var heartRateSamples: [WorkoutHeartRateSample] = []

    private struct HRChartPoint: Identifiable {
        let id: Int
        let timestamp: Date
        let bpm: Int
    }

    private var durationText: String {
        let end = detail.workout.finishedAt ?? detail.workout.startedAt
        return Formatters.elapsedDuration(from: detail.workout.startedAt, to: end)
    }

    private var resolvedAvgHR: Int? {
        if let avg = detail.workout.avgHeartRate { return avg }
        guard !heartRateSamples.isEmpty else { return nil }
        let sum = heartRateSamples.reduce(0) { $0 + $1.bpm }
        return Int((Double(sum) / Double(heartRateSamples.count)).rounded())
    }

    private var resolvedMaxHR: Int? {
        detail.workout.maxHeartRate ?? heartRateSamples.map { $0.bpm }.max()
    }

    private var resolvedMinHR: Int? {
        detail.workout.minHeartRate ?? heartRateSamples.map { $0.bpm }.min()
    }

    private var hasHeartRateData: Bool {
        resolvedAvgHR != nil || !heartRateSamples.isEmpty
    }

    private var chartPoints: [HRChartPoint] {
        guard !heartRateSamples.isEmpty else { return [] }
        let maxPoints = 180
        if heartRateSamples.count <= maxPoints {
            return heartRateSamples.enumerated().map { idx, sample in
                HRChartPoint(id: idx, timestamp: sample.recordedAt, bpm: sample.bpm)
            }
        }
        let bucketSize = Double(heartRateSamples.count) / Double(maxPoints)
        var points: [HRChartPoint] = []
        points.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let start = Int(Double(i) * bucketSize)
            let end = min(heartRateSamples.count, Int(Double(i + 1) * bucketSize))
            guard start < end else { continue }
            let slice = heartRateSamples[start..<end]
            let avgBpm = Int((Double(slice.reduce(0) { $0 + $1.bpm }) / Double(slice.count)).rounded())
            let midTimestamp = slice[start + slice.count / 2].recordedAt
            points.append(HRChartPoint(id: i, timestamp: midTimestamp, bpm: avgBpm))
        }
        return points
    }

    private var chartYDomain: ClosedRange<Int> {
        let minVal = resolvedMinHR ?? 60
        let maxVal = resolvedMaxHR ?? 160
        let lower = max(30, minVal - 10)
        let upper = min(240, max(lower + 20, maxVal + 10))
        return lower...upper
    }

    private var zoneCounts: [(zone: HeartRateZone, count: Int)] {
        guard !heartRateSamples.isEmpty else { return [] }
        var counts: [HeartRateZone: Int] = [:]
        for sample in heartRateSamples {
            if let zone = HeartRateZone.zone(for: sample.bpm, maxHR: cardioStore.maxHeartRate) {
                counts[zone, default: 0] += 1
            }
        }
        return HeartRateZone.allCases.compactMap { zone in
            guard let count = counts[zone], count > 0 else { return nil }
            return (zone, count)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard

                if hasHeartRateData {
                    heartRateCard
                }

                if detail.exercises.isEmpty {
                    EmptyStateView(
                        systemImage: "dumbbell",
                        title: "Keine abgeschlossenen Sätze",
                        message: "In diesem Workout wurden keine Sätze abgeschlossen."
                    )
                } else {
                    ForEach(detail.exercises) { exerciseDetail in
                        exerciseCard(exerciseDetail)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(detail.workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Workout löschen")
            }
        }
        .onAppear {
            heartRateSamples = historyStore.fetchHeartRateSamples(forWorkoutId: detail.id)
        }
        .alert("Workout löschen?", isPresented: $isShowingDeleteAlert) {
            Button("Löschen", role: .destructive) {
                historyStore.deleteWorkout(id: detail.id)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieses abgeschlossene Training wird dauerhaft aus deinem Verlauf entfernt.")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Formatters.workoutDate(detail.workout.startedAt))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let gymName = detail.gymName {
                    Label(gymName, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                MetricTile(title: "Dauer", value: durationText)
                MetricTile(title: "Sätze", value: "\(detail.completedSetCount)")
                MetricTile(title: "Volumen", value: "\(Formatters.weight(detail.totalVolumeKg)) kg")
            }

            if let notes = detail.workout.notes, !notes.isEmpty {
                Divider()
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Herzfrequenz", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
                if !heartRateSamples.isEmpty {
                    Text("\(heartRateSamples.count) Messpunkte")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                MetricTile(title: "Ø Puls", value: resolvedAvgHR.map { "\($0) bpm" } ?? "–")
                MetricTile(title: "Max. Puls", value: resolvedMaxHR.map { "\($0) bpm" } ?? "–")
                MetricTile(title: "Min. Puls", value: resolvedMinHR.map { "\($0) bpm" } ?? "–")
            }

            if chartPoints.count >= 2 {
                Chart {
                    ForEach(chartPoints) { point in
                        AreaMark(
                            x: .value("Zeit", point.timestamp),
                            yStart: .value("Min", chartYDomain.lowerBound),
                            yEnd: .value("BPM", point.bpm)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red.opacity(0.28), Color.red.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("BPM", point.bpm)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Color.red)
                    }

                    if let avg = resolvedAvgHR {
                        RuleMark(y: .value("Durchschnitt", avg))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }
                }
                .chartYScale(domain: chartYDomain)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 165)
            }

            let zones = zoneCounts
            let totalZoned = zones.reduce(0) { $0 + $1.count }
            if totalZoned > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(zones, id: \.zone.id) { item in
                                let fraction = CGFloat(item.count) / CGFloat(totalZoned)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(item.zone.color)
                                    .frame(width: max(4, geo.size.width * fraction - 2))
                            }
                        }
                    }
                    .frame(height: 8)

                    HStack(spacing: 10) {
                        ForEach(zones, id: \.zone.id) { item in
                            let pct = Int((Double(item.count) / Double(totalZoned) * 100.0).rounded())
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(item.zone.color)
                                    .frame(width: 6, height: 6)
                                Text("\(item.zone.shortName) \(pct)%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func exerciseCard(_ item: WorkoutExerciseDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text("\(item.exercise.muscleGroup.displayName) · \(item.exercise.equipment.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            ForEach(item.sets) { workoutSet in
                HStack {
                    Text(workoutSet.setType.shortBadge ?? "\(workoutSet.setOrder)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(workoutSet.setType == .warmup ? .orange : .primary)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(setDescription(workoutSet))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    if workoutSet.setType != .warmup,
                       let w = workoutSet.weightKg,
                       let r = workoutSet.reps,
                       w > 0, r > 0 {
                        let est1RM = OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                        Text("1RM ~\(Formatters.weight(est1RM)) kg")
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

    private func setDescription(_ workoutSet: WorkoutSet) -> String {
        switch (workoutSet.weightKg, workoutSet.reps) {
        case let (w?, r?):
            return "\(Formatters.weight(w)) kg × \(r)"
        case let (nil, r?):
            return "\(r) Wdh."
        case let (w?, nil):
            return "\(Formatters.weight(w)) kg"
        case (nil, nil):
            return "Abgeschlossen"
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
