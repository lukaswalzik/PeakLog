import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProfileBackupView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var restTimerManager: RestTimerManager
    @EnvironmentObject private var bodyweightStore: BodyweightStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var gymStore: GymStore
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var liveActivityManager: WorkoutLiveActivityManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var progressSummary: UserProgressSummary {
        ProgressEngine.compute(
            workouts: historyStore.completedWorkouts,
            cardioSessions: cardioStore.sessions,
            bodyweightEntries: bodyweightStore.entries
        )
    }

    private var activeConnectionsSubtitle: String {
        var parts: [String] = []
        if healthKitService.isConnected { parts.append("Apple Health") }
        if OuraService.shared.isConnected { parts.append("Oura") }
        if heartRateReceiver.isEnabled { parts.append("UDP-Puls") }
        if parts.isEmpty {
            return "Apple Health, Oura Ring, Schlaf & Live-Puls"
        }
        return "Aktiv: \(parts.joined(separator: " · "))"
    }

    private var formattedTotalVolume: String {
        let vol = historyStore.totalVolumeKg
        if vol >= 1000 {
            return "\(Formatters.weight(vol / 1000.0)) t"
        }
        return "\(Formatters.weight(vol)) kg"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        ProfileStatTile(
                            title: "Workouts",
                            value: "\(historyStore.totalCompletedWorkouts)",
                            icon: "figure.strengthtraining.traditional",
                            color: themeManager.preset.accentColor
                        )
                        ProfileStatTile(
                            title: "Streak",
                            value: "\(progressSummary.weeklyStreak) Wo.",
                            icon: "flame.fill",
                            color: .orange
                        )
                        ProfileStatTile(
                            title: "Volumen",
                            value: formattedTotalVolume,
                            icon: "scalemass.fill",
                            color: .green
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("Körper & Fortschritt")) {
                    NavigationLink {
                        ProgressDashboardView()
                    } label: {
                        ProfileHubRow(
                            icon: "chart.line.uptrend.xyaxis",
                            color: .blue,
                            title: "Fortschritt & Trends",
                            subtitle: "Kraftsteigerung, Muskel-Heatmap & Gewichtsverlauf"
                        )
                    }

                    NavigationLink {
                        BodyweightView()
                    } label: {
                        ProfileHubRow(
                            icon: "figure.stand",
                            color: .purple,
                            title: "Körpergewicht & Fotos",
                            subtitle: bodyweightStore.latestEntry.map {
                                "Aktuell \(Formatters.weight($0.entry.weightKg)) kg · \(bodyweightStore.allPhotosTimeline.count) Fotos"
                            } ?? "Gewichtsverlauf & Vorher/Nachher-Slider"
                        )
                    }

                    NavigationLink {
                        BodyMeasurementsView()
                    } label: {
                        ProfileHubRow(
                            icon: "ruler",
                            color: .indigo,
                            title: "Körpermaße & KFA",
                            subtitle: wellnessStore.measurements.isEmpty
                                ? "Umfänge, US-Navy-KFA & FFMI"
                                : "\(wellnessStore.measurements.count) Messungen gespeichert"
                        )
                    }

                    NavigationLink {
                        SaunaNavigationView()
                    } label: {
                        ProfileHubRow(
                            icon: "flame.fill",
                            color: .orange,
                            title: "Sauna & Kälte",
                            subtitle: wellnessStore.saunaSessions.isEmpty
                                ? "Saunagänge, Temperatur, Eisbad & Live-Timer"
                                : "Diese Woche: \(wellnessStore.saunaSessionsThisWeek.count)× (\(wellnessStore.saunaMinutesThisWeek) Min)"
                        )
                    }
                }

                Section(header: Text("Motivation & KI")) {
                    NavigationLink {
                        MilestonesView()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(themeManager.preset.heroGradient)
                                    .frame(width: 40, height: 40)
                                Text("L\(progressSummary.level)")
                                    .font(.subheadline)
                                    .fontWeight(.heavy)
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Level \(progressSummary.level) · \(progressSummary.rankTitle)")
                                    .font(.headline)
                                ProgressView(value: progressSummary.levelProgress)
                                    .progressViewStyle(.linear)
                                    .tint(themeManager.preset.accentColor)
                                Text("\(progressSummary.unlockedCount)/\(progressSummary.milestones.count) Meilensteine · \(progressSummary.totalXP) XP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        WrappedSummaryView()
                    } label: {
                        ProfileHubRow(
                            icon: "trophy.fill",
                            color: .yellow,
                            title: "PeakLog Wrapped",
                            subtitle: "Monats- & Jahresrückblick, bewegte Tonnen & Highlights"
                        )
                    }

                    NavigationLink {
                        ProfileAIHubView()
                    } label: {
                        ProfileHubRow(
                            icon: "sparkles",
                            color: .orange,
                            title: "KI-Studio (Mistral)",
                            subtitle: MistralAIService.shared.isConfigured
                                ? "Aktiv · KI-Coach, Plan-Generator & Foto-Vision"
                                : "Optionaler KI-Coach & Plan-Generator einrichten",
                            subtitleColor: MistralAIService.shared.isConfigured ? .green : .secondary
                        )
                    }
                }

                Section(header: Text("Einstellungen")) {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        ProfileHubRow(
                            icon: "paintbrush.fill",
                            color: themeManager.preset.accentColor,
                            title: "Design & Erscheinungsbild",
                            subtitle: themeManager.shortSummary
                        )
                    }

                    NavigationLink {
                        ProfileConnectionsView()
                    } label: {
                        ProfileHubRow(
                            icon: "waveform.path.ecg",
                            color: .pink,
                            title: "Verbindungen & Sensoren",
                            subtitle: activeConnectionsSubtitle,
                            subtitleColor: (healthKitService.isConnected || OuraService.shared.isConnected) ? .green : .secondary
                        )
                    }

                    NavigationLink {
                        ProfileTrainingSettingsView()
                    } label: {
                        ProfileHubRow(
                            icon: "slider.horizontal.3",
                            color: .teal,
                            title: "Training & Benachrichtigungen",
                            subtitle: "Gyms, Pausentimer, Dynamic Island & Ziele"
                        )
                    }

                    NavigationLink {
                        ProfileDataBackupView()
                    } label: {
                        ProfileHubRow(
                            icon: "externaldrive.fill",
                            color: .gray,
                            title: "Daten, PRs & Backup",
                            subtitle: "Top 1RM-PRs, Strong CSV-Import & JSON-Backup"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profil")
            .onAppear {
                restTimerManager.refreshNotificationStatus()
            }
        }
    }
}

// MARK: - Sub-Page 1: KI-Studio Hub

private struct ProfileAIHubView: View {
    @ObservedObject private var mistral = MistralAIService.shared

    var body: some View {
        List {
            Section(header: Text("KI-Funktionen")) {
                NavigationLink {
                    AICoachView()
                } label: {
                    ProfileHubRow(
                        icon: "sparkles",
                        color: .orange,
                        title: "KI-Coach",
                        subtitle: "Datenbasierte Trainings- & Ernährungs-Analyse"
                    )
                }

                NavigationLink {
                    AIPlanGeneratorView()
                } label: {
                    ProfileHubRow(
                        icon: "wand.and.stars",
                        color: .purple,
                        title: "KI-Trainingsplan-Generator",
                        subtitle: "Plan erstellen & mit 1 Tap als Routinen speichern"
                    )
                }
            }

            Section(header: Text("Konfiguration")) {
                NavigationLink {
                    MistralSettingsView()
                } label: {
                    ProfileHubRow(
                        icon: "key.fill",
                        color: .teal,
                        title: "Mistral API-Einstellungen",
                        subtitle: mistral.isConfigured
                            ? "API-Key aktiv · \(mistral.selectedModel.displayName)"
                            : "API-Key aus console.mistral.ai hinterlegen",
                        subtitleColor: mistral.isConfigured ? .green : .secondary
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("KI-Studio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sub-Page 2: Verbindungen & Sensoren

private struct ProfileConnectionsView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var heartRateReceiver: HeartRateReceiver
    @EnvironmentObject private var healthKitService: HealthKitService

    var body: some View {
        List {
            Section(header: Text("Health & Wearables")) {
                NavigationLink {
                    AppleHealthView()
                } label: {
                    let subtitle: String = {
                        if healthKitService.isConnected {
                            if let bpm = heartRateReceiver.currentBPM,
                               heartRateReceiver.activeSource == .appleHealth {
                                return "Live · \(bpm) bpm · HealthKit aktiv"
                            }
                            return "Verbunden · Live-HF, Schritte, HRV & Workout-Export"
                        }
                        return "Live-Puls (AirPods/Watch), Gewicht & Workout-Sync"
                    }()

                    ProfileHubRow(
                        icon: "heart.text.square.fill",
                        color: .pink,
                        title: "Apple Health",
                        subtitle: subtitle,
                        subtitleColor: healthKitService.isConnected ? .green : .secondary
                    )
                }

                NavigationLink {
                    OuraIntegrationView()
                } label: {
                    let subtitle: String = {
                        if let latest = OuraService.shared.snapshot?.latestDay,
                           let r = latest.readinessScore {
                            return "Verbunden · Readiness \(r)/100\(latest.averageHRV.map { " · HRV \($0) ms" } ?? "")"
                        }
                        return "OAuth2 Sync für Readiness, Schlaf, HRV & Workouts"
                    }()

                    ProfileHubRow(
                        icon: "circle.circle.fill",
                        color: .cyan,
                        title: "Oura Ring (API v2)",
                        subtitle: subtitle,
                        subtitleColor: OuraService.shared.isConnected ? .green : .secondary
                    )
                }

                NavigationLink {
                    ReadinessView()
                } label: {
                    ProfileHubRow(
                        icon: "bed.double.fill",
                        color: .mint,
                        title: "Readiness & Schlaf",
                        subtitle: wellnessStore.latestReadiness.map {
                            "Zuletzt: Score \($0.readinessScore) · \(String(format: "%.1f", $0.sleepHours)) Std. Schlaf"
                        } ?? "Tagesform, Schlafdauer & Muskelkater"
                    )
                }
            }

            Section(header: Text("Lokale Herzfrequenz-Bridge")) {
                NavigationLink {
                    HeartRateReceiverSettingsView()
                } label: {
                    let subtitle: String = {
                        if let bpm = heartRateReceiver.currentBPM {
                            return "Live · \(bpm) bpm (\(heartRateReceiver.endpointDisplay))"
                        }
                        if let err = heartRateReceiver.lastError {
                            return err
                        }
                        if heartRateReceiver.isEnabled && heartRateReceiver.isListening {
                            return "Aktiv · wartet auf UDP-Puls (:\(heartRateReceiver.port))"
                        }
                        return "Deaktiviert · \(heartRateReceiver.endpointDisplay)"
                    }()

                    ProfileHubRow(
                        icon: "heart.circle.fill",
                        color: .red,
                        title: "Live-Herzfrequenz (UDP)",
                        subtitle: subtitle,
                        subtitleColor: heartRateReceiver.currentBPM != nil ? .green : (heartRateReceiver.lastError != nil ? .red : .secondary)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Verbindungen & Sensoren")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sub-Page 3: Training & Benachrichtigungen

private struct ProfileTrainingSettingsView: View {
    @EnvironmentObject private var gymStore: GymStore
    @EnvironmentObject private var cardioStore: CardioStore
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var restTimerManager: RestTimerManager
    @EnvironmentObject private var liveActivityManager: WorkoutLiveActivityManager

    private var notificationStatusText: String {
        switch restTimerManager.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Erlaubt"
        case .denied:
            return "Deaktiviert"
        case .notDetermined:
            return "Noch nicht gefragt"
        @unknown default:
            return "Unbekannt"
        }
    }

    var body: some View {
        List {
            Section(header: Text("Studios & Erinnerungen")) {
                NavigationLink {
                    GymsManagementView()
                } label: {
                    ProfileHubRow(
                        icon: "mappin.and.ellipse",
                        color: .teal,
                        title: "Meine Gyms",
                        subtitle: gymStore.gyms.isEmpty
                            ? "Studios & Homegym anlegen"
                            : "\(gymStore.gyms.count) Gyms · Aktiv: \(gymStore.selectedGym?.name ?? "Alle")"
                    )
                }

                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    ProfileHubRow(
                        icon: "bell.badge.fill",
                        color: .red,
                        title: "Erinnerungen",
                        subtitle: "Tägliche lokale Checks für Supplements, Wasser & Gym"
                    )
                }
            }

            Section(header: Text("Cardio & Wasser")) {
                Stepper(value: $cardioStore.maxHeartRate, in: 130...220) {
                    HStack {
                        Text("Maximale Herzfrequenz")
                        Spacer()
                        Text("\(cardioStore.maxHeartRate) bpm")
                            .foregroundColor(.secondary)
                    }
                }

                Stepper(value: $wellnessStore.dailyWaterGoalMl, in: 1000...7000, step: 250) {
                    HStack {
                        Text("Wasser-Tagesziel")
                        Spacer()
                        Text("\(wellnessStore.dailyWaterGoalMl) ml")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(
                header: Text("Pausentimer & Live Activity"),
                footer: Text("Zeigt während eines aktiven Workouts den Pausentimer-Countdown, Live-Puls und Satz-Fortschritt in der Dynamic Island und auf dem Sperrbildschirm.")
            ) {
                Toggle("Auto-Pause nach Satz-Abhaken", isOn: $restTimerManager.autoStartEnabled)
                Toggle("Dynamic Island & Live Activity", isOn: $liveActivityManager.isEnabled)

                if !liveActivityManager.areSystemActivitiesEnabled {
                    HStack {
                        Text("iOS Live-Aktivitäten")
                        Spacer()
                        Text("In Einstellungen deaktiviert")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if let liveErr = liveActivityManager.lastError {
                    Text(liveErr)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack {
                    Text("Benachrichtigungen")
                    Spacer()
                    Text(notificationStatusText)
                        .foregroundColor(.secondary)
                }

                if restTimerManager.notificationStatus == .notDetermined {
                    Button("Benachrichtigungen erlauben") {
                        restTimerManager.requestNotificationPermission()
                    }
                } else if restTimerManager.notificationStatus == .denied {
                    Button("In iOS-Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Training & Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            restTimerManager.refreshNotificationStatus()
        }
    }
}

// MARK: - Sub-Page 4: Daten, PRs & Backup

private struct ProfileDataBackupView: View {
    @EnvironmentObject private var historyStore: HistoryStore

    @State private var exportDocument: StrongTrackerBackupDocument? = nil
    @State private var exportIncludesPhotos: Bool = false
    @State private var isShowingExporter: Bool = false
    @State private var isShowingImporter: Bool = false
    @State private var pendingImportPayload: BackupPayload? = nil
    @State private var statusAlertTitle: String = ""
    @State private var statusAlertMessage: String = ""
    @State private var isShowingStatusAlert: Bool = false

    var body: some View {
        List {
            Section(
                header: Text("Import & Lokales Backup"),
                footer: Text("Der Strong-Import fügt Trainings aus einer Strong-CSV-Datei hinzu, ohne bestehende Daten zu überschreiben. Das JSON-Komplett-Backup bettet zusätzlich alle eigenen Übungs- und Fortschrittsfotos ein.")
            ) {
                NavigationLink {
                    StrongImportView()
                } label: {
                    Label("Aus Strong-App importieren (CSV)", systemImage: "arrow.down.doc.fill")
                }

                Button {
                    prepareExport(includePhotos: false)
                } label: {
                    Label("Daten als JSON exportieren", systemImage: "square.and.arrow.up")
                }

                Button {
                    prepareExport(includePhotos: true)
                } label: {
                    Label("Komplett-Backup inkl. Fotos", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    isShowingImporter = true
                } label: {
                    Label("JSON-Backup importieren", systemImage: "square.and.arrow.down")
                }
            }

            Section(header: Text("Top PRs (geschätztes 1RM)")) {
                if historyStore.exercisePRs.isEmpty {
                    Text("Noch keine PRs vorhanden. Logge Arbeitssätze mit Gewicht und Wiederholungen.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(historyStore.exercisePRs.prefix(15)) { pr in
                        NavigationLink {
                            ExerciseDetailView(exercise: pr.exercise)
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseThumbnailView(exercise: pr.exercise, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.exercise.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                    Text("Max. \(Formatters.weight(pr.bestWeightKg)) kg · \(Formatters.shortDate(pr.achievedAt))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Formatters.weight(pr.bestEstimated1RM)) kg")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(pr.exercise.muscleGroup.accentColor)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Daten, PRs & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupService.defaultFilename(includePhotos: exportIncludesPhotos)
        ) { result in
            switch result {
            case .success:
                showStatus(title: "Export erfolgreich", message: exportIncludesPhotos ? "Dein Komplett-Backup (inkl. Fotos) wurde gespeichert." : "Dein JSON-Backup wurde gespeichert.")
            case .failure(let error):
                showStatus(title: "Export fehlgeschlagen", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .alert(
            "Backup wiederherstellen?",
            isPresented: Binding(
                get: { pendingImportPayload != nil },
                set: { isPresented in
                    if !isPresented { pendingImportPayload = nil }
                }
            ),
            presenting: pendingImportPayload
        ) { payload in
            Button("Überschreiben & Importieren", role: .destructive) {
                performImport(payload)
                pendingImportPayload = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingImportPayload = nil
            }
        } message: { payload in
            let photoCount = payload.embeddedMedia?.count ?? 0
            Text("Alle aktuellen Daten werden durch das Backup ersetzt (\(payload.exercises.count) Übungen, \(payload.routines.count) Routinen, \(payload.workouts.count) Workouts, \(photoCount) Fotos).")
        }
        .alert(statusAlertTitle, isPresented: $isShowingStatusAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusAlertMessage)
        }
    }

    private func prepareExport(includePhotos: Bool) {
        do {
            let data = try BackupService.exportJSONData(from: historyStore.database, includePhotos: includePhotos)
            exportIncludesPhotos = includePhotos
            exportDocument = StrongTrackerBackupDocument(data: data)
            isShowingExporter = true
        } catch {
            showStatus(title: "Export fehlgeschlagen", message: error.localizedDescription)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showStatus(title: "Import fehlgeschlagen", message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let payload = try BackupService.decodePayload(from: data)
                pendingImportPayload = payload
            } catch {
                showStatus(
                    title: "Ungültige Backup-Datei",
                    message: "Die Datei konnte nicht als PeakLog-JSON gelesen werden: \(error.localizedDescription)"
                )
            }
        }
    }

    private func performImport(_ payload: BackupPayload) {
        do {
            let summary = try BackupService.importPayload(payload, into: historyStore.database)
            showStatus(
                title: "Import abgeschlossen",
                message: "\(summary.exerciseCount) Übungen, \(summary.routineCount) Routinen, \(summary.workoutCount) Workouts und \(summary.mediaCount) Fotos wurden wiederhergestellt."
            )
        } catch {
            showStatus(title: "Import fehlgeschlagen", message: error.localizedDescription)
        }
    }

    private func showStatus(title: String, message: String) {
        statusAlertTitle = title
        statusAlertMessage = message
        isShowingStatusAlert = true
    }
}

// MARK: - Reusable Clean Row & Stat Tile

private struct ProfileHubRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var subtitleColor: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProfileStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .padding(7)
                .background(color.opacity(0.14))
                .clipShape(Circle())

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
    }
}

struct ProfileBackupView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        ProfileBackupView()
            .environmentObject(HistoryStore(database: db))
            .environmentObject(RestTimerManager())
            .environmentObject(ExerciseStore(database: db))
            .environmentObject(BodyweightStore(database: db))
            .environmentObject(CardioStore(database: db))
            .environmentObject(GymStore(database: db))
            .environmentObject(WellnessStore(database: db))
            .environmentObject(HeartRateReceiver(autoStart: false))
            .environmentObject(HealthKitService(autoStart: false))
            .environmentObject(WorkoutLiveActivityManager())
            .environmentObject(ThemeManager())
    }
}
