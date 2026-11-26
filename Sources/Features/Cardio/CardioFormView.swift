import SwiftUI

struct CardioFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardioStore: CardioStore

    let existingSession: CardioSession?
    let onSave: (CardioSession) -> Void

    @State private var activityType: CardioActivityType
    @State private var startedAt: Date
    @State private var durationMinutes: Int
    @State private var distanceText: String
    @State private var avgHRText: String
    @State private var maxHRText: String
    @State private var caloriesText: String
    @State private var z1Minutes: Int
    @State private var z2Minutes: Int
    @State private var z3Minutes: Int
    @State private var z4Minutes: Int
    @State private var z5Minutes: Int
    @State private var notes: String

    init(
        existingSession: CardioSession? = nil,
        prefilledSession: CardioSession? = nil,
        onSave: @escaping (CardioSession) -> Void
    ) {
        self.existingSession = existingSession
        self.onSave = onSave

        let source = existingSession ?? prefilledSession
        _activityType = State(initialValue: source?.activityType ?? .running)
        _startedAt = State(initialValue: source?.startedAt ?? Date())
        _durationMinutes = State(initialValue: max(1, Int(round(Double(source?.durationSeconds ?? 1800) / 60.0))))
        _distanceText = State(initialValue: source?.distanceKm.map { Formatters.weight($0) } ?? "")
        _avgHRText = State(initialValue: source?.avgHeartRate.map { "\($0)" } ?? "")
        _maxHRText = State(initialValue: source?.maxHeartRate.map { "\($0)" } ?? "")
        _caloriesText = State(initialValue: source?.calories.map { "\($0)" } ?? "")
        _z1Minutes = State(initialValue: Int(round(Double(source?.zone1Seconds ?? 0) / 60.0)))
        _z2Minutes = State(initialValue: Int(round(Double(source?.zone2Seconds ?? 0) / 60.0)))
        _z3Minutes = State(initialValue: Int(round(Double(source?.zone3Seconds ?? 0) / 60.0)))
        _z4Minutes = State(initialValue: Int(round(Double(source?.zone4Seconds ?? 0) / 60.0)))
        _z5Minutes = State(initialValue: Int(round(Double(source?.zone5Seconds ?? 0) / 60.0)))
        _notes = State(initialValue: source?.notes ?? "")
    }

    private var totalZoneMinutes: Int {
        z1Minutes + z2Minutes + z3Minutes + z4Minutes + z5Minutes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Einheit")) {
                    Picker("Sportart", selection: $activityType) {
                        ForEach(CardioActivityType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }

                    DatePicker("Datum", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])

                    Stepper(value: $durationMinutes, in: 1...360) {
                        HStack {
                            Text("Gesamtdauer")
                            Spacer()
                            Text("\(durationMinutes) min")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Messwerte (optional)")) {
                    HStack {
                        Text("Distanz")
                        Spacer()
                        TextField("z. B. 5,2", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("km")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Ø Herzfrequenz")
                        Spacer()
                        TextField("z. B. 142", text: $avgHRText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Max. Herzfrequenz")
                        Spacer()
                        TextField("z. B. 176", text: $maxHRText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Kalorien")
                        Spacer()
                        TextField("z. B. 340", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                }

                Section(
                    header: HStack {
                        Text("HF-Trainingszonen (Max-HF \(cardioStore.maxHeartRate))")
                        Spacer()
                        if totalZoneMinutes > 0 {
                            Text("\(totalZoneMinutes) min")
                                .foregroundColor(.accentColor)
                        }
                    },
                    footer: Text("Trage hier die Minuten pro Herzfrequenz-Zone ein (z. B. aus deinem Oura Ring oder vom Gerät).")
                ) {
                    zoneStepper(zone: .z1, minutes: $z1Minutes)
                    zoneStepper(zone: .z2, minutes: $z2Minutes)
                    zoneStepper(zone: .z3, minutes: $z3Minutes)
                    zoneStepper(zone: .z4, minutes: $z4Minutes)
                    zoneStepper(zone: .z5, minutes: $z5Minutes)

                    if totalZoneMinutes > 0 && totalZoneMinutes != durationMinutes {
                        Button("Gesamtdauer auf \(totalZoneMinutes) min setzen") {
                            durationMinutes = totalZoneMinutes
                        }
                        .font(.subheadline)
                    }
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. lockerer Zone-2-Lauf, Oura-Daten", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingSession == nil ? "Cardio eintragen" : "Cardio bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func zoneStepper(zone: HeartRateZone, minutes: Binding<Int>) -> some View {
        Stepper(value: minutes, in: 0...300) {
            HStack(spacing: 8) {
                Circle()
                    .fill(zone.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(zone.title)
                        .font(.subheadline)
                    Text(zone.bpmRangeText(maxHR: cardioStore.maxHeartRate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(minutes.wrappedValue) min")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(minutes.wrappedValue > 0 ? zone.color : .secondary)
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = CardioSession(
            id: existingSession?.id ?? UUID().uuidString,
            activityType: activityType,
            startedAt: startedAt,
            durationSeconds: max(60, durationMinutes * 60),
            distanceKm: Formatters.parseWeight(distanceText),
            avgHeartRate: Int(avgHRText.filter { $0.isNumber }),
            maxHeartRate: Int(maxHRText.filter { $0.isNumber }),
            calories: Int(caloriesText.filter { $0.isNumber }),
            zone1Seconds: z1Minutes * 60,
            zone2Seconds: z2Minutes * 60,
            zone3Seconds: z3Minutes * 60,
            zone4Seconds: z4Minutes * 60,
            zone5Seconds: z5Minutes * 60,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        onSave(session)
        dismiss()
    }
}
