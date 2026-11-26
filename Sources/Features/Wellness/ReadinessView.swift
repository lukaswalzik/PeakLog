import Charts
import SwiftUI

struct ReadinessView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore

    @State private var isShowingAddSheet: Bool = false

    private var last14Days: [ReadinessLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return wellnessStore.readinessLogs
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var averageReadiness: Int? {
        guard !last14Days.isEmpty else { return nil }
        let sum = last14Days.reduce(0) { $0 + $1.readinessScore }
        return sum / last14Days.count
    }

    private var averageSleep: Double? {
        guard !last14Days.isEmpty else { return nil }
        let sum = last14Days.reduce(0.0) { $0 + $1.sleepHours }
        return sum / Double(last14Days.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryRow
                chartCard
                logsSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Readiness & Schlaf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Check-in eintragen")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            ReadinessFormView { log in
                wellnessStore.saveReadiness(log)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ø Readiness (14T)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(averageReadiness.map { "\($0) / 100" } ?? "–")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.teal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .strongCard(padding: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ø Schlaf (14T)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(averageSleep.map { "\(String(format: "%.1f", $0)) Std." } ?? "–")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.indigo)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .strongCard(padding: 12)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Readiness-Verlauf (Oura / Tagesform)")
                .font(.headline)

            if last14Days.isEmpty {
                Text("Trage täglich deinen Oura Readiness-Score & deine Schlafdauer ein, um Erholung und Trainingsleistung im Blick zu behalten.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                Chart(last14Days) { log in
                    AreaMark(
                        x: .value("Datum", log.recordedAt),
                        y: .value("Score", log.readinessScore)
                    )
                    .foregroundStyle(Color.teal.opacity(0.18))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", log.recordedAt),
                        y: .value("Score", log.readinessScore)
                    )
                    .foregroundStyle(Color.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", log.recordedAt),
                        y: .value("Score", log.readinessScore)
                    )
                    .foregroundStyle(Color.teal)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check-ins (\(wellnessStore.readinessLogs.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if wellnessStore.readinessLogs.isEmpty {
                EmptyStateView(
                    systemImage: "bed.double.fill",
                    title: "Noch keine Check-ins",
                    message: "Logge heute deinen Oura Readiness-Score, Schlaf & Muskelkater.",
                    actionTitle: "Heutiges Check-in"
                ) {
                    isShowingAddSheet = true
                }
            } else {
                ForEach(wellnessStore.readinessLogs) { log in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Formatters.shortDate(log.recordedAt))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("Readiness \(log.readinessScore)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(scoreColor(log.readinessScore).opacity(0.16))
                                .foregroundColor(scoreColor(log.readinessScore))
                                .clipShape(Capsule())

                            Button(role: .destructive) {
                                wellnessStore.deleteReadiness(id: log.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }

                        HStack(spacing: 14) {
                            Label("\(String(format: "%.1f", log.sleepHours)) Std. Schlaf", systemImage: "moon.zzz.fill")
                            Label("Muskelkater \(log.soreness)/5", systemImage: "figure.walk")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if let notes = log.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 65 { return .orange }
        return .red
    }
}

private struct ReadinessFormView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ReadinessLog) -> Void

    @State private var date: Date = Date()
    @State private var readinessScore: Double = 82
    @State private var sleepHours: Double = 7.5
    @State private var soreness: Int = 2
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Datum")) {
                    DatePicker("Tag", selection: $date, displayedComponents: [.date])
                }

                Section(header: Text("Oura Readiness & Schlaf")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Readiness-Score")
                            Spacer()
                            Text("\(Int(readinessScore)) / 100")
                                .fontWeight(.bold)
                                .foregroundColor(.teal)
                        }
                        Slider(value: $readinessScore, in: 0...100, step: 1)
                    }

                    Stepper(value: $sleepHours, in: 2.0...14.0, step: 0.25) {
                        HStack {
                            Text("Schlafdauer")
                            Spacer()
                            Text("\(String(format: "%.2f", sleepHours)) Std.")
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Muskelkater", selection: $soreness) {
                        Text("1 · Frisch").tag(1)
                        Text("2 · Leicht").tag(2)
                        Text("3 · Spürbar").tag(3)
                        Text("4 · Stark").tag(4)
                        Text("5 · Sehr stark").tag(5)
                    }
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. HRV hoch, gut erholt", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Readiness Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let log = ReadinessLog(
                            dayKey: DayKeyFormatter.string(from: date),
                            recordedAt: date,
                            readinessScore: Int(readinessScore),
                            sleepHours: sleepHours,
                            soreness: soreness,
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                        )
                        onSave(log)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
