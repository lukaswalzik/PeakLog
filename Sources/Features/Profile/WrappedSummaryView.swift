import SwiftUI

struct WrappedSummaryView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var nutritionStore: NutritionStore

    enum Scope: String, CaseIterable, Identifiable {
        case month = "Dieser Monat"
        case year = "Dieses Jahr"
        case all = "Gesamt"

        var id: String { rawValue }

        func matches(_ date: Date) -> Bool {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .month:
                return cal.isDate(date, equalTo: now, toGranularity: .month)
            case .year:
                return cal.isDate(date, equalTo: now, toGranularity: .year)
            case .all:
                return true
            }
        }
    }

    @State private var scope: Scope = .month

    private var workouts: [WorkoutDetail] {
        historyStore.completedWorkouts.filter { scope.matches($0.workout.startedAt) }
    }

    private var cardioSessions: [CardioSession] {
        cardioStore.sessions.filter { scope.matches($0.startedAt) }
    }

    private var totalVolumeKg: Double {
        workouts.reduce(0.0) { $0 + $1.totalVolumeKg }
    }

    private var totalSets: Int {
        workouts.reduce(0) { $0 + $1.completedSetCount }
    }

    private var totalCardioMinutes: Int {
        cardioSessions.reduce(0) { $0 + $1.durationSeconds } / 60
    }

    private var funComparison: String {
        let tons = totalVolumeKg / 1000.0
        if tons < 1 {
            return "Jeder Anfang zählt – bald knackst du die erste Tonne!"
        } else if tons < 15 {
            let cars = max(1, Int(round(tons / 1.4)))
            return "Das entspricht etwa \(cars) Kleinwagen gestemmt!"
        } else if tons < 60 {
            let elephants = max(1, Int(round(tons / 5.5)))
            return "Das entspricht etwa \(elephants) ausgewachsenen Elefanten!"
        } else {
            let planes = max(1, Int(round(tons / 42.0)))
            return "Das entspricht etwa \(planes) vollgetankten Boeing 737!"
        }
    }

    private var favoriteExercise: (name: String, sets: Int)? {
        var counts: [String: Int] = [:]
        for w in workouts {
            for ex in w.exercises {
                let s = ex.sets.filter { $0.isCompleted }.count
                counts[ex.exercise.name, default: 0] += s
            }
        }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return (top.key, top.value)
    }

    private var strongestWeekday: String? {
        let cal = Calendar.current
        let symbols = ["", "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
        var counts: [Int: Int] = [:]
        for w in workouts {
            let wd = cal.component(.weekday, from: w.workout.startedAt)
            counts[wd, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }), top.key >= 1, top.key < symbols.count else {
            return nil
        }
        return "\(symbols[top.key]) (\(top.value)×)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Zeitraum", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                // Hero tonnage card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("PEAKLOG WRAPPED")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    Text(
                        totalVolumeKg >= 1000
                            ? "\(String(format: "%.1f", totalVolumeKg / 1000.0)) Tonnen"
                            : "\(Int(round(totalVolumeKg))) kg"
                    )
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundColor(.white)

                    Text(funComparison)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.purple, .indigo, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 10) {
                    wrappedTile(title: "Workouts", value: "\(workouts.count)", icon: "dumbbell.fill", color: .blue)
                    wrappedTile(title: "Sätze", value: "\(totalSets)", icon: "checkmark.circle.fill", color: .green)
                    wrappedTile(title: "Cardio", value: "\(totalCardioMinutes)m", icon: "heart.fill", color: .red)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Highlights")
                        .font(.headline)

                    if let fav = favoriteExercise {
                        highlightRow(icon: "star.fill", color: .yellow, title: "Lieblingsübung", value: "\(fav.name) (\(fav.sets) Sätze)")
                    }
                    if let day = strongestWeekday {
                        highlightRow(icon: "calendar", color: .blue, title: "Stärkster Wochentag", value: day)
                    }
                    if nutritionStore.averageWeeklyCalories > 0 {
                        highlightRow(
                            icon: "fork.knife",
                            color: .orange,
                            title: "Ø Ernährung (7T)",
                            value: "\(nutritionStore.averageWeeklyCalories) kcal · \(nutritionStore.averageWeeklyProtein)g E"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .strongCard()
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Rückblick (Wrapped)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func wrappedTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .strongCard(padding: 12)
    }

    private func highlightRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
        }
    }
}
