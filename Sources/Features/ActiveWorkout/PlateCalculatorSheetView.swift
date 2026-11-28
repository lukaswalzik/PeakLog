import SwiftUI
import UIKit

// MARK: - Plate Model & Per-Gym Configuration

struct PlateSpec: Identifiable, Hashable {
    let weightKg: Double
    let color: Color
    let heightRatio: CGFloat
    let widthPt: CGFloat
    let shortLabel: String

    var id: Double { weightKg }

    static let allStandard: [PlateSpec] = [
        PlateSpec(weightKg: 25, color: Color(red: 0.85, green: 0.18, blue: 0.20), heightRatio: 1.00, widthPt: 15, shortLabel: "25"),
        PlateSpec(weightKg: 20, color: Color(red: 0.14, green: 0.44, blue: 0.86), heightRatio: 0.96, widthPt: 14, shortLabel: "20"),
        PlateSpec(weightKg: 15, color: Color(red: 0.92, green: 0.72, blue: 0.10), heightRatio: 0.86, widthPt: 13, shortLabel: "15"),
        PlateSpec(weightKg: 10, color: Color(red: 0.16, green: 0.66, blue: 0.36), heightRatio: 0.76, widthPt: 12, shortLabel: "10"),
        PlateSpec(weightKg: 5, color: Color(red: 0.62, green: 0.66, blue: 0.72), heightRatio: 0.64, widthPt: 10, shortLabel: "5"),
        PlateSpec(weightKg: 2.5, color: Color(red: 0.26, green: 0.28, blue: 0.34), heightRatio: 0.54, widthPt: 9, shortLabel: "2,5"),
        PlateSpec(weightKg: 1.25, color: Color(red: 0.48, green: 0.52, blue: 0.58), heightRatio: 0.45, widthPt: 8, shortLabel: "1,25"),
        PlateSpec(weightKg: 0.5, color: Color(red: 0.58, green: 0.32, blue: 0.86), heightRatio: 0.38, widthPt: 7, shortLabel: "0,5")
    ]

    static func spec(for weight: Double) -> PlateSpec {
        allStandard.first(where: { abs($0.weightKg - weight) < 0.01 })
            ?? PlateSpec(weightKg: weight, color: .gray, heightRatio: 0.5, widthPt: 9, shortLabel: Formatters.weight(weight))
    }
}

struct PlateCalculatorConfig: Codable, Equatable {
    var barWeightKg: Double = 20.0
    var enabledPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    static func storageKey(for gymId: String?) -> String {
        "strongtracker.platecalc.config.\(gymId ?? "default")"
    }

