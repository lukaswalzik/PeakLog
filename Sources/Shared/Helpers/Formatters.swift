import Foundation

enum Formatters {
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
}
