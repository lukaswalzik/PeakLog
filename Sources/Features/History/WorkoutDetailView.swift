import Charts
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var activeCardioManager: ActiveCardioManager
    @EnvironmentObject private var themeManager: ThemeManager

    let detail: WorkoutDetail

    private enum CardioSheet: Identifiable {
        case addManual
        case edit(CardioSession)

        var id: String {
            switch self {
            case .addManual: return "add-manual"
            case .edit(let session): return "edit-\(session.id)"
            }
        }
    }

    @State private var isShowingDeleteAlert: Bool = false
    @State private var cardioToDelete: CardioSession? = nil
    @State private var activeCardioSheet: CardioSheet? = nil
    @State private var heartRateSamples: [WorkoutHeartRateSample] = []

    private struct HRChartPoint: Identifiable {
        let id: Int
        let timestamp: Date
        let bpm: Int
    }

    private var linkedCardioSessions: [CardioSession] {
        cardioStore.sessions(forWorkoutId: detail.id)
    }

    private var sameDayStandaloneCardio: [CardioSession] {
        cardioStore.standaloneSessions.filter {
            Calendar.current.isDate($0.startedAt, inSameDayAs: detail.workout.startedAt)
        }
    }

    private var strengthDurationSeconds: Int {
        let end = detail.workout.finishedAt ?? detail.workout.startedAt
        return max(0, Int(end.timeIntervalSince(detail.workout.startedAt)))
    }

    private var totalCardioSeconds: Int {
        linkedCardioSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var durationText: String {
        let totalSecs = strengthDurationSeconds + totalCardioSeconds
        let end = detail.workout.startedAt.addingTimeInterval(TimeInterval(totalSecs))
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

                cardioSection

                VStack(alignment: .leading, spacing: 12) {
                    if !linkedCardioSessions.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundColor(.accentColor)
                            Text("Krafttraining")
                                .font(.headline)
                        }
                        .padding(.horizontal, 4)
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
        .sheet(item: $activeCardioSheet) { sheet in
            switch sheet {
            case .addManual:
                CardioFormView(
                    prefilledSession: CardioSession(
                        activityType: .walking,
                        startedAt: detail.workout.finishedAt ?? detail.workout.startedAt,
                        durationSeconds: 1200
                    ),
                    defaultWorkoutId: detail.id
                ) { session in
                    cardioStore.save(session)
                }
                .tint(themeManager.preset.accentColor)
                .preferredColorScheme(themeManager.appearance.colorScheme)
            case .edit(let session):
                CardioFormView(existingSession: session) { updated in
                    cardioStore.save(updated)
                }
                .tint(themeManager.preset.accentColor)
                .preferredColorScheme(themeManager.appearance.colorScheme)
            }
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
        .alert(
            "Cardio-Einheit löschen?",
            isPresented: Binding(
                get: { cardioToDelete != nil },
                set: { if !$0 { cardioToDelete = nil } }
            ),
            presenting: cardioToDelete
        ) { session in
            Button("Löschen", role: .destructive) {
                cardioStore.delete(id: session.id)
                cardioToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                cardioToDelete = nil
            }
        } message: { session in
            Text("Die Cardio-Einheit „\(session.activityType.displayName)“ wird dauerhaft gelöscht.")
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
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(gymName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                MetricTile(title: linkedCardioSessions.isEmpty ? "Dauer" : "Gesamtdauer", value: durationText)
                MetricTile(title: "Sätze", value: "\(detail.completedSetCount)")
                MetricTile(title: "Volumen", value: "\(Formatters.weight(detail.totalVolumeKg)) kg")
            }

            if !linkedCardioSessions.isEmpty {
                let kraftMins = max(1, strengthDurationSeconds / 60)
                let cardioMins = max(1, totalCardioSeconds / 60)
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text("Kombiniertes Training · \(kraftMins) Min Kraft + \(cardioMins) Min Cardio")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.green)
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

    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.circle.fill")
                        .foregroundColor(.green)
                    Text("Cardio")
                        .font(.headline)
                }

                Spacer()

                Menu {
                    Button {
                        if activeCardioManager.hasActiveSession {
                            activeCardioManager.linkedWorkoutId = detail.id
                            activeCardioManager.isPresentingSheet = true
                        } else {
                            activeCardioManager.start(linkedWorkoutId: detail.id)
                        }
                    } label: {
                        Label("Live Cardio-Timer starten", systemImage: "stopwatch.fill")
                    }

                    Button {
                        activeCardioSheet = .addManual
                    } label: {
                        Label("Cardio manuell eintragen", systemImage: "plus.circle")
                    }

                    if !sameDayStandaloneCardio.isEmpty {
                        Divider()
                        ForEach(sameDayStandaloneCardio) { existing in
                            Button {
                                cardioStore.linkSession(existing, toWorkoutId: detail.id)
                            } label: {
                                Label(
                                    "Verknüpfen: \(existing.activityType.displayName) (\(max(1, existing.durationSeconds / 60)) Min)",
                                    systemImage: "link"
                                )
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                        Text("Cardio hinzufügen")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)

            if linkedCardioSessions.isEmpty {
                Text("Kein Cardio angehängt. Du kannst direkt einen Live-Timer starten, Cardio nachtragen oder eine Einheit vom selben Tag verknüpfen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(linkedCardioSessions) { session in
                    linkedCardioCard(session)
                }
            }
        }
    }

    private func linkedCardioCard(_ session: CardioSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: session.activityType.systemImage)
                    .font(.title3)
                    .foregroundColor(session.activityType.accentColor)
                    .frame(width: 40, height: 40)
                    .background(session.activityType.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.activityType.displayName)
                        .font(.headline)
                    Text(Formatters.workoutDate(session.startedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        activeCardioSheet = .edit(session)
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    Button {
                        cardioStore.linkSession(session, toWorkoutId: nil)
                    } label: {
                        Label("Vom Training trennen", systemImage: "link.badge.minus")
                    }
                    Button(role: .destructive) {
                        cardioToDelete = session
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("\(max(1, session.durationSeconds / 60)) min")
                }
                if let dist = session.distanceKm {
                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        Text("\(Formatters.weight(dist)) km")
                    }
                }
                if let avg = session.avgHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                        Text("Ø \(avg) bpm")
                    }
                    .foregroundColor(.red)
                }
                if let maxHR = session.maxHeartRate {
                    Text("Max \(maxHR)")
                        .foregroundColor(.secondary)
                }
                if let kcal = session.calories {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(kcal) kcal")
                    }
                    .foregroundColor(.orange)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if session.totalZoneSeconds > 0 {
                HeartRateZoneBarView(session: session, height: 10)
            }

            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            activeCardioSheet = .edit(session)
        }
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
