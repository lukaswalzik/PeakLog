import SwiftUI
import WidgetKit

// MARK: - Timeline Entry & Provider

struct PeakLogWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PeakLogWidgetSnapshot
}

struct PeakLogWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeakLogWidgetEntry {
        PeakLogWidgetEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PeakLogWidgetEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview
            ? (PeakLogWidgetStore.load(referenceDate: now) ?? .sample)
            : (PeakLogWidgetStore.load(referenceDate: now) ?? emptyTodaySnapshot(for: now))
        completion(PeakLogWidgetEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PeakLogWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = PeakLogWidgetStore.load(referenceDate: now) ?? emptyTodaySnapshot(for: now)
        let entry = PeakLogWidgetEntry(date: now, snapshot: snapshot)

        // Refresh in 30 minutes, or right after midnight so daily counters reset cleanly
        let thirtyMin = now.addingTimeInterval(1800)
        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))?.addingTimeInterval(60) ?? thirtyMin
        let refreshDate = min(thirtyMin, nextMidnight)

        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func emptyTodaySnapshot(for date: Date) -> PeakLogWidgetSnapshot {
        PeakLogWidgetSnapshot(
            updatedAt: date,
            dayKey: PeakLogWidgetSnapshot.dayKey(for: date),
            caloriesConsumed: 0,
            caloriesTarget: 2500,
            proteinGrams: 0,
            proteinTarget: 160,
            carbsGrams: 0,
            carbsTarget: 290,
            fatGrams: 0,
            fatTarget: 75,
            waterMl: 0,
            waterGoalMl: 3000,
            supplementsTaken: 0,
            supplementsTotal: 4,
            weeklyStreak: 0,
            workoutsThisWeek: 0,
            weeklyVolumeKg: 0,
            weekActivityDays: Array(repeating: false, count: 7),
            level: 1,
            rankTitle: "Einsteiger",
            nextRoutineName: nil,
            lastWorkoutName: nil,
            lastWorkoutDate: nil,
            readinessScore: nil
        )
    }
}

// MARK: - Shared Styling Helpers

private enum PeakLogWidgetTheme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.11, blue: 0.24),
            Color(red: 0.12, green: 0.20, blue: 0.48),
            Color(red: 0.17, green: 0.14, blue: 0.42)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let waterGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.16, blue: 0.30),
            Color(red: 0.08, green: 0.30, blue: 0.56),
            Color(red: 0.06, green: 0.20, blue: 0.42)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func formattedInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct WidgetRingView: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0.0, progress))))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 1. Nutrition & Macros Widget

