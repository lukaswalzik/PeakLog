import Charts
import SwiftUI

struct BodyMeasurementsView: View {
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var bodyweightStore: BodyweightStore
    @EnvironmentObject private var nutritionStore: NutritionStore

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

    private var latestUSNavyEstimate: (bfPercent: Double, leanMassKg: Double, ffmi: Double)? {
        guard let latestWithNavy = wellnessStore.measurements.first(where: { $0.waistCm != nil && $0.neckCm != nil }),
              let waist = latestWithNavy.waistCm,
              let neck = latestWithNavy.neckCm,
              waist > neck + 2 else {
            return nil
        }
        let heightCm = Double(max(130, nutritionStore.goals.heightCm))
        let weightKg = bodyweightStore.latestEntry?.entry.weightKg ?? nutritionStore.goals.weightKg
        let denom = 1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(heightCm)
        guard denom > 0 else { return nil }
        let rawBF = (495.0 / denom) - 450.0
        let bf = max(4.0, min(45.0, rawBF))
        let lbm = weightKg * (1.0 - bf / 100.0)
        let heightM = heightCm / 100.0
        let ffmi = lbm / (heightM * heightM)
        return (bf, lbm, ffmi)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                usNavyBodyFatCard
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

    private var usNavyBodyFatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Körperfett (US-Navy) & FFMI", systemImage: "figure.arms.open")
                    .font(.headline)
                Spacer()
            }

            if let est = latestUSNavyEstimate {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KFA (ca.)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", est.bfPercent)) %")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Magermasse")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Formatters.weight(est.leanMassKg)) kg")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FFMI")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", est.ffmi))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.purple.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text("Trage bei einer Messung **Taille** und **Nacken** ein, um automatisch deinen geschätzten Körperfettanteil (US-Navy), deine fettfreie Muskelmasse und deinen FFMI zu berechnen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
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
                    message: "Halte Brust, Taille, Nacken, Oberarm & Oberschenkel fest – ideal bei Recomp & Muskelaufbau.",
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

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if let v = item.chestCm { measureBadge("Brust", v, .blue) }
                                if let v = item.waistCm { measureBadge("Taille", v, .green) }
                                if let v = item.neckCm { measureBadge("Nacken", v, .teal) }
                                if let v = item.armCm { measureBadge("Arm", v, .purple) }
                                if let v = item.thighCm { measureBadge("Bein", v, .orange) }
                            }
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
    @State private var neckText: String = ""
    @State private var armText: String = ""
    @State private var thighText: String = ""
    @State private var notes: String = ""

    private var hasAnyValue: Bool {
        Formatters.parseWeight(chestText) != nil
            || Formatters.parseWeight(waistText) != nil
            || Formatters.parseWeight(neckText) != nil
            || Formatters.parseWeight(armText) != nil
            || Formatters.parseWeight(thighText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Datum")) {
                    DatePicker("Gemessen am", selection: $recordedAt, displayedComponents: [.date])
                }

                Section(
                    header: Text("Umfänge (cm, optional)"),
                    footer: Text("Taille + Nacken aktivieren automatisch die US-Navy Körperfett- & FFMI-Berechnung.")
                ) {
                    field("Brust", text: $chestText, placeholder: "z. B. 108")
                    field("Taille (Bauchnabel)", text: $waistText, placeholder: "z. B. 84")
                    field("Nacken", text: $neckText, placeholder: "z. B. 40")
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
                            neckCm: Formatters.parseWeight(neckText),
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
