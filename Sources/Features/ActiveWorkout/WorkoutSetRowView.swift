import SwiftUI
import UIKit

struct WorkoutSetRowView: View {
    let set: WorkoutSet
    let previous: PreviousSetReference?
    var isPR: Bool = false
    let onUpdate: (WorkoutSet) -> Void
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    var onOpenPlateCalculator: (() -> Void)? = nil

    private enum Field: Hashable {
        case weight
        case reps
    }

    @State private var weightText: String
    @State private var repsText: String
    @FocusState private var focusedField: Field?

    init(
        set: WorkoutSet,
        previous: PreviousSetReference?,
        isPR: Bool = false,
        onUpdate: @escaping (WorkoutSet) -> Void,
        onToggleComplete: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenPlateCalculator: (() -> Void)? = nil
    ) {
        self.set = set
        self.previous = previous
        self.isPR = isPR
        self.onUpdate = onUpdate
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        self.onOpenPlateCalculator = onOpenPlateCalculator
        _weightText = State(initialValue: set.weightKg.map { Formatters.weight($0) } ?? "")
        _repsText = State(initialValue: set.reps.map { "\($0)" } ?? "")
    }

    private var setBadgeText: String {
        self.set.setType.shortBadge ?? "\(self.set.setOrder)"
    }

    private var setBadgeColor: Color {
        switch set.setType {
        case .normal: return .primary
        case .warmup: return .orange
        case .dropset: return .purple
        case .failure: return .red
        }
    }

    private var weightPlaceholder: String {
        if let prevWeight = previous?.weightKg {
            return Formatters.weight(prevWeight)
        }
        return "0"
    }

    private var repsPlaceholder: String {
        if let prevReps = previous?.reps {
            return "\(prevReps)"
        }
        return "0"
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SetType.allCases) { type in
                    Button {
                        var updated = set
                        updated.setType = type
                        onUpdate(updated)
                    } label: {
                        HStack {
                            Text(type.displayName)
                            if set.setType == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if let openPlates = onOpenPlateCalculator {
                    Divider()
                    Button {
                        focusedField = nil
                        openPlates()
                    } label: {
                        Label("Scheibenrechner", systemImage: "scalemass")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Satz löschen", systemImage: "trash")
                }
            } label: {
                Text(setBadgeText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(setBadgeColor)
                    .frame(width: 30, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if isPR {
                HStack(spacing: 2) {
                    Image(systemName: "trophy.fill")
                    Text("PR")
                }
                .font(.caption2)
                .fontWeight(.heavy)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.25))
                .foregroundColor(.orange)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(Formatters.previousSet(previous))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            TextField(weightPlaceholder, text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .fontWeight(.medium)
                .focused($focusedField, equals: .weight)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 64)
                .onChange(of: weightText) { newValue in
                    let parsed = Formatters.parseWeight(newValue)
                    if parsed != set.weightKg {
                        var updated = set
                        updated.weightKg = parsed
                        onUpdate(updated)
                    }
                }

            TextField(repsPlaceholder, text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .fontWeight(.medium)
                .focused($focusedField, equals: .reps)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 48)
                .onChange(of: repsText) { newValue in
                    let digitsOnly = newValue.filter { $0.isNumber }
                    let parsed = Int(digitsOnly)
                    if parsed != set.reps {
                        var updated = set
                        updated.reps = parsed
                        onUpdate(updated)
                    }
                }

            Menu {
                Button("RIR 0 (Muskelversagen)") { updateRIR(0) }
                Button("RIR 1 (1 Wdh. Reserve)") { updateRIR(1) }
                Button("RIR 2 (Optimal Hypertrophie)") { updateRIR(2) }
                Button("RIR 3 (Moderat)") { updateRIR(3) }
                Button("RIR 4+ (Leicht)") { updateRIR(4) }
                if set.rir != nil {
                    Divider()
                    Button("RIR entfernen", role: .destructive) { updateRIR(nil) }
                }
            } label: {
                Text(set.rir.map { "R\($0)" } ?? "–")
                    .font(.caption)
                    .fontWeight(set.rir != nil ? .bold : .regular)
                    .foregroundColor(rirColor(set.rir))
                    .frame(width: 34, height: 32)
                    .background(rirBackground(set.rir))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                focusedField = nil
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onToggleComplete()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.square.fill" : "checkmark.square")
                    .font(.title2)
                    .foregroundColor(set.isCompleted ? .green : .secondary.opacity(0.6))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Satz abgeschlossen" : "Satz abhaken")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(set.isCompleted ? (isPR ? Color.yellow.opacity(0.14) : Color.green.opacity(0.12)) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: isPR) { nowPR in
            if nowPR {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: set.weightKg) { newWeight in
            guard focusedField != .weight else { return }
            let formatted = newWeight.map { Formatters.weight($0) } ?? ""
            if formatted != weightText {
                weightText = formatted
            }
        }
        .onChange(of: set.reps) { newReps in
            guard focusedField != .reps else { return }
            let formatted = newReps.map { "\($0)" } ?? ""
            if formatted != repsText {
                repsText = formatted
            }
        }
    }

    private func updateRIR(_ value: Int?) {
        var updated = set
        updated.rir = value
        onUpdate(updated)
    }

    private func rirColor(_ rir: Int?) -> Color {
        guard let rir = rir else { return .secondary }
        switch rir {
        case 0: return .red
        case 1: return .orange
        case 2: return .green
        default: return .blue
        }
    }

    private func rirBackground(_ rir: Int?) -> Color {
        guard let rir = rir else { return Color(uiColor: .tertiarySystemFill) }
        return rirColor(rir).opacity(0.16)
    }
}
