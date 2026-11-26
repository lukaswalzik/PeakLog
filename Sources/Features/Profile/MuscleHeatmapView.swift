import SwiftUI

struct MuscleHeatmapView: View {
    let workouts: [WorkoutDetail]

    enum Mode: String, CaseIterable, Identifiable {
        case volume = "Wochen-Volumen"
        case recovery = "Erholung"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .volume
    @State private var selectedGroup: MuscleGroup = .chest

    private var weeklySetsByGroup: [MuscleGroup: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var counts: [MuscleGroup: Int] = [:]
        for detail in workouts where detail.workout.startedAt >= cutoff {
            for ex in detail.exercises {
                let working = ex.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                counts[ex.exercise.muscleGroup, default: 0] += working
            }
        }
        return counts
    }

    private var lastTrainedDaysAgo: [MuscleGroup: Int] {
        var latestDate: [MuscleGroup: Date] = [:]
        for detail in workouts {
            for ex in detail.exercises {
                let hasWorking = ex.sets.contains { $0.isCompleted && $0.setType != .warmup }
                guard hasWorking else { continue }
                let group = ex.exercise.muscleGroup
                if let prev = latestDate[group] {
                    if detail.workout.startedAt > prev {
                        latestDate[group] = detail.workout.startedAt
                    }
                } else {
                    latestDate[group] = detail.workout.startedAt
                }
            }
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [MuscleGroup: Int] = [:]
        for (group, date) in latestDate {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day ?? 0
            result[group] = max(0, days)
        }
        return result
    }

    private func fillColor(for group: MuscleGroup) -> Color {
        switch mode {
        case .volume:
            let sets = weeklySetsByGroup[group] ?? 0
            if sets == 0 { return Color(uiColor: .systemGray4) }
            if sets < 6 { return Color.yellow.opacity(0.85) }
            if sets < 10 { return Color.blue.opacity(0.8) }
            return Color.green.opacity(0.85)
        case .recovery:
            guard let days = lastTrainedDaysAgo[group] else {
                return Color.green.opacity(0.75)
            }
            if days <= 1 { return Color.red.opacity(0.82) }
            if days == 2 { return Color.orange.opacity(0.82) }
            return Color.green.opacity(0.82)
        }
    }

    private func recoveryText(for group: MuscleGroup) -> String {
        guard let days = lastTrainedDaysAgo[group] else {
            return "Frisch · noch nicht getrackt"
        }
        switch days {
        case 0: return "Heute trainiert · regeneriert"
        case 1: return "Vor 1 Tag · in Regeneration"
        case 2: return "Vor 2 Tagen · fast bereit"
        default: return "Vor \(days) Tagen · voll erholt"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muskel-Heatmap")
                        .font(.headline)
                    Text("Tippe auf eine Muskelgruppe für Details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Picker("Modus", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    frontBodyDiagram
                    Text("Vorne")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    backBodyDiagram
                    Text("Hinten")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)

            // Selected muscle detail bar
            let sets = weeklySetsByGroup[selectedGroup] ?? 0
            HStack(spacing: 10) {
                Circle()
                    .fill(fillColor(for: selectedGroup))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedGroup.displayName) · \(sets) Sätze (7 Tage)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(recoveryText(for: selectedGroup))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Legend
            HStack(spacing: 12) {
                if mode == .volume {
                    legendDot(color: Color(uiColor: .systemGray4), text: "0")
                    legendDot(color: .yellow, text: "1–5")
                    legendDot(color: .blue, text: "6–9")
                    legendDot(color: .green, text: "10+ Sätze")
                } else {
                    legendDot(color: .red, text: "Regeneriert (0–1T)")
                    legendDot(color: .orange, text: "Fast bereit (2T)")
                    legendDot(color: .green, text: "Frisch (3T+)")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.85)).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func muscleBlock(group: MuscleGroup, width: CGFloat, height: CGFloat, radius: CGFloat = 8) -> some View {
        let isSelected = selectedGroup == group
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fillColor(for: group))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            )
            .frame(width: width, height: height)
            .onTapGesture {
                selectedGroup = group
            }
    }

    private var frontBodyDiagram: some View {
        VStack(spacing: 4) {
            // Head
            Circle()
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 24, height: 24)

            // Shoulders + Chest + Biceps + Core
            HStack(alignment: .top, spacing: 4) {
                // Left Shoulder + Biceps
                VStack(spacing: 3) {
                    muscleBlock(group: .shoulders, width: 16, height: 20, radius: 7)
                    muscleBlock(group: .biceps, width: 14, height: 32, radius: 6)
                }

                // Torso: Chest + Core
                VStack(spacing: 4) {
                    muscleBlock(group: .chest, width: 52, height: 28, radius: 8)
                    muscleBlock(group: .core, width: 42, height: 36, radius: 7)
                }

                // Right Shoulder + Biceps
                VStack(spacing: 3) {
                    muscleBlock(group: .shoulders, width: 16, height: 20, radius: 7)
                    muscleBlock(group: .biceps, width: 14, height: 32, radius: 6)
                }
            }

            // Quads / Legs
            HStack(spacing: 6) {
                muscleBlock(group: .legs, width: 22, height: 58, radius: 8)
                muscleBlock(group: .legs, width: 22, height: 58, radius: 8)
            }
        }
        .frame(height: 164)
    }

    private var backBodyDiagram: some View {
        VStack(spacing: 4) {
            // Head
            Circle()
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 24, height: 24)

            // Shoulders + Back + Triceps
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 3) {
                    muscleBlock(group: .shoulders, width: 16, height: 20, radius: 7)
                    muscleBlock(group: .triceps, width: 14, height: 32, radius: 6)
                }

                VStack(spacing: 4) {
                    muscleBlock(group: .back, width: 52, height: 68, radius: 9)
                }

                VStack(spacing: 3) {
                    muscleBlock(group: .shoulders, width: 16, height: 20, radius: 7)
                    muscleBlock(group: .triceps, width: 14, height: 32, radius: 6)
                }
            }

            // Hamstrings / Glutes / Legs
            HStack(spacing: 6) {
                muscleBlock(group: .legs, width: 22, height: 58, radius: 8)
                muscleBlock(group: .legs, width: 22, height: 58, radius: 8)
            }
        }
        .frame(height: 164)
    }
}
