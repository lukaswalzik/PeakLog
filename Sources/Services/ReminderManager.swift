import Foundation
import UserNotifications

final class ReminderManager: ObservableObject {
    static let shared = ReminderManager()

    private static let supplementId = "strongtracker.reminder.supplements"
    private static let waterId = "strongtracker.reminder.water"
    private static let workoutId = "strongtracker.reminder.workout"

    @Published var supplementEnabled: Bool {
        didSet { persistAndReschedule() }
    }
    @Published var supplementTime: Date {
        didSet { persistAndReschedule() }
    }

    @Published var waterEnabled: Bool {
        didSet { persistAndReschedule() }
    }
    @Published var waterTime: Date {
        didSet { persistAndReschedule() }
    }

    @Published var workoutEnabled: Bool {
        didSet { persistAndReschedule() }
    }
    @Published var workoutTime: Date {
        didSet { persistAndReschedule() }
    }

    private var isInitializing = true

    private init() {
        let d = UserDefaults.standard
        self.supplementEnabled = d.bool(forKey: "rem.supp.enabled")
        self.supplementTime = Self.loadTime(key: "rem.supp.time", defaultHour: 20, defaultMinute: 0)
        self.waterEnabled = d.bool(forKey: "rem.water.enabled")
        self.waterTime = Self.loadTime(key: "rem.water.time", defaultHour: 16, defaultMinute: 0)
        self.workoutEnabled = d.bool(forKey: "rem.workout.enabled")
        self.workoutTime = Self.loadTime(key: "rem.workout.time", defaultHour: 17, defaultMinute: 30)
        self.isInitializing = false
    }

    private static func loadTime(key: String, defaultHour: Int, defaultMinute: Int) -> Date {
        if let saved = UserDefaults.standard.object(forKey: key) as? Date {
            return saved
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = defaultHour
        comps.minute = defaultMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func persistAndReschedule() {
        guard !isInitializing else { return }
        let d = UserDefaults.standard
        d.set(supplementEnabled, forKey: "rem.supp.enabled")
        d.set(supplementTime, forKey: "rem.supp.time")
        d.set(waterEnabled, forKey: "rem.water.enabled")
        d.set(waterTime, forKey: "rem.water.time")
        d.set(workoutEnabled, forKey: "rem.workout.enabled")
        d.set(workoutTime, forKey: "rem.workout.time")

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard let self = self else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Self.supplementId, Self.waterId, Self.workoutId])
            guard granted else { return }

            if self.supplementEnabled {
                self.scheduleDaily(
                    id: Self.supplementId,
                    time: self.supplementTime,
                    title: "Supplements-Check 💊",
                    body: "Kreatin & Tages-Supplements heute schon abgehakt?"
                )
            }
            if self.waterEnabled {
                self.scheduleDaily(
                    id: Self.waterId,
                    time: self.waterTime,
                    title: "Wasser-Erinnerung 💧",
                    body: "Kurzer Trink-Check – wie steht dein Tagesziel?"
                )
            }
            if self.workoutEnabled {
                self.scheduleDaily(
                    id: Self.workoutId,
                    time: self.workoutTime,
                    title: "Zeit fürs Training 💪",
                    body: "Bereit für deine nächste StrongTracker-Einheit?"
                )
            }
        }
    }

    private func scheduleDaily(id: String, time: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
