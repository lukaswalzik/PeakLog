import SwiftUI

struct MilestonesView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    private var summary: UserProgressSummary {
        ProgressEngine.compute(
            workouts: historyStore.completedWorkouts,
            cardioSessions: cardioStore.sessions,
            bodyweightEntries: bodyweightStore.entries
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                levelHeroCard
                streakRow
                milestonesList
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Level & Meilensteine")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 62, height: 62)
                    VStack(spacing: 0) {
                        Text("LVL")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.85))
                        Text("\(summary.level)")
                            .font(.title2)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.rankTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("\(summary.totalXP) XP gesamt · \(summary.unlockedCount)/\(summary.milestones.count) Badges")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.88))
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: summary.levelProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)

                HStack {
                    Text("\(summary.currentLevelXP) / \(summary.nextLevelRequiredXP) XP")
                    Spacer()
                    Text("Noch \(summary.nextLevelRequiredXP - summary.currentLevelXP) XP bis Lv. \(summary.level + 1)")
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(18)
        .background(AppTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.blue.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    private var streakRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Wochen-Streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("\(summary.weeklyStreak) \(summary.weeklyStreak == 1 ? "Woche" : "Wochen")")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .strongCard(padding: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.green)
                    Text("Diese Woche")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("\(summary.sessionsThisWeek) \(summary.sessionsThisWeek == 1 ? "Training" : "Trainings")")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .strongCard(padding: 12)
        }
    }

    private var milestonesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meilensteine (\(summary.unlockedCount)/\(summary.milestones.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(summary.milestones) { milestone in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(milestone.isUnlocked ? milestone.color.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                            .frame(width: 48, height: 48)
                        Image(systemName: milestone.icon)
                            .font(.title3)
                            .foregroundColor(milestone.isUnlocked ? milestone.color : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(milestone.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if milestone.isUnlocked {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                            } else {
                                Text(milestone.progressText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(milestone.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !milestone.isUnlocked {
                            ProgressView(value: milestone.progress)
                                .progressViewStyle(.linear)
                                .tint(milestone.color)
                        }
                    }
                }
                .strongCard(padding: 12)
                .opacity(milestone.isUnlocked ? 1.0 : 0.85)
            }
        }
    }
}
