import SwiftUI

struct StrengthStandardsCardView: View {
    let workouts: [WorkoutDetail]
    let bodyweightKg: Double

    private struct LiftStandard: Identifiable {
        let id: String
        let title: String
        let keywords: [String]
        let noviceRatio: Double
        let intermediateRatio: Double
        let advancedRatio: Double
        let eliteRatio: Double
    }

    private let standards: [LiftStandard] = [
        LiftStandard(
            id: "bench",
            title: "Bankdrücken",
            keywords: ["bankdrücken", "bench"],
            noviceRatio: 0.75,
            intermediateRatio: 1.0,
            advancedRatio: 1.3,
            eliteRatio: 1.6
        ),
        LiftStandard(
            id: "squat",
            title: "Kniebeuge",
            keywords: ["kniebeuge", "squat"],
            noviceRatio: 1.0,
            intermediateRatio: 1.35,
            advancedRatio: 1.75,
            eliteRatio: 2.15
        ),
        LiftStandard(
            id: "deadlift",
            title: "Kreuzheben",
            keywords: ["kreuzheben", "deadlift"],
            noviceRatio: 1.25,
            intermediateRatio: 1.65,
            advancedRatio: 2.1,
            eliteRatio: 2.55
        ),
        LiftStandard(
            id: "ohp",
            title: "Schulterdrücken",
            keywords: ["schulterdrücken", "military", "overhead"],
            noviceRatio: 0.5,
            intermediateRatio: 0.68,
            advancedRatio: 0.9,
            eliteRatio: 1.15
        )
    ]

    private func best1RM(for standard: LiftStandard) -> Double? {
        var best: Double = 0
        for detail in workouts {
            for ex in detail.exercises {
                let lower = ex.exercise.name.lowercased()
                let matches = standard.keywords.contains { lower.contains($0) }
                guard matches else { continue }
                for set in ex.sets where set.isCompleted && set.setType != .warmup {
                    if let w = set.weightKg, let r = set.reps, w > 0, r > 0 {
                        let est = OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                        if est > best { best = est }
                    }
                }
            }
        }
        return best > 0 ? best : nil
    }

    private func tierInfo(ratio: Double, standard: LiftStandard) -> (label: String, color: Color, progress: Double) {
        if ratio >= standard.eliteRatio {
            return ("Elite", .purple, 1.0)
        } else if ratio >= standard.advancedRatio {
            let p = (ratio - standard.advancedRatio) / max(0.01, standard.eliteRatio - standard.advancedRatio)
            return ("Athlet", .blue, min(1.0, max(0.05, p)))
        } else if ratio >= standard.intermediateRatio {
            let p = (ratio - standard.intermediateRatio) / max(0.01, standard.advancedRatio - standard.intermediateRatio)
            return ("Fortgeschritten", .green, min(1.0, max(0.05, p)))
        } else if ratio >= standard.noviceRatio {
            let p = (ratio - standard.noviceRatio) / max(0.01, standard.intermediateRatio - standard.noviceRatio)
            return ("Aufbauend", .orange, min(1.0, max(0.05, p)))
        } else {
            let p = ratio / max(0.01, standard.noviceRatio)
            return ("Anfänger", .secondary, min(1.0, max(0.05, p)))
        }
    }

    private var pushPullSetsLast14Days: (push: Int, pull: Int, legs: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        var push = 0
        var pull = 0
        var legs = 0
        for detail in workouts where detail.workout.startedAt >= cutoff {
            for ex in detail.exercises {
                let count = ex.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                switch ex.exercise.muscleGroup {
                case .chest, .shoulders, .triceps: push += count
                case .back, .biceps: pull += count
                case .legs: legs += count
                case .core, .other: break
                }
            }
        }
        return (push, pull, legs)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1. Push / Pull Balance
            pushPullCard

            // 2. Strength Standards
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kraft-Standards")
                            .font(.headline)
                        Text("Geschätztes 1RM relativ zu \(Formatters.weight(bodyweightKg)) kg Körpergewicht")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                let matched = standards.compactMap { std -> (LiftStandard, Double)? in
                    guard let val = best1RM(for: std) else { return nil }
                    return (std, val)
                }

                if matched.isEmpty {
                    Text("Logge Grundübungen wie Bankdrücken, Kniebeuge, Kreuzheben oder Schulterdrücken, um dein Kraft-Level zu sehen.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(matched, id: \.0.id) { standard, best in
                        let ratio = best / max(40.0, bodyweightKg)
                        let tier = tierInfo(ratio: ratio, standard: standard)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(standard.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(Formatters.weight(best)) kg (\(String(format: "%.2f", ratio))× KG)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Text(tier.label)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(tier.color.opacity(0.16))
                                    .foregroundColor(tier.color)
                                    .clipShape(Capsule())
                            }
                            ProgressView(value: tier.progress)
                                .tint(tier.color)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .strongCard()
        }
    }

    private var pushPullCard: some View {
        let stats = pushPullSetsLast14Days
        let totalPP = stats.push + stats.pull
        let pushShare = totalPP > 0 ? Double(stats.push) / Double(totalPP) : 0.5

        let statusText: String
        let statusColor: Color
        if totalPP < 6 {
            statusText = "Noch zu wenig Daten (14 Tage)"
            statusColor = .secondary
        } else if pushShare > 0.62 {
            statusText = "Push-lastig – mehr Rücken/Pull empfohlen"
            statusColor = .orange
        } else if pushShare < 0.38 {
            statusText = "Pull-lastig – Push-Volumen ausbauen"
            statusColor = .blue
        } else {
            statusText = "Ausgewogenes Push/Pull-Verhältnis"
            statusColor = .green
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push / Pull Balance (14 Tage)")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                Spacer()
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.blue.opacity(0.85))
                        .frame(width: max(8, geo.size.width * pushShare))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.indigo.opacity(0.85))
                }
            }
            .frame(height: 12)

            HStack {
                Label("Push: \(stats.push) Sätze", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
                Label("Beine: \(stats.legs)", systemImage: "figure.run")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
                Label("Pull: \(stats.pull) Sätze", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(.indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }
}
