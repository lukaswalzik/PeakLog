import SwiftUI
import UniformTypeIdentifiers

struct StrongImportView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var gymStore: GymStore

    @State private var selectedFileData: Data? = nil
    @State private var selectedFileName: String? = nil
    @State private var weightUnitMode: StrongWeightUnitMode = .auto
    @State private var skipDuplicates: Bool = true
    @State private var selectedGymId: String? = nil
    @State private var preview: StrongImportPreview? = nil
    @State private var isShowingFileImporter: Bool = false
    @State private var isImporting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var importResult: StrongImportResult? = nil

    private var workoutsToImportCount: Int {
        guard let preview = preview else { return 0 }
        return skipDuplicates ? preview.newWorkoutCount : preview.workouts.count
    }

    var body: some View {
        List {
            Section(header: Text("So funktioniert der Import")) {
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: "1", text: "In der Strong-App: Profil → Einstellungen → „Strong-Daten exportieren“.")
                    stepRow(number: "2", text: "Die erzeugte CSV-Datei (z. B. strong.csv) in der Dateien-App sichern.")
                    stepRow(number: "3", text: "CSV hier auswählen, Vorschau prüfen und sicher zusammenführen.")
                }
                .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Bestehende Trainings, Routinen, Ernährung und Fotos in StrongTracker bleiben vollständig erhalten.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Strong CSV-Datei")) {
                Button {
                    isShowingFileImporter = true
                } label: {
                    HStack {
                        Label(
                            selectedFileName == nil ? "Strong CSV-Datei auswählen" : "Andere CSV-Datei wählen",
                            systemImage: "doc.badge.plus"
                        )
                        .fontWeight(.semibold)
                        Spacer()
                        if let name = selectedFileName {
                            Text(name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            if let result = importResult {
                Section(header: Text("Import abgeschlossen")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(result.importedWorkouts) Workouts importiert", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("\(result.importedSets) Sätze · \(result.createdExercises) neue Übungen angelegt" + (result.skippedDuplicates > 0 ? " · \(result.skippedDuplicates) Duplikate übersprungen" : ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let preview = preview {
                Section(header: Text("Vorschau")) {
                    infoRow(label: "Gefundene Workouts", value: "\(preview.workouts.count)")
                    if preview.duplicateWorkoutCount > 0 {
                        infoRow(
                            label: "Bereits vorhanden (Duplikate)",
                            value: "\(preview.duplicateWorkoutCount)",
                            valueColor: .orange
                        )
                    }
                    infoRow(label: "Sätze gesamt", value: "\(preview.totalSetCount)")
                    if let first = preview.earliestDate, let last = preview.latestDate {
                        infoRow(
                            label: "Zeitraum",
                            value: "\(Formatters.shortDate(first)) – \(Formatters.shortDate(last))"
                        )
                    }
                    infoRow(
                        label: "Übungen",
                        value: "\(preview.uniqueExerciseCount) (\(preview.matchedExerciseCount) erkannt, \(preview.newExerciseNames.count) neu)"
                    )
                    infoRow(label: "CSV-Format", value: "\(preview.detectedDelimiter) · \(preview.detectedUnitHint)")
                }

                Section(header: Text("Import-Optionen")) {
                    Picker("Gewichtseinheit", selection: $weightUnitMode) {
                        ForEach(StrongWeightUnitMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Toggle("Duplikate überspringen", isOn: $skipDuplicates)

                    if !gymStore.gyms.isEmpty {
                        Picker("Gym zuordnen", selection: $selectedGymId) {
                            Text("Kein Gym").tag(String?.none)
                            ForEach(gymStore.gyms) { gym in
                                Text(gym.name).tag(Optional(gym.id))
                            }
                        }
                    }
                }

                Section(header: Text("Letzte Workouts in der Datei")) {
                    ForEach(preview.workouts.prefix(5)) { workout in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(workout.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Spacer()
                                Text(Formatters.shortDate(workout.startedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(workout.exercises.count) Übungen · \(workout.totalSets) Sätze · \(max(1, workout.durationSeconds / 60)) Min.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    if preview.workouts.count > 5 {
                        Text("+ \(preview.workouts.count - 5) weitere Workouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !preview.newExerciseNames.isEmpty {
                    Section(
                        header: Text("Neue Übungen (\(preview.newExerciseNames.count))"),
                        footer: Text("Bekannte Strong-Übungen werden automatisch deinen bestehenden StrongTracker-Übungen (inkl. Illustrationen) zugeordnet. Alle weiteren werden automatisch mit passender Muskelgruppe & Equipment angelegt.")
                    ) {
                        ForEach(preview.newExerciseNames.prefix(8), id: \.self) { name in
                            Text(name)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        if preview.newExerciseNames.count > 8 {
                            Text("+ \(preview.newExerciseNames.count - 8) weitere Übungen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        runImport(preview)
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Importiere…")
                                    .fontWeight(.semibold)
                            } else {
                                Label(
                                    workoutsToImportCount == 0
                                        ? "Alle Workouts bereits vorhanden"
                                        : "\(workoutsToImportCount) Workouts jetzt importieren",
                                    systemImage: "square.and.arrow.down.fill"
                                )
                                .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isImporting || workoutsToImportCount == 0)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Strong-App Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .onChange(of: weightUnitMode) { _ in
            reparseSelectedFile()
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func infoRow(label: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        importResult = nil
        switch result {
        case .failure(let error):
            errorMessage = "Datei konnte nicht geöffnet werden: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                selectedFileData = data
                selectedFileName = url.lastPathComponent
                reparseSelectedFile()
            } catch {
                errorMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func reparseSelectedFile() {
        guard let data = selectedFileData else { return }
        errorMessage = nil
        do {
            preview = try StrongCSVImportService.parseAndPreview(
                data: data,
                weightUnitMode: weightUnitMode,
                database: historyStore.database
            )
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func runImport(_ preview: StrongImportPreview) {
        isImporting = true
        errorMessage = nil
        do {
            let result = try StrongCSVImportService.performImport(
                preview: preview,
                skipDuplicates: skipDuplicates,
                gymId: selectedGymId,
                into: historyStore.database
            )
            importResult = result
            // Refresh preview so duplicate counter reflects newly imported workouts
            reparseSelectedFile()
        } catch {
            errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
        isImporting = false
    }
}
