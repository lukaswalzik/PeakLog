import Foundation

enum Formatters {
    private static let weightNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static func restDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins == 0 {
            return "\(secs)s"
        } else if secs == 0 {
            return "\(mins) min"
        } else {
            return String(format: "%d:%02d min", mins, secs)
        }
    }

    static func elapsedDuration(from startDate: Date, to endDate: Date = Date()) -> String {
        let totalSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    static func weight(_ kg: Double) -> String {
        weightNumberFormatter.string(from: NSNumber(value: kg)) ?? "\(kg)"
    }

    static func parseWeight(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func previousSet(_ ref: PreviousSetReference?) -> String {
        guard let ref = ref else { return "–" }
        switch (ref.weightKg, ref.reps) {
        case let (w?, r?):
            return "\(weight(w)) × \(r)"
        case let (nil, r?):
            return "\(r) Wdh."
        case let (w?, nil):
            return "\(weight(w)) kg"
        case (nil, nil):
            return "–"
        }
    }

    private static let workoutDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }()

    static func workoutDate(_ date: Date) -> String {
        workoutDateFormatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }
}
