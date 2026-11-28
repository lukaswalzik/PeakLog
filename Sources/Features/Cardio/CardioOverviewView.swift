import Charts
import SwiftUI

struct CardioOverviewView: View {
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var activeCardioManager: ActiveCardioManager

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

    @State private var selectedRange: RangeFilter = .days30
    @State private var isShowingManualForm: Bool = false
    @State private var editingSession: CardioSession? = nil
    @State private var sessionToDelete: CardioSession? = nil

    private var zoneTotals: [(zone: HeartRateZone, seconds: Int)] {
        cardioStore.zoneTotals(forDays: selectedRange.days)
    }

    private var totalTrackedZoneSeconds: Int {
        zoneTotals.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                quickActionsRow
                CardioPlansSectionView { planned in
                    if activeCardioManager.hasActiveSession {
                        activeCardioManager.isPresentingSheet = true
                    } else {
                        activeCardioManager.start(plannedSession: planned)
                    }
                }
                zonesChartCard
                sessionsSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isShowingManualForm) {
            CardioFormView { session in
                cardioStore.save(session)
            }
        }
        .sheet(item: $editingSession) { session in
            CardioFormView(existingSession: session) { updated in
                cardioStore.save(updated)
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

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            Button {
                if activeCardioManager.hasActiveSession {
                    activeCardioManager.isPresentingSheet = true
                } else {
                    activeCardioManager.start()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stopwatch.fill")
                    Text(activeCardioManager.hasActiveSession ? "Cardio öffnen" : "Live-Timer")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingManualForm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Eintragen")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
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
            Text("Cardio-Einheiten (\(cardioStore.sessions.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if cardioStore.sessions.isEmpty {
                EmptyStateView(
                    systemImage: "heart.text.square",
                    title: "Noch keine Cardio-Einheiten",
                    message: "Starte den Live-Timer oder trage eine Einheit manuell ein."
                )
            } else {
                ForEach(cardioStore.sessions) { session in
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
                                    editingSession = session
                                } label: {
                                    Label("Bearbeiten", systemImage: "pencil")
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

                        HStack(spacing: 12) {
                            Label("\(session.durationSeconds / 60) min", systemImage: "clock")
                            if let dist = session.distanceKm {
                                Label("\(Formatters.weight(dist)) km", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            }
                            if let avg = session.avgHeartRate {
                                Label("Ø \(avg) bpm", systemImage: "heart.fill")
                                    .foregroundColor(.red)
                            }
                            if let kcal = session.calories {
                                Label("\(kcal) kcal", systemImage: "flame.fill")
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
                        editingSession = session
                    }
                }
            }
        }
    }
}
