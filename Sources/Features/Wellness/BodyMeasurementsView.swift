import Charts
import SwiftUI

struct BodyMeasurementsView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore

    enum Metric: String, CaseIterable, Identifiable {
        case waist = "Taille"
        case chest = "Brust"
        case arm = "Oberarm"
        case thigh = "Oberschenkel"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .waist: return .green
            case .chest: return .blue
            case .arm: return .purple
            case .thigh: return .orange
            }
        }

        func value(from m: BodyMeasurement) -> Double? {
            switch self {
            case .waist: return m.waistCm
            case .chest: return m.chestCm
            case .arm: return m.armCm
            case .thigh: return m.thighCm
            }
        }
    }

    @State private var selectedMetric: Metric = .waist
    @State private var isShowingAddSheet: Bool = false

    private var chartPoints: [(id: String, date: Date, value: Double)] {
        wellnessStore.measurements
            .reversed()
            .compactMap { m in
                guard let val = selectedMetric.value(from: m) else { return nil }
                return (m.id, m.recordedAt, val)
            }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                chartCard
                entriesSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Körpermaße")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Maße eintragen")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            BodyMeasurementFormView { measurement in
                wellnessStore.saveMeasurement(measurement)
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Bereich", selection: $selectedMetric) {
                ForEach(Metric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            if chartPoints.isEmpty {
                Text("Trage deine ersten Umfang-Messungen (cm) ein, um deine Form-Entwicklung im Diagramm zu verfolgen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart(chartPoints, id: \.id) { point in
                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("cm", point.value)
                    )
                    .foregroundStyle(selectedMetric.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("cm", point.value)
                    )
                    .foregroundStyle(selectedMetric.color)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Messungen (\(wellnessStore.measurements.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if wellnessStore.measurements.isEmpty {
                EmptyStateView(
                    systemImage: "ruler",
                    title: "Noch keine Messungen",
                    message: "Halte Brust, Taille, Oberarm & Oberschenkel fest – ideal bei Recomp & Muskelaufbau.",
                    actionTitle: "Erste Messung eintragen"
                ) {
                    isShowingAddSheet = true
                }
            } else {
                ForEach(wellnessStore.measurements) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Formatters.workoutDate(item.recordedAt))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button(role: .destructive) {
                                wellnessStore.deleteMeasurement(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            if let v = item.chestCm { measureBadge("Brust", v, .blue) }
                            if let v = item.waistCm { measureBadge("Taille", v, .green) }
                            if let v = item.armCm { measureBadge("Arm", v, .purple) }
                            if let v = item.thighCm { measureBadge("Bein", v, .orange) }
                        }

                        if let notes = item.notes, !notes.isEmpty {
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

    private func measureBadge(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(Formatters.weight(value)) cm")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BodyMeasurementFormView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (BodyMeasurement) -> Void

    @State private var recordedAt: Date = Date()
    @State private var chestText: String = ""
    @State private var waistText: String = ""
    @State private var armText: String = ""
    @State private var thighText: String = ""
    @State private var notes: String = ""

    private var hasAnyValue: Bool {
        Formatters.parseWeight(chestText) != nil
            || Formatters.parseWeight(waistText) != nil
            || Formatters.parseWeight(armText) != nil
            || Formatters.parseWeight(thighText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Datum")) {
                    DatePicker("Gemessen am", selection: $recordedAt, displayedComponents: [.date])
                }

                Section(header: Text("Umfänge (cm, optional)")) {
                    field("Brust", text: $chestText, placeholder: "z. B. 108")
                    field("Taille", text: $waistText, placeholder: "z. B. 84")
                    field("Oberarm", text: $armText, placeholder: "z. B. 40,5")
                    field("Oberschenkel", text: $thighText, placeholder: "z. B. 62")
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. morgens, angespannt", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Körpermaße eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let measurement = BodyMeasurement(
                            recordedAt: recordedAt,
                            chestCm: Formatters.parseWeight(chestText),
                            waistCm: Formatters.parseWeight(waistText),
                            armCm: Formatters.parseWeight(armText),
                            thighCm: Formatters.parseWeight(thighText),
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                        )
                        onSave(measurement)
                        dismiss()
                    }
                    .disabled(!hasAnyValue)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("cm")
                .foregroundColor(.secondary)
        }
    }
}