    static func load(for gymId: String?) -> PlateCalculatorConfig {
        let key = storageKey(for: gymId)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PlateCalculatorConfig.self, from: data) {
            return decoded
        }
        return PlateCalculatorConfig()
    }

    func save(for gymId: String?) {
        let key = Self.storageKey(for: gymId)
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct PlateBreakdown {
    let platesPerSide: [PlateSpec]
    let achievableTotalKg: Double
    let remainderKg: Double

    var perSideWeightKg: Double {
        platesPerSide.reduce(0) { $0 + $1.weightKg }
    }

    var groupedPerSide: [(spec: PlateSpec, count: Int)] {
        var result: [(spec: PlateSpec, count: Int)] = []
        for plate in platesPerSide {
            if let lastIdx = result.indices.last, result[lastIdx].spec.weightKg == plate.weightKg {
                result[lastIdx].count += 1
            } else {
                result.append((plate, 1))
            }
        }
        return result
    }

    static func compute(targetTotalKg: Double, barWeightKg: Double, availablePlates: [Double]) -> PlateBreakdown {
        let sorted = availablePlates.filter { $0 > 0 }.sorted(by: >)
        let loadTotal = max(0, targetTotalKg - barWeightKg)
        var remainingPerSide = loadTotal / 2.0
        var chosen: [PlateSpec] = []

        for plateWeight in sorted {
            while remainingPerSide + 0.001 >= plateWeight {
                chosen.append(PlateSpec.spec(for: plateWeight))
                remainingPerSide -= plateWeight
                if chosen.count >= 16 { break }
            }
            if chosen.count >= 16 { break }
        }

        let perSideActual = chosen.reduce(0.0) { $0 + $1.weightKg }
        let achievable = barWeightKg + perSideActual * 2.0
        let diff = max(0, targetTotalKg - achievable)
        return PlateBreakdown(
            platesPerSide: chosen,
            achievableTotalKg: achievable,
            remainderKg: diff < 0.01 ? 0 : diff
        )
    }
}

// MARK: - Sheet View

struct PlateCalculatorSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let exerciseName: String?
    let gymId: String?
    let gymName: String?
    let defaultBarWeightOverride: Double?
    let onApplyWeight: ((Double) -> Void)?

    @State private var config: PlateCalculatorConfig
    @State private var targetWeightKg: Double
    @State private var weightText: String
    @State private var isShowingWarmupLadder: Bool = false
    @State private var isShowingConfigSection: Bool = false

    private let barPresets: [(label: String, kg: Double)] = [
        ("20 kg", 20),
        ("15 kg", 15),
        ("10 kg SZ", 10),
        ("7,5 kg", 7.5),
        ("0 kg (Masch.)", 0)
    ]

    init(
        initialWeightKg: Double = 60,
        exerciseName: String? = nil,
        gymId: String? = nil,
        gymName: String? = nil,
        defaultBarWeightOverride: Double? = nil,
        onApplyWeight: ((Double) -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.gymId = gymId
        self.gymName = gymName
        self.defaultBarWeightOverride = defaultBarWeightOverride
        self.onApplyWeight = onApplyWeight

        var loaded = PlateCalculatorConfig.load(for: gymId)
        if let overrideBar = defaultBarWeightOverride {
            loaded.barWeightKg = overrideBar
        }
        let startWeight = initialWeightKg > 0 ? initialWeightKg : max(loaded.barWeightKg, 60)
        _config = State(initialValue: loaded)
        _targetWeightKg = State(initialValue: startWeight)
        _weightText = State(initialValue: Formatters.weight(startWeight))
    }

    private var breakdown: PlateBreakdown {
        PlateBreakdown.compute(
            targetTotalKg: targetWeightKg,
            barWeightKg: config.barWeightKg,
            availablePlates: config.enabledPlates
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerWeightCard
                    barbellVisualCard
                    plateTapBuilderCard
                    barWeightCard
                    warmupLadderCard
                    availablePlatesCard
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Scheibenrechner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if let onApplyWeight = onApplyWeight {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen") {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onApplyWeight(breakdown.achievableTotalKg)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Target Weight Input Card

    private var headerWeightCard: some View {
        VStack(spacing: 12) {
            if let name = exerciseName {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    if let gym = gymName {
                        Text(gym)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zielgewicht (gesamt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("60", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: 130)
                            .onChange(of: weightText) { newValue in
                                if let parsed = Formatters.parseWeight(newValue), parsed >= 0 {
                                    targetWeightKg = min(600, parsed)
                                }
                            }
                        Text("kg")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Pro Seite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Formatters.weight(breakdown.perSideWeightKg)) kg")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.accentColor)
                }
            }

            // Quick adjustment steppers
            HStack(spacing: 6) {
                quickStepButton(delta: -10)
                quickStepButton(delta: -5)
                quickStepButton(delta: -2.5)
                quickStepButton(delta: 2.5)
                quickStepButton(delta: 5)
                quickStepButton(delta: 10)
            }

            if breakdown.remainderKg > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                    Text("Mit deinen Scheiben erreichbar: **\(Formatters.weight(breakdown.achievableTotalKg)) kg** (Rest \(Formatters.weight(breakdown.remainderKg)) kg).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let onApplyWeight = onApplyWeight {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onApplyWeight(breakdown.achievableTotalKg)
                    dismiss()
                } label: {
                    Label("Gewicht übernehmen (\(Formatters.weight(breakdown.achievableTotalKg)) kg)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .strongCard()
    }

    private func quickStepButton(delta: Double) -> some View {
        let sign = delta > 0 ? "+" : "−"
        let label = "\(sign)\(Formatters.weight(abs(delta)))"
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            setWeight(max(config.barWeightKg, targetWeightKg + delta))
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(delta > 0 ? Color.accentColor.opacity(0.14) : Color(uiColor: .tertiarySystemFill))
                .foregroundColor(delta > 0 ? .accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visual Barbell Card

    private var barbellVisualCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hantel-Vorschau")
                    .font(.headline)
                Spacer()
                Text("Stange \(Formatters.weight(config.barWeightKg)) kg")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            // Visual symmetrical barbell diagram
            ZStack {
                // Shaft
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.55), Color.gray.opacity(0.85), Color.gray.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 10)

                HStack(spacing: 0) {
                    // Left sleeve + plates (outer -> inner)
                    HStack(spacing: 2) {
                        Spacer(minLength: 4)
                        ForEach(Array(breakdown.platesPerSide.reversed().enumerated()), id: \.offset) { _, plate in
                            plateBlock(plate)
                        }
                        collarView
                    }
                    .frame(maxWidth: .infinity)

                    // Center grip knurling area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 72, height: 14)

                    // Right collar + plates (inner -> outer)
                    HStack(spacing: 2) {
                        collarView
                        ForEach(Array(breakdown.platesPerSide.enumerated()), id: \.offset) { _, plate in
                            plateBlock(plate)
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112)
            .padding(.horizontal, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Per-side plate summary pills
            if breakdown.groupedPerSide.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                    Text(config.barWeightKg > 0 ? "Nur die Stange – keine Scheiben nötig." : "Noch keine Scheiben aufgelegt.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auf jede Seite stecken:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                        ForEach(breakdown.groupedPerSide, id: \.spec.weightKg) { entry in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(entry.spec.color)
                                    .frame(width: 10, height: 10)
                                Text("\(entry.count)× \(Formatters.weight(entry.spec.weightKg)) kg")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .background(entry.spec.color.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
        .strongCard()
    }

    private var collarView: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(uiColor: .systemGray2))
            .frame(width: 7, height: 26)
    }

    private func plateBlock(_ plate: PlateSpec) -> some View {
        let maxHeight: CGFloat = 94
        let height = max(28, maxHeight * plate.heightRatio)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(plate.color)
            .frame(width: plate.widthPt, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.22), lineWidth: 0.8)
            )
            .overlay(
                Group {
                    if plate.widthPt >= 12 {
                        Text(plate.shortLabel)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                    }
                }
            )
    }

    // MARK: - Interactive Plate Tap Builder

    private var plateTapBuilderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scheiben direkt auflegen (je Seite)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Leeren") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    setWeight(config.barWeightKg)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .disabled(targetWeightKg <= config.barWeightKg)
            }

            let activeSpecs = PlateSpec.allStandard.filter { spec in
                config.enabledPlates.contains(where: { abs($0 - spec.weightKg) < 0.01 })
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(activeSpecs) { spec in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        setWeight(min(600, breakdown.achievableTotalKg + spec.weightKg * 2.0))
                    } label: {
                        VStack(spacing: 2) {
                            Text("+\(spec.shortLabel)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                            Text("kg")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(spec.color)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .strongCard()
    }

    // MARK: - Bar Weight Card

    private var barWeightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Stangengewicht")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Formatters.weight(config.barWeightKg)) kg")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                    .monospacedDigit()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(barPresets, id: \.kg) { preset in
                        let selected = abs(config.barWeightKg - preset.kg) < 0.01
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            config.barWeightKg = preset.kg
                            config.save(for: gymId)
                            if targetWeightKg < preset.kg {
                                setWeight(preset.kg)
                            }
                        } label: {
                            Text(preset.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .foregroundColor(selected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .strongCard()
    }

    // MARK: - Warmup Ladder Card

    private var warmupLadderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingWarmupLadder.toggle()
                }
            } label: {
                HStack {
                    Label("Aufwärm-Scheibenleiter", systemImage: "flame.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Spacer()
                    Image(systemName: isShowingWarmupLadder ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isShowingWarmupLadder {
                let steps: [(label: String, factor: Double, reps: String)] = [
                    ("50 %", 0.50, "8 Wdh."),
                    ("70 %", 0.70, "5 Wdh."),
                    ("85 %", 0.85, "2–3 Wdh."),
                    ("100 %", 1.00, "Arbeitssatz")
                ]

                VStack(spacing: 8) {
                    ForEach(steps, id: \.label) { step in
                        let rawTarget = max(config.barWeightKg, targetWeightKg * step.factor)
                        let stepBreakdown = PlateBreakdown.compute(
                            targetTotalKg: rawTarget,
                            barWeightKg: config.barWeightKg,
                            availablePlates: config.enabledPlates
                        )
                        HStack(spacing: 8) {
                            Text(step.label)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .frame(width: 42, alignment: .leading)

                            Text("\(Formatters.weight(stepBreakdown.achievableTotalKg)) kg")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .frame(width: 68, alignment: .leading)

                            if stepBreakdown.groupedPerSide.isEmpty {
                                Text("Nur Stange")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(
                                    stepBreakdown.groupedPerSide
                                        .map { "\($0.count)×\(Formatters.weight($0.spec.weightKg))" }
                                        .joined(separator: " + ")
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            }

                            Spacer()

                            Text(step.reps)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .strongCard()
    }

    // MARK: - Available Plates Per Gym

    private var availablePlatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingConfigSection.toggle()
                }
            } label: {
                HStack {
                    Label("Verfügbare Scheiben (\(gymName ?? "Standard"))", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isShowingConfigSection ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isShowingConfigSection {
                Text("Wähle aus, welche Hantelscheiben in deinem Studio vorhanden sind:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                    ForEach(PlateSpec.allStandard) { spec in
                        let isOn = config.enabledPlates.contains(where: { abs($0 - spec.weightKg) < 0.01 })
                        Button {
                            togglePlate(spec.weightKg)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                Text("\(Formatters.weight(spec.weightKg)) kg")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isOn ? spec.color.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                            .foregroundColor(isOn ? spec.color : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .strongCard()
    }

    // MARK: - Helpers

    private func setWeight(_ newWeight: Double) {
        let clamped = max(0, min(600, newWeight))
        targetWeightKg = clamped
        weightText = Formatters.weight(clamped)
    }

    private func togglePlate(_ weight: Double) {
        if let idx = config.enabledPlates.firstIndex(where: { abs($0 - weight) < 0.01 }) {
            // Keep at least one plate enabled
            guard config.enabledPlates.count > 1 else { return }
            config.enabledPlates.remove(at: idx)
        } else {
            config.enabledPlates.append(weight)
            config.enabledPlates.sort(by: >)
        }
        config.save(for: gymId)
    }
}
