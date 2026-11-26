import Charts
import SwiftUI
import UIKit

struct OuraIntegrationView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var cardioStore: CardioStore
    @ObservedObject private var oura = OuraService.shared

    enum ChartMetric: String, CaseIterable, Identifiable {
        case readiness = "Readiness"
        case hrv = "HRV (ms)"
        case sleep = "Schlaf (h)"
        case steps = "Schritte"

        var id: String { rawValue }
    }

    @State private var selectedMetric: ChartMetric = .readiness
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSetupExpanded: Bool = false
    @State private var copiedRedirectFeedback: Bool = false
    @State private var importedWorkoutIds: Set<String> = []

    private var needsDeloadHint: Bool {
        guard let days = oura.snapshot?.days else { return false }
        let lastThree = days.suffix(3).compactMap { $0.readinessScore }
        return lastThree.count == 3 && lastThree.allSatisfy { $0 < 65 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionStatusCard

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let status = oura.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if needsDeloadHint {
                    HStack(spacing: 10) {
                        Image(systemName: "battery.25")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recovery- & Deload-Hinweis")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("Dein Oura Readiness Score lag 3 Tage in Folge unter 65. Überlege dir heute eine leichtere Deload-Einheit (−20 %) oder einen Ruhetag.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }

                if let snapshot = oura.snapshot, let latest = snapshot.latestDay {
                    latestMetricsCard(latest, syncedAt: snapshot.syncedAt)
                    trendsChartCard(snapshot.days)
                    if !snapshot.workouts.isEmpty {
                        ouraWorkoutsCard(snapshot.workouts)
                    }
                }

                oauthSetupCard
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Oura Ring (API v2)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !oura.isConnected {
                showSetupExpanded = true
            }
        }
    }

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "circle.circle.fill")
                        .font(.title2)
                        .foregroundColor(oura.isConnected ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(oura.isConnected ? "Mit Oura verbunden" : "Nicht verbunden")
                            .font(.headline)
                        if let synced = oura.snapshot?.syncedAt {
                            Text("Letzter Sync: \(Formatters.workoutDate(synced))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("OAuth2 · Readiness, Schlaf, HRV, Schritte & Workouts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                if oura.isConnected {
                    Button {
                        runSync()
                    } label: {
                        HStack {
                            if oura.isSyncing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(oura.isSyncing ? "Synchronisiere..." : "Jetzt synchronisieren")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(oura.isSyncing)

                    Button(role: .destructive) {
                        oura.disconnect()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        runOAuthConnect()
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "link.circle.fill")
                            }
                            Text(isConnecting ? "Verbinde..." : "Mit Oura verbinden (OAuth2)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting || !oura.hasClientCredentials)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func latestMetricsCard(_ day: OuraDailySummary, syncedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aktuelle Oura-Werte (\(day.day))")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricTile(
                    title: "Readiness",
                    value: day.readinessScore.map { "\($0)/100" } ?? "–",
                    icon: "bolt.heart.fill",
                    color: (day.readinessScore ?? 80) >= 75 ? .green : .orange
                )
                metricTile(
                    title: "Schlaf",
                    value: day.sleepHours.map { String(format: "%.1f Std.", $0) } ?? (day.sleepScore.map { "\($0)/100" } ?? "–"),
                    icon: "bed.double.fill",
                    color: .indigo
                )
                metricTile(
                    title: "Ø HRV",
                    value: day.averageHRV.map { "\($0) ms" } ?? "–",
                    icon: "waveform.path.ecg",
                    color: .purple
                )
                metricTile(
                    title: "Ruhepuls",
                    value: day.lowestHeartRate.map { "\($0) bpm" } ?? "–",
                    icon: "heart.fill",
                    color: .red
                )
                metricTile(
                    title: "Schritte",
                    value: day.steps.map { "\($0)" } ?? "–",
                    icon: "figure.walk",
                    color: .blue
                )
                metricTile(
                    title: "Aktiv-Kalorien",
                    value: day.activeCalories.map { "\($0) kcal" } ?? "–",
                    icon: "flame.fill",
                    color: .orange
                )
                if let stress = day.stressSummary {
                    metricTile(
                        title: "Stress-Status",
                        value: localizedStress(stress),
                        icon: "brain.head.profile",
                        color: .teal
                    )
                }
                if let spo2 = day.spo2Average {
                    metricTile(
                        title: "SpO2",
                        value: String(format: "%.1f %%", spo2),
                        icon: "lungs.fill",
                        color: .cyan
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func metricTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func trendsChartCard(_ days: [OuraDailySummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("14-Tage-Verlauf")
                .font(.headline)

            Picker("Metrik", selection: $selectedMetric) {
                ForEach(ChartMetric.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            let points: [(id: String, date: Date, val: Double)] = days.compactMap { d in
                let val: Double?
                switch selectedMetric {
                case .readiness: val = d.readinessScore.map { Double($0) }
                case .hrv: val = d.averageHRV.map { Double($0) }
                case .sleep: val = d.sleepHours
                case .steps: val = d.steps.map { Double($0) }
                }
                guard let v = val else { return nil }
                return (d.day, d.date, v)
            }

            if points.isEmpty {
                Text("Für diese Metrik liegen in den letzten 14 Tagen noch keine Daten vor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart(points, id: \.id) { pt in
                    if selectedMetric == .steps {
                        BarMark(
                            x: .value("Tag", pt.date, unit: .day),
                            y: .value("Wert", pt.val)
                        )
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .cornerRadius(4)
                    } else {
                        LineMark(
                            x: .value("Tag", pt.date),
                            y: .value("Wert", pt.val)
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Tag", pt.date),
                            y: .value("Wert", pt.val)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func ouraWorkoutsCard(_ workouts: [OuraWorkoutRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Oura Workouts (14 Tage)")
                    .font(.headline)
                Spacer()
                Button("Alle importieren") {
                    for w in workouts {
                        cardioStore.save(w.toCardioSession())
                        importedWorkoutIds.insert(w.id)
                    }
                }
                .font(.caption)
                .fontWeight(.semibold)
            }

            ForEach(workouts.prefix(8)) { w in
                let isImported = importedWorkoutIds.contains(w.id) ||
                    cardioStore.sessions.contains(where: { $0.id == "oura-\(w.id)" })
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(w.day) · \(w.durationSeconds / 60) Min.\(w.calories.map { " · \(Int(round($0))) kcal" } ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        cardioStore.save(w.toCardioSession())
                        importedWorkoutIds.insert(w.id)
                    } label: {
                        Text(isImported ? "Importiert" : "In Cardio")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(isImported ? .green : .accentColor)
                    .disabled(isImported)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var oauthSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation {
                    showSetupExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("OAuth2 App-Zugangsdaten", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showSetupExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showSetupExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Öffne **cloud.ouraring.com/oauth/applications** und erstelle eine neue kostenlose App (bis 10 Nutzer sofort aktiv).")
                    Text("2. Trage als **Redirect URI** exakt diese Adresse ein:")
                    HStack {
                        Text(OuraService.redirectURI)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .padding(6)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button {
                            UIPasteboard.general.string = OuraService.redirectURI
                            copiedRedirectFeedback = true
                        } label: {
                            Label(copiedRedirectFeedback ? "Kopiert" : "Kopieren", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text("3. Kopiere **Client ID** und **Client Secret** hier rein und tippe oben auf „Mit Oura verbinden“.")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                TextField("Oura Client ID", text: $oura.clientId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Oura Client Secret", text: $oura.clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private func localizedStress(_ raw: String) -> String {
        switch raw.lowercased() {
        case "restored": return "Erholt"
        case "normal": return "Normal"
        case "stressful": return "Gestresst"
        default: return raw.capitalized
        }
    }

    private func runOAuthConnect() {
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await oura.connectOAuth()
                _ = try await oura.syncAll(days: 14, wellnessStore: wellnessStore)
                await MainActor.run {
                    isConnecting = false
                    showSetupExpanded = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func runSync() {
        errorMessage = nil
        Task {
            do {
                _ = try await oura.syncAll(days: 14, wellnessStore: wellnessStore)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