struct PeakLogNutritionWidget: Widget {
    let kind: String = "PeakLogNutritionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeakLogWidgetProvider()) { entry in
            NutritionWidgetEntryView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "strongtracker://tab/nutrition"))
        }
        .configurationDisplayName("Ernährung & Makros")
        .description("Kalorien, Protein, Kohlenhydrate, Fett & Wasser heute auf einen Blick.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct NutritionWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakLogWidgetSnapshot

    var body: some View {
        switch family {
        case .systemSmall:
            smallHomeView
        case .systemMedium:
            mediumHomeView
        case .accessoryCircular:
            circularLockView
        case .accessoryRectangular:
            rectangularLockView
        case .accessoryInline:
            inlineLockView
        default:
            smallHomeView
        }
    }

    private var smallHomeView: some View {
        ZStack {
            PeakLogWidgetTheme.backgroundGradient

            VStack(spacing: 8) {
                HStack {
                    Label("PeakLog", systemImage: "fork.knife")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }

                ZStack {
                    WidgetRingView(progress: snapshot.calorieProgress, color: .cyan, lineWidth: 9)
                        .frame(width: 78, height: 78)

                    VStack(spacing: 1) {
                        Text(PeakLogWidgetTheme.formattedInt(snapshot.remainingCalories))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text("kcal übrig")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }

                HStack(spacing: 6) {
                    miniPill(label: "P", value: "\(snapshot.proteinGrams)g", color: .cyan)
                    miniPill(label: "💧", value: snapshot.formattedWaterLiters, color: .blue)
                }
            }
            .padding(12)
        }
    }

    private var mediumHomeView: some View {
        ZStack {
            PeakLogWidgetTheme.backgroundGradient

            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    ZStack {
                        WidgetRingView(progress: snapshot.calorieProgress, color: .cyan, lineWidth: 10)
                            .frame(width: 86, height: 86)

                        VStack(spacing: 1) {
                            Text(PeakLogWidgetTheme.formattedInt(snapshot.caloriesConsumed))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("/ \(PeakLogWidgetTheme.formattedInt(snapshot.caloriesTarget))")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Text("\(PeakLogWidgetTheme.formattedInt(snapshot.remainingCalories)) kcal offen")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                }
                .frame(width: 104)

                VStack(alignment: .leading, spacing: 8) {
                    macroBarRow(
                        title: "Protein",
                        value: "\(snapshot.proteinGrams)/\(snapshot.proteinTarget) g",
                        progress: snapshot.proteinProgress,
                        color: .cyan
                    )
                    macroBarRow(
                        title: "Carbs",
                        value: "\(snapshot.carbsGrams)/\(snapshot.carbsTarget) g",
                        progress: snapshot.carbsProgress,
                        color: .orange
                    )
                    macroBarRow(
                        title: "Fett",
                        value: "\(snapshot.fatGrams)/\(snapshot.fatTarget) g",
                        progress: snapshot.fatProgress,
                        color: .purple
                    )
                    macroBarRow(
                        title: "Wasser",
                        value: "\(snapshot.formattedWaterLiters)/\(snapshot.formattedWaterGoalLiters)",
                        progress: snapshot.waterProgress,
                        color: .blue
                    )
                }
            }
            .padding(14)
        }
    }

    private var circularLockView: some View {
        Gauge(value: snapshot.calorieProgress, in: 0...1) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(snapshot.caloriesConsumed)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularLockView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("PeakLog · Ernährung")
                    .font(.caption2)
                    .fontWeight(.bold)
                Spacer()
                Text("\(snapshot.proteinGrams)g P")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            Gauge(value: snapshot.calorieProgress, in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)

            Text("\(PeakLogWidgetTheme.formattedInt(snapshot.caloriesConsumed))/\(PeakLogWidgetTheme.formattedInt(snapshot.caloriesTarget)) kcal · \(snapshot.formattedWaterLiters)")
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var inlineLockView: some View {
        Text("\(PeakLogWidgetTheme.formattedInt(snapshot.caloriesConsumed)) kcal · \(snapshot.proteinGrams)g Protein")
    }

    private func miniPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private func macroBarRow(title: String, value: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(value)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, progress)))))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - 2. Training, Streak & Weekly Activity Widget

