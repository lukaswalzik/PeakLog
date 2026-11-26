import SwiftUI
import UIKit

struct WorkoutSetRowView: View {
    let set: WorkoutSet
    let previous: PreviousSetReference?
    var isPR: Bool = false
    let onUpdate: (WorkoutSet) -> Void
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

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
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.previous = previous
        self.isPR = isPR
        self.onUpdate = onUpdate
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
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
        HStack(spacing: 8) {
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
                    .frame(width: 32, height: 32)
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
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            TextField(weightPlaceholder, text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .fontWeight(.medium)
                .focused($focusedField, equals: .weight)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 72)
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
                .padding(.horizontal, 6)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 58)
                .onChange(of: repsText) { newValue in
                    let digitsOnly = newValue.filter { $0.isNumber }
                    let parsed = Int(digitsOnly)
                    if parsed != set.reps {
                        var updated = set
                        updated.reps = parsed
                        onUpdate(updated)
                    }
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
                    .frame(width: 36, height: 32)
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
}
