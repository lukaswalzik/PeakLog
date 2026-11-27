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

    @State private var exportDocument: StrongTrackerBackupDocument? = nil
    @State private var exportIncludesPhotos: Bool = false
    @State private var isShowingExporter: Bool = false
    @State private var isShowingImporter: Bool = false
    @State private var pendingImportPayload: BackupPayload? = nil
    @State private var statusAlertTitle: String = ""
    @State private var statusAlertMessage: String = ""
    @State private var isShowingStatusAlert: Bool = false

    private var progressSummary: UserProgressSummary {
        ProgressEngine.compute(
            workouts: historyStore.completedWorkouts,
            cardioSessions: cardioStore.sessions,
            bodyweightEntries: bodyweightStore.entries
        )
    }

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
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        ProfileStatTile(
                            title: "Workouts",
                            value: "\(historyStore.totalCompletedWorkouts)",
                            icon: "figure.strengthtraining.traditional",
                            color: .blue
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

                Section(header: Text("KI-Assistent (Mistral)")) {
                    NavigationLink {
                        AICoachView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .frame(width: 40, height: 40)
                                .background(Color.orange.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("KI-Coach (Mistral)")
                                    .font(.headline)
                                Text("Datenbasierte Trainings- & Ernährungs-Analyse")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        AIPlanGeneratorView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title3)
                                .foregroundColor(.purple)
                                .frame(width: 40, height: 40)
                                .background(Color.purple.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("KI-Trainingsplan-Generator")
                                    .font(.headline)
                                Text("Plan erstellen & mit 1 Tap als Routinen speichern")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        MistralSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.title3)
                                .foregroundColor(.teal)
                                .frame(width: 40, height: 40)
                                .background(Color.teal.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mistral KI-Einstellungen")
                                    .font(.headline)
                                Text(MistralAIService.shared.isConfigured ? "API-Key aktiv · \(MistralAIService.shared.selectedModel.displayName)" : "API-Key aus console.mistral.ai hinterlegen")
                                    .font(.caption)
                                    .foregroundColor(MistralAIService.shared.isConfigured ? .green : .secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Fortschritt & Motivation")) {
                    NavigationLink {
                        WrappedSummaryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .font(.title3)
                                .foregroundColor(.yellow)
                                .frame(width: 40, height: 40)
                                .background(Color.yellow.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("StrongTracker Wrapped")
                                    .font(.headline)
                                Text("Monats- & Jahresrückblick, bewegte Tonnen & Highlights")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        OuraIntegrationView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.circle.fill")
                                .font(.title3)
                                .foregroundColor(.cyan)
                                .frame(width: 40, height: 40)
                                .background(Color.cyan.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Oura Ring (API v2)")
                                    .font(.headline)
                                if let latest = OuraService.shared.snapshot?.latestDay,
                                   let r = latest.readinessScore {
                                    Text("Verbunden · Readiness \(r)/100\(latest.averageHRV.map { " · HRV \($0) ms" } ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("OAuth2 Sync für Readiness, Schlaf, HRV & Workouts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        HeartRateReceiverSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.circle.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                                .frame(width: 40, height: 40)
                                .background(Color.red.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live-Herzfrequenz (UDP)")
                                    .font(.headline)
                                if let bpm = heartRateReceiver.currentBPM {
                                    Text("Live · \(bpm) bpm (\(heartRateReceiver.endpointDisplay))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else if let err = heartRateReceiver.lastError {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .lineLimit(1)
                                } else if heartRateReceiver.isEnabled && heartRateReceiver.isListening {
                                    Text("Aktiv · wartet auf airpods-hf-bridge (:\(heartRateReceiver.port))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Deaktiviert · \(heartRateReceiver.endpointDisplay)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        RemindersSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                                .frame(width: 40, height: 40)
                                .background(Color.red.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Erinnerungen")
                                    .font(.headline)
                                Text("Tägliche lokale Checks für Supplements, Wasser & Gym")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    NavigationLink {
                        ProgressDashboardView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fortschritt & Trends")
                                    .font(.headline)
                                Text("Kraftsteigerung & Gewichtsverlauf im Graph")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        MilestonesView()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.heroGradient)
                                    .frame(width: 40, height: 40)
                                Text("L\(progressSummary.level)")
                                    .font(.subheadline)
                                    .fontWeight(.heavy)
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Level \(progressSummary.level) · \(progressSummary.rankTitle)")
                                        .font(.headline)
                                }
                                ProgressView(value: progressSummary.levelProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                Text("\(progressSummary.unlockedCount)/\(progressSummary.milestones.count) Meilensteine · \(progressSummary.totalXP) XP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        BodyweightView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.stand")
                                .font(.title3)
                                .foregroundColor(.purple)
                                .frame(width: 40, height: 40)
                                .background(Color.purple.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Körpergewicht & Fotos")
                                    .font(.headline)
                                if let latest = bodyweightStore.latestEntry {
                                    Text("Aktuell \(Formatters.weight(latest.entry.weightKg)) kg · \(bodyweightStore.allPhotosTimeline.count) Fotos")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Gewichtsverlauf & Vorher/Nachher-Fotos")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        BodyMeasurementsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "ruler")
                                .font(.title3)
                                .foregroundColor(.indigo)
                                .frame(width: 40, height: 40)
                                .background(Color.indigo.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Körpermaße")
                                    .font(.headline)
                                Text(wellnessStore.measurements.isEmpty ? "Brust, Taille, Arm & Bein in cm" : "\(wellnessStore.measurements.count) Messungen gespeichert")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        ReadinessView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bed.double.fill")
                                .font(.title3)
                                .foregroundColor(.mint)
                                .frame(width: 40, height: 40)
                                .background(Color.mint.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Readiness & Schlaf (Oura)")
                                    .font(.headline)
                                if let latest = wellnessStore.latestReadiness {
                                    Text("Zuletzt: Score \(latest.readinessScore) · \(String(format: "%.1f", latest.sleepHours)) Std. Schlaf")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Tagesform, Schlafdauer & Muskelkater")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        GymsManagementView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title3)
                                .foregroundColor(.teal)
                                .frame(width: 40, height: 40)
                                .background(Color.teal.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Meine Gyms")
                                    .font(.headline)
                                Text(gymStore.gyms.isEmpty ? "Studios & Homegym anlegen" : "\(gymStore.gyms.count) Gyms · Aktiv: \(gymStore.selectedGym?.name ?? "Alle")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Top PRs (geschätztes 1RM)")) {
                    if historyStore.exercisePRs.isEmpty {
                        Text("Noch keine PRs vorhanden. Logge Arbeitssätze mit Gewicht und Wiederholungen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(historyStore.exercisePRs.prefix(10)) { pr in
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

                Section(header: Text("Pausentimer")) {
                    Toggle("Auto-Pause nach Satz-Abhaken", isOn: $restTimerManager.autoStartEnabled)

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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profil")
            .onAppear {
                restTimerManager.refreshNotificationStatus()
            }
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
                    message: "Die Datei konnte nicht als StrongTracker-JSON gelesen werden: \(error.localizedDescription)"
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

    private var formattedTotalVolume: String {
        let vol = historyStore.totalVolumeKg
        if vol >= 1000 {
            return "\(Formatters.weight(vol / 1000.0)) t"
        }
        return "\(Formatters.weight(vol)) kg"
    }

    private func showStatus(title: String, message: String) {
        statusAlertTitle = title
        statusAlertMessage = message
        isShowingStatusAlert = true
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
    }
}