struct PeakLogTrainingWidget: Widget {
    let kind: String = "PeakLogTrainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeakLogWidgetProvider()) { entry in
            TrainingWidgetEntryView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "strongtracker://tab/start"))
        }
        .configurationDisplayName("Training & Streak")
        .description("Wochen-Streak, Trainings dieser Woche, Volumen & nächste Routine.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct TrainingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakLogWidgetSnapshot

    private let dayLabels = ["M", "D", "M", "D", "F", "S", "S"]

    var body: some View {
        switch family {
        case .systemSmall:
            smallHomeView
        case .systemMedium:
            mediumHomeView
        case .accessoryCircular:
            circularLockView
        case .accessoryRectangular:
            rectangularLockView
        case .accessoryInline:
            inlineLockView
        default:
            smallHomeView
        }
    }

    private var smallHomeView: some View {
        ZStack {
            PeakLogWidgetTheme.backgroundGradient

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("\(snapshot.weeklyStreak) Wo.")
                        .font(.subheadline)
                        .fontWeight(.heavy)
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Spacer()
                    Text("L\(snapshot.level)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.workoutsThisWeek) Workouts")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Diese Woche · \(snapshot.formattedWeeklyVolume)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                weekDotsRow

                if let next = snapshot.nextRoutineName {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.cyan)
                        Text(next)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
        }
    }

    private var mediumHomeView: some View {
        ZStack {
            PeakLogWidgetTheme.backgroundGradient

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(snapshot.weeklyStreak) Wochen Streak")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(snapshot.workoutsThisWeek)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.white)
                            Text("Workouts")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot.formattedWeeklyVolume)
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("Wochenvol.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    weekDotsRow
                }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NÄCHSTES TRAINING")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundColor(.white.opacity(0.65))
                        Text(snapshot.nextRoutineName ?? "Freies Training")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 6) {
                        Text("L\(snapshot.level) · \(snapshot.rankTitle)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let r = snapshot.readinessScore {
                            Text("R \(r)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mint.opacity(0.24))
                                .foregroundColor(.mint)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(width: 132)
            }
            .padding(14)
        }
    }

    private var weekDotsRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { idx in
                let active = idx < snapshot.weekActivityDays.count && snapshot.weekActivityDays[idx]
                VStack(spacing: 2) {
                    Circle()
                        .fill(active ? Color.green : Color.white.opacity(0.18))
                        .frame(width: 10, height: 10)
                    Text(dayLabels[idx])
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(active ? .white : .white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var circularLockView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                Text("\(snapshot.weeklyStreak)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Wo.")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
    }

    private var rectangularLockView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("\(snapshot.weeklyStreak) Wo. Streak", systemImage: "flame.fill")
                    .font(.caption2)
                    .fontWeight(.bold)
                Spacer()
                Text("L\(snapshot.level)")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            Text("Woche: \(snapshot.workoutsThisWeek) Workouts · \(snapshot.formattedWeeklyVolume)")
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
            if let next = snapshot.nextRoutineName {
                Text("Nächste: \(next)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inlineLockView: some View {
        Label("\(snapshot.weeklyStreak) Wo. Streak · \(snapshot.workoutsThisWeek) Workouts", systemImage: "flame.fill")
    }
}

// MARK: - 3. Hydration & Supplements Widget

struct PeakLogWaterWidget: Widget {
    let kind: String = "PeakLogWaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeakLogWidgetProvider()) { entry in
            WaterWidgetEntryView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "strongtracker://tab/nutrition"))
        }
        .configurationDisplayName("Wasser & Supplements")
        .description("Tägliche Flüssigkeitsaufnahme und abgehakte Supplements.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

private struct WaterWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PeakLogWidgetSnapshot

    var body: some View {
        switch family {
        case .systemSmall:
            smallHomeView
        case .accessoryCircular:
            circularLockView
        case .accessoryRectangular:
            rectangularLockView
        default:
            smallHomeView
        }
    }

    private var smallHomeView: some View {
        ZStack {
            PeakLogWidgetTheme.waterGradient

            VStack(spacing: 8) {
                HStack {
                    Label("Wasser", systemImage: "drop.fill")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("\(Int((snapshot.waterProgress * 100).rounded()))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.8))
                }

                ZStack {
                    WidgetRingView(progress: snapshot.waterProgress, color: .cyan, lineWidth: 9)
                        .frame(width: 78, height: 78)

                    VStack(spacing: 1) {
                        Text(snapshot.formattedWaterLiters)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        Text("/ \(snapshot.formattedWaterGoalLiters)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: snapshot.supplementsTaken >= snapshot.supplementsTotal && snapshot.supplementsTotal > 0 ? "checkmark.circle.fill" : "pills.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Supps \(snapshot.supplementsTaken)/\(snapshot.supplementsTotal)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(12)
        }
    }

    private var circularLockView: some View {
        Gauge(value: snapshot.waterProgress, in: 0...1) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(snapshot.formattedWaterLiters.replacingOccurrences(of: " L", with: "L"))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularLockView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("Wasser", systemImage: "drop.fill")
                    .font(.caption2)
                    .fontWeight(.bold)
                Spacer()
                Text("Supps \(snapshot.supplementsTaken)/\(snapshot.supplementsTotal)")
                    .font(.caption2)
                    .monospacedDigit()
            }

            Gauge(value: snapshot.waterProgress, in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)

            Text("\(snapshot.waterMl) / \(snapshot.waterGoalMl) ml")
                .font(.caption2)
                .monospacedDigit()
        }
    }
}
