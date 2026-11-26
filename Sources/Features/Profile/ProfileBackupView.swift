import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProfileBackupView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var restTimerManager: RestTimerManager

    @State private var exportDocument: StrongTrackerBackupDocument? = nil
    @State private var isShowingExporter: Bool = false
    @State private var isShowingImporter: Bool = false
    @State private var pendingImportPayload: BackupPayload? = nil
    @State private var statusAlertTitle: String = ""
    @State private var statusAlertMessage: String = ""
    @State private var isShowingStatusAlert: Bool = false

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
                Section(header: Text("Gesamt-Übersicht")) {
                    HStack {
                        Label("Abgeschlossene Workouts", systemImage: "figure.strengthtraining.traditional")
                        Spacer()
                        Text("\(historyStore.totalCompletedWorkouts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Abgeschlossene Sätze", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(historyStore.totalCompletedSets)")
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Gesamtvolumen", systemImage: "scalemass")
                        Spacer()
                        Text("\(Formatters.weight(historyStore.totalVolumeKg)) kg")
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
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
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pr.exercise.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Max. \(Formatters.weight(pr.bestWeightKg)) kg · \(Formatters.shortDate(pr.achievedAt))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Formatters.weight(pr.bestEstimated1RM)) kg")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.vertical, 2)
                            }
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
                    header: Text("Lokales Backup (JSON)"),
                    footer: Text("Exportiert alle Übungen, Routinen und Workouts als lokale JSON-Datei. Beim Import werden die aktuellen Daten atomar durch das Backup ersetzt.")
                ) {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Daten als JSON exportieren", systemImage: "square.and.arrow.up")
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
                defaultFilename: BackupService.defaultFilename()
            ) { result in
                switch result {
                case .success:
                    showStatus(title: "Export erfolgreich", message: "Dein JSON-Backup wurde gespeichert.")
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
                Text("Alle aktuellen Daten werden durch das Backup ersetzt (\(payload.exercises.count) Übungen, \(payload.routines.count) Routinen, \(payload.workouts.count) Workouts).")
            }
            .alert(statusAlertTitle, isPresented: $isShowingStatusAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusAlertMessage)
            }
        }
    }

    private func prepareExport() {
        do {
            let data = try BackupService.exportJSONData(from: historyStore.database)
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
                message: "\(summary.exerciseCount) Übungen, \(summary.routineCount) Routinen und \(summary.workoutCount) Workouts wurden wiederhergestellt."
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

struct ProfileBackupView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        ProfileBackupView()
            .environmentObject(HistoryStore(database: db))
            .environmentObject(RestTimerManager())
            .environmentObject(ExerciseStore(database: db))
    }
}
