import Charts
import SwiftUI
import UIKit

// MARK: - Sauna Overview (used in Verlauf -> Sauna & Profil -> Sauna & Kälte)

struct SaunaOverviewView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var themeManager: ThemeManager

    private enum ActiveSaunaSheet: Identifiable {
        case liveTimer
        case manualForm
        case edit(SaunaSession)

        var id: String {
            switch self {
            case .liveTimer: return "live-timer"
            case .manualForm: return "manual-form"
            case .edit(let session): return "edit-\(session.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSaunaSheet? = nil
    @State private var sessionToDelete: SaunaSession? = nil

    private struct WeeklySaunaBar: Identifiable {
        let weekStart: Date
        let label: String
        let minutes: Int
        var id: Date { weekStart }
    }

    private var sessionsLast30Days: [SaunaSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return wellnessStore.saunaSessions.filter { $0.startedAt >= cutoff }
    }

    private var avgTempLast30Days: Int? {
        guard !sessionsLast30Days.isEmpty else { return nil }
        let sum = sessionsLast30Days.reduce(0) { $0 + $1.temperatureCelsius }
        return Int((Double(sum) / Double(sessionsLast30Days.count)).rounded())
    }

    private var coldPlungePercent: Int {
        guard !wellnessStore.saunaSessions.isEmpty else { return 0 }
        let count = wellnessStore.saunaSessions.filter { $0.coldPlungeDone }.count
        return Int((Double(count) / Double(wellnessStore.saunaSessions.count) * 100.0).rounded())
    }

    private var weeklyBars: [WeeklySaunaBar] {
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = .current
        let now = Date()
        let comps = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let currentWeekStart = isoCal.date(from: comps) else { return [] }

        return (0..<8).reversed().compactMap { offset -> WeeklySaunaBar? in
            guard let start = isoCal.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let end = isoCal.date(byAdding: .day, value: 7, to: start) else {
                return nil
            }
            let mins = wellnessStore.saunaSessions
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .reduce(0) { $0 + $1.totalDurationMinutes }
            let kw = isoCal.component(.weekOfYear, from: start)
            return WeeklySaunaBar(weekStart: start, label: "KW\(kw)", minutes: mins)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                quickActionsRow
                summaryStatsRow
                weeklyChartCard
                sessionsSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .liveTimer:
                LiveSaunaTimerView { session, extraWaterMl in
                    wellnessStore.saveSaunaSession(session)
                    if extraWaterMl > 0 {
                        wellnessStore.adjustTodayWater(deltaMl: extraWaterMl)
                    }
                }
                .tint(themeManager.preset.accentColor)
                .preferredColorScheme(themeManager.appearance.colorScheme)
            case .manualForm:
                SaunaSessionFormView { session, extraWaterMl in
                    wellnessStore.saveSaunaSession(session)
                    if extraWaterMl > 0 {
                        wellnessStore.adjustTodayWater(deltaMl: extraWaterMl)
                    }
                }
                .tint(themeManager.preset.accentColor)
                .preferredColorScheme(themeManager.appearance.colorScheme)
            case .edit(let session):
                SaunaSessionFormView(existingSession: session) { updated, extraWaterMl in
                    wellnessStore.saveSaunaSession(updated)
                    if extraWaterMl > 0 {
                        wellnessStore.adjustTodayWater(deltaMl: extraWaterMl)
                    }
                }
                .tint(themeManager.preset.accentColor)
                .preferredColorScheme(themeManager.appearance.colorScheme)
            }
        }
        .alert(
            "Sauna-Session löschen?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("Löschen", role: .destructive) {
                wellnessStore.deleteSaunaSession(id: session.id)
                sessionToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                sessionToDelete = nil
            }
        } message: { session in
            Text("Die \(session.saunaType.displayName)-Session (\(session.totalDurationMinutes) Min) wird dauerhaft gelöscht.")
        }
    }

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .liveTimer
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text("Live Sauna-Timer")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                activeSheet = .manualForm
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

    private var summaryStatsRow: some View {
        HStack(spacing: 10) {
            saunaStatTile(
                title: "Diese Woche",
                value: "\(wellnessStore.saunaSessionsThisWeek.count)x",
                subtitle: "\(wellnessStore.saunaMinutesThisWeek) Min",
                color: .orange
            )
            saunaStatTile(
                title: "30 Tage",
                value: "\(sessionsLast30Days.count)",
                subtitle: avgTempLast30Days.map { "Ø \($0) °C" } ?? "Sessions",
                color: .red
            )
            saunaStatTile(
                title: "Gesamtzeit",
                value: formattedTotalHours,
                subtitle: coldPlungePercent > 0 ? "\(coldPlungePercent)% mit Kälte" : "\(wellnessStore.saunaSessions.count) Sessions",
                color: .cyan
            )
        }
    }

    private var formattedTotalHours: String {
        let mins = wellnessStore.totalSaunaMinutes
        if mins >= 60 {
            let hrs = Double(mins) / 60.0
            return String(format: "%.1f Std.", hrs).replacingOccurrences(of: ".", with: ",")
        }
        return "\(mins) Min"
    }

    private func saunaStatTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
    }

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saunaminuten pro Woche")
                        .font(.headline)
                    Text("Letzte 8 Wochen · Ziel: 2–4×/Woche für Erholung & Herz-Kreislauf")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if wellnessStore.saunaSessions.isEmpty {
                Text("Starte den Live Sauna-Timer oder logge deine erste Session, um deinen Wochenverlauf zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                Chart(weeklyBars) { bar in
                    BarMark(
                        x: .value("Woche", bar.label),
                        y: .value("Minuten", bar.minutes)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sauna-Sessions (\(wellnessStore.saunaSessions.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if wellnessStore.saunaSessions.isEmpty {
                EmptyStateView(
                    systemImage: "flame.fill",
                    title: "Noch keine Sauna-Sessions",
                    message: "Tracke Saunagänge, Temperatur, Kaltduschen/Eisbad & Live-Puls."
                )
            } else {
                ForEach(wellnessStore.saunaSessions) { session in
                    saunaSessionCard(session)
                }
            }
        }
    }

    private func saunaSessionCard(_ session: SaunaSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: session.saunaType.systemImage)
                    .font(.title3)
                    .foregroundColor(session.saunaType.accentColor)
                    .frame(width: 42, height: 42)
                    .background(session.saunaType.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.saunaType.displayName)
                        .font(.headline)
                    Text(Formatters.workoutDate(session.startedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        activeSheet = .edit(session)
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

            HStack(spacing: 8) {
                metricPill(icon: "thermometer.medium", text: "\(session.temperatureCelsius) °C", color: .orange)
                metricPill(icon: "repeat", text: "\(session.rounds) \(session.rounds == 1 ? "Gang" : "Gänge")", color: .primary)
                metricPill(icon: "clock", text: "\(session.totalDurationMinutes) Min", color: .primary)

                if session.coldPlungeDone {
                    let coldLabel = session.coldPlungeMinutes > 0 ? "Kalt \(session.coldPlungeMinutes)m" : "Kalt"
                    metricPill(icon: "snowflake", text: coldLabel, color: .cyan)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                if let avg = session.avgHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text("Ø \(avg) bpm" + (session.maxHeartRate.map { " · Max \($0)" } ?? ""))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= session.feeling ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundColor(star <= session.feeling ? .yellow : .secondary.opacity(0.35))
                    }
                }

                Spacer()
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
            activeSheet = .edit(session)
        }
    }

    private func metricPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color == .primary ? Color(uiColor: .tertiarySystemFill) : color.opacity(0.14))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

// MARK: - Standalone Navigation Wrapper for Profile Link

struct SaunaNavigationView: View {
    var body: some View {
        SaunaOverviewView()
            .navigationTitle("Sauna & Kälte")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Live Sauna Timer (Heat Rounds + Cooldown + Live HR + Hydration)

struct LiveSaunaTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver

    enum Phase {
        case heat
        case cooldown
    }

    let onFinish: (SaunaSession, Int) -> Void

    @State private var saunaType: SaunaType = .finnish
    @State private var temperatureCelsius: Int = 90
    @State private var phase: Phase = .heat
    @State private var currentRound: Int = 1
    @State private var isRunning: Bool = true
    @State private var startedAt: Date = Date()

    @State private var currentPhaseSeconds: Int = 0
    @State private var totalHeatSeconds: Int = 0
    @State private var totalCooldownSeconds: Int = 0
    @State private var completedRoundDurations: [Int] = []

    @State private var coldPlungeDone: Bool = false
    @State private var addHydrationBonus: Bool = true
    @State private var feeling: Int = 4
    @State private var notes: String = ""

    @State private var hrSampleCount: Int = 0
    @State private var hrBpmSum: Int = 0
    @State private var hrMaxBpm: Int? = nil

    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var avgHeartRate: Int? {
        guard hrSampleCount > 0 else { return nil }
        return Int((Double(hrBpmSum) / Double(hrSampleCount)).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sauna type & temp bar
                    HStack(spacing: 10) {
                        Picker("Sauna", selection: $saunaType) {
                            ForEach(SaunaType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: saunaType) { newType in
                            temperatureCelsius = newType.defaultTemperatureCelsius
                        }

                        Spacer()

                        Stepper("\(temperatureCelsius) °C", value: $temperatureCelsius, in: 35...115, step: 5)
                            .fixedSize()
                    }
                    .strongCard(padding: 12)

                    // Main phase & live clock card
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: phase == .heat ? "flame.fill" : "snowflake")
                            Text(phase == .heat ? "GANG \(currentRound) · HITZEPHASE" : "ABKÜHLUNG / PAUSE")
                                .font(.caption)
                                .fontWeight(.heavy)
                                .tracking(0.8)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background((phase == .heat ? Color.orange : Color.cyan).opacity(0.18))
                        .foregroundColor(phase == .heat ? .orange : .cyan)
                        .clipShape(Capsule())

                        Text(formatClock(currentPhaseSeconds))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("Hitze gesamt")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatClock(totalHeatSeconds))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }

                            Divider().frame(height: 24)

                            VStack(spacing: 2) {
                                Text("Gänge")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(currentRound)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }

                            Divider().frame(height: 24)

                            VStack(spacing: 2) {
                                Text("Abkühlung")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatClock(totalCooldownSeconds))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                        }

                        if let bpm = heartRateReceiver.currentBPM {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .font(.caption)
                                    Text("\(bpm) bpm")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background((bpm >= 155 ? Color.red : Color.pink).opacity(0.16))
                                .foregroundColor(bpm >= 155 ? .red : .pink)
                                .clipShape(Capsule())

                                if bpm >= 155 {
                                    Text("Hoher Puls – ggf. kurz abkühlen")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .strongCard()

                    // Round & Phase controls
                    HStack(spacing: 10) {
                        Button {
                            isRunning.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                Text(isRunning ? "Pause" : "Weiter")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            switchPhase()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: phase == .heat ? "snowflake" : "flame.fill")
                                Text(phase == .heat ? "Abkühlen" : "Gang \(currentRound + 1)")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(phase == .heat ? .cyan : .orange)
                    }

                    if !completedRoundDurations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Absolvierte Gänge")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(Array(completedRoundDurations.enumerated()), id: \.offset) { idx, secs in
                                    Text("G\(idx + 1): \(formatClock(secs))")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.14))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strongCard(padding: 12)
                    }

                    // Options before saving
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $coldPlungeDone) {
                            HStack(spacing: 6) {
                                Image(systemName: "snowflake")
                                    .foregroundColor(.cyan)
                                Text("Kaltdusche / Tauchbecken genutzt")
                                    .font(.subheadline)
                            }
                        }
                        .tint(.cyan)

                        Toggle(isOn: $addHydrationBonus) {
                            HStack(spacing: 6) {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(.blue)
                                Text("+500 ml Wasser heute verbuchen")
                                    .font(.subheadline)
                            }
                        }
                        .tint(.blue)

                        HStack {
                            Text("Erholungsgefühl")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(1...5, id: \.self) { star in
                                    Button {
                                        feeling = star
                                    } label: {
                                        Image(systemName: star <= feeling ? "star.fill" : "star")
                                            .font(.title3)
                                            .foregroundColor(star <= feeling ? .yellow : .secondary.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        TextField("Notiz (z. B. Aufguss Eukalyptus, nach Push)", text: $notes)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                    .strongCard()

                    Button {
                        finishSession()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Sauna-Session speichern")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(totalHeatSeconds < 10)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Live Sauna-Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen", role: .destructive) {
                        dismiss()
                    }
                }
            }
            .onReceive(ticker) { _ in
                guard isRunning else { return }
                currentPhaseSeconds += 1
                if phase == .heat {
                    totalHeatSeconds += 1
                } else {
                    totalCooldownSeconds += 1
                }
            }
            .onReceive(heartRateReceiver.sampleSubject) { reading in
                guard isRunning else { return }
                hrSampleCount += 1
                hrBpmSum += reading.bpm
                hrMaxBpm = hrMaxBpm.map { max($0, reading.bpm) } ?? reading.bpm
            }
        }
    }

    private func switchPhase() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if phase == .heat {
            if currentPhaseSeconds > 0 {
                completedRoundDurations.append(currentPhaseSeconds)
            }
            phase = .cooldown
            currentPhaseSeconds = 0
        } else {
            currentRound += 1
            phase = .heat
            currentPhaseSeconds = 0
        }
    }

    private func formatClock(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func finishSession() {
        let heatMinutes = max(1, Int((Double(totalHeatSeconds) / 60.0).rounded()))
        let coldMins = coldPlungeDone ? max(0, totalCooldownSeconds / 60) : 0
        let roundsCompleted = max(1, phase == .heat && currentPhaseSeconds > 0 ? completedRoundDurations.count + 1 : completedRoundDurations.count)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let session = SaunaSession(
            startedAt: startedAt,
            saunaType: saunaType,
            temperatureCelsius: temperatureCelsius,
            rounds: roundsCompleted,
            totalDurationMinutes: heatMinutes,
            coldPlungeDone: coldPlungeDone,
            coldPlungeMinutes: coldMins,
            avgHeartRate: avgHeartRate,
            maxHeartRate: hrMaxBpm,
            feeling: feeling,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFinish(session, addHydrationBonus ? 500 : 0)
        dismiss()
    }
}

// MARK: - Manual Sauna Entry / Edit Form

struct SaunaSessionFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingSession: SaunaSession?
    let onSave: (SaunaSession, Int) -> Void

    @State private var startedAt: Date
    @State private var saunaType: SaunaType
    @State private var temperatureCelsius: Int
    @State private var rounds: Int
    @State private var totalDurationMinutes: Int
    @State private var coldPlungeDone: Bool
    @State private var coldPlungeMinutes: Int
    @State private var feeling: Int
    @State private var notes: String
    @State private var addHydrationBonus: Bool

    private let tempPresets = [55, 65, 80, 85, 90, 95]
    private let durationPresets = [15, 20, 30, 36, 45, 60]

    init(
        existingSession: SaunaSession? = nil,
        onSave: @escaping (SaunaSession, Int) -> Void
    ) {
        self.existingSession = existingSession
        self.onSave = onSave
        _startedAt = State(initialValue: existingSession?.startedAt ?? Date())
        _saunaType = State(initialValue: existingSession?.saunaType ?? .finnish)
        _temperatureCelsius = State(initialValue: existingSession?.temperatureCelsius ?? 90)
        _rounds = State(initialValue: existingSession?.rounds ?? 3)
        _totalDurationMinutes = State(initialValue: existingSession?.totalDurationMinutes ?? 36)
        _coldPlungeDone = State(initialValue: existingSession?.coldPlungeDone ?? true)
        _coldPlungeMinutes = State(initialValue: existingSession?.coldPlungeMinutes ?? 2)
        _feeling = State(initialValue: existingSession?.feeling ?? 4)
        _notes = State(initialValue: existingSession?.notes ?? "")
        _addHydrationBonus = State(initialValue: existingSession == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sauna-Typ & Datum") {
                    Picker("Art", selection: $saunaType) {
                        ForEach(SaunaType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .onChange(of: saunaType) { newType in
                        if existingSession == nil {
                            temperatureCelsius = newType.defaultTemperatureCelsius
                        }
                    }

                    DatePicker("Datum & Uhrzeit", selection: $startedAt)
                }

                Section("Temperatur, Gänge & Dauer") {
                    Stepper("Temperatur: \(temperatureCelsius) °C", value: $temperatureCelsius, in: 35...115, step: 5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tempPresets, id: \.self) { t in
                                Button {
                                    temperatureCelsius = t
                                } label: {
                                    Text("\(t) °C")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(temperatureCelsius == t ? Color.orange : Color(uiColor: .tertiarySystemFill))
                                        .foregroundColor(temperatureCelsius == t ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Stepper("Saunagänge: \(rounds)", value: $rounds, in: 1...8)

                    Stepper("Gesamt-Hitzezeit: \(totalDurationMinutes) Min", value: $totalDurationMinutes, in: 5...120, step: 5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(durationPresets, id: \.self) { mins in
                                Button {
                                    totalDurationMinutes = mins
                                } label: {
                                    Text("\(mins) Min")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(totalDurationMinutes == mins ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                        .foregroundColor(totalDurationMinutes == mins ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Abkühlung & Erholung") {
                    Toggle("Kaltdusche / Tauchbecken / Eisbad", isOn: $coldPlungeDone)
                        .tint(.cyan)

                    if coldPlungeDone {
                        Stepper("Kältezeit: \(coldPlungeMinutes) Min", value: $coldPlungeMinutes, in: 0...20)
                    }

                    HStack {
                        Text("Erholungsgefühl")
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    feeling = star
                                } label: {
                                    Image(systemName: star <= feeling ? "star.fill" : "star")
                                        .foregroundColor(star <= feeling ? .yellow : .secondary.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if existingSession == nil {
                        Toggle("+500 ml Wasser heute verbuchen", isOn: $addHydrationBonus)
                            .tint(.blue)
                    }
                }

                Section("Notizen (optional)") {
                    TextField("z. B. Aufguss Minze, super geschlafen danach", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingSession == nil ? "Sauna eintragen" : "Sauna bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let session = SaunaSession(
                            id: existingSession?.id ?? UUID().uuidString,
                            startedAt: startedAt,
                            saunaType: saunaType,
                            temperatureCelsius: temperatureCelsius,
                            rounds: rounds,
                            totalDurationMinutes: totalDurationMinutes,
                            coldPlungeDone: coldPlungeDone,
                            coldPlungeMinutes: coldPlungeDone ? coldPlungeMinutes : 0,
                            avgHeartRate: existingSession?.avgHeartRate,
                            maxHeartRate: existingSession?.maxHeartRate,
                            feeling: feeling,
                            notes: trimmed.isEmpty ? nil : trimmed
                        )
                        let waterBonus = (existingSession == nil && addHydrationBonus) ? 500 : 0
                        onSave(session, waterBonus)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
