import Charts
import SwiftUI

struct CardioOverviewView: View {
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var themeManager: ThemeManager

    enum RangeFilter: String, CaseIterable, Identifiable {
        case days7 = "7T"
        case days30 = "30T"
        case all = "Alle"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .days7: return 7
            case .days30: return 30
            case .all: return nil
            }
        }
    }

    private enum ActiveFormSheet: Identifiable {
        case create
        case edit(CardioSession)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let session): return "edit-\(session.id)"
            }
        }
    }

    @State private var selectedRange: RangeFilter = .days30
    @State private var showCombinedSessions: Bool = false
    @State private var activeFormSheet: ActiveFormSheet? = nil
    @State private var sessionToDelete: CardioSession? = nil

    private var zoneTotals: [(zone: HeartRateZone, seconds: Int)] {
        cardioStore.zoneTotals(forDays: selectedRange.days)
    }

    private var totalTrackedZoneSeconds: Int {
        zoneTotals.reduce(0) { $0 + $1.seconds }
    }

    private var displayedSessions: [CardioSession] {
        showCombinedSessions ? cardioStore.sessions : cardioStore.standaloneSessions
    }

    private var linkedCount: Int {
        cardioStore.linkedSessions.count
    }

    private func linkedWorkoutName(for workoutId: String?) -> String? {
        guard let id = workoutId else { return nil }
        return historyStore.completedWorkouts.first(where: { $0.id == id })?.workout.name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                addCompletedCardioBar
                zonesChartCard
                sessionsSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: $activeFormSheet) { sheet in
            switch sheet {
            case .create:
                CardioFormView { session in
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
        .alert(
            "Cardio-Einheit löschen?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("Löschen", role: .destructive) {
                cardioStore.delete(id: session.id)
                sessionToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                sessionToDelete = nil
            }
        } message: { session in
            Text("Die Einheit „\(session.activityType.displayName)“ wird dauerhaft gelöscht.")
        }
    }

    private var addCompletedCardioBar: some View {
        Button {
            activeFormSheet = .create
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
                Text("Abgeschlossenes Cardio eintragen")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.14))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var zonesChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HF-Trainingszonen")
                        .font(.headline)
                    Text("Max-HF \(cardioStore.maxHeartRate) bpm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Zeitraum", selection: $selectedRange) {
                    ForEach(RangeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if totalTrackedZoneSeconds == 0 {
                Text("Logge deine erste Cardio-Einheit mit Zonen-Minuten (z. B. aus deinem Oura Ring oder per Live-Timer), um deine Zonen-Verteilung zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                Chart(zoneTotals, id: \.zone.id) { item in
                    BarMark(
                        x: .value("Zone", item.zone.shortName),
                        y: .value("Minuten", Double(item.seconds) / 60.0)
                    )
                    .foregroundStyle(item.zone.color)
                    .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 170)

                VStack(spacing: 6) {
                    ForEach(zoneTotals, id: \.zone.id) { item in
                        let mins = item.seconds / 60
                        let pct = totalTrackedZoneSeconds > 0
                            ? Int(round(Double(item.seconds) / Double(totalTrackedZoneSeconds) * 100))
                            : 0
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.zone.color)
                                .frame(width: 9, height: 9)
                            Text(item.zone.title)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text(item.zone.bpmRangeText(maxHR: cardioStore.maxHeartRate))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(mins) min (\(pct)%)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Abgeschlossene Einheiten (\(displayedSessions.count))")
                    .font(.headline)

                Spacer()

                if linkedCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCombinedSessions.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCombinedSessions ? "link.circle.fill" : "link.circle")
                                .font(.caption2)
                            Text(showCombinedSessions ? "Alle inkl. Kombi" : "+\(linkedCount) im Kraft-Verlauf")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(showCombinedSessions ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundColor(showCombinedSessions ? .accentColor : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            if displayedSessions.isEmpty {
                if linkedCount > 0 && !showCombinedSessions {
                    VStack(spacing: 10) {
                        EmptyStateView(
                            systemImage: "link.circle",
                            title: "Keine eigenständigen Cardio-Einheiten",
                            message: "Du hast \(linkedCount) Cardio-\(linkedCount == 1 ? "Einheit" : "Einheiten"), die direkt in deinen Krafttrainings gespeichert sind."
                        )
                        Button("Kombinierte Cardio-Einheiten anzeigen") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCombinedSessions = true
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .buttonStyle(.bordered)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "heart.text.square",
                        title: "Noch keine Cardio-Einheiten",
                        message: "Starte Cardio über den Start-Tab oder trage hier eine abgeschlossene Einheit manuell ein."
                    )
                }
            } else {
                ForEach(displayedSessions) { session in
                    cardioSessionCard(session)
                }
            }
        }
    }

    private func cardioSessionCard(_ session: CardioSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: session.activityType.systemImage)
                    .font(.title3)
                    .foregroundColor(session.activityType.accentColor)
                    .frame(width: 42, height: 42)
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
                        activeFormSheet = .edit(session)
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    if session.workoutId != nil {
                        Button {
                            cardioStore.linkSession(session, toWorkoutId: nil)
                        } label: {
                            Label("Vom Krafttraining trennen", systemImage: "link.badge.minus")
                        }
                    }
                    Button(role: .destructive) {
                        sessionToDelete = session
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            if let workoutName = linkedWorkoutName(for: session.workoutId) {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text("Kombiniert mit: \(workoutName)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.14))
                .foregroundColor(.green)
                .clipShape(Capsule())
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
        .onTapGesture {
            activeFormSheet = .edit(session)
        }
    }
}
