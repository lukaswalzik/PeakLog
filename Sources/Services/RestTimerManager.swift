import Foundation
import UIKit
import UserNotifications

final class RestTimerManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private static let notificationIdentifier = "strongtracker.rest_timer.complete"
    private static let autoStartDefaultsKey = "strongtracker.rest_timer.auto_start"

    @Published private(set) var targetEndDate: Date?
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    @Published var autoStartEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoStartEnabled, forKey: Self.autoStartDefaultsKey)
        }
    }

    private var ticker: Timer?
    private var foregroundObserver: NSObjectProtocol?

    var progress: Double {
        guard totalDuration > 0, isRunning else { return 0 }
        let remaining = max(0, targetEndDate?.timeIntervalSinceNow ?? 0)
        return min(1.0, max(0.0, 1.0 - (remaining / totalDuration)))
    }

    override init() {
        if UserDefaults.standard.object(forKey: Self.autoStartDefaultsKey) == nil {
            self.autoStartEnabled = true
        } else {
            self.autoStartEnabled = UserDefaults.standard.bool(forKey: Self.autoStartDefaultsKey)
        }
        super.init()

        UNUserNotificationCenter.current().delegate = self
        refreshNotificationStatus()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNotificationStatus()
            self?.syncRemainingTime()
        }
    }

    deinit {
        ticker?.invalidate()
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshNotificationStatus()
                completion?(granted)
            }
        }
    }

    func startIfAutoEnabled(seconds: Int) {
        guard autoStartEnabled else { return }
        start(seconds: seconds)
    }

    func start(seconds: Int) {
        let clamped = max(5, seconds)
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(clamped))

        totalDuration = TimeInterval(clamped)
        targetEndDate = end
        remainingSeconds = clamped
        isRunning = true

        startTicker()

        if notificationStatus == .notDetermined {
            requestNotificationPermission { [weak self] granted in
                if granted, let endDate = self?.targetEndDate {
                    let remaining = endDate.timeIntervalSinceNow
                    if remaining > 0.5 {
                        self?.scheduleNotification(in: remaining)
                    }
                }
            }
        } else if notificationStatus == .authorized || notificationStatus == .provisional {
            scheduleNotification(in: TimeInterval(clamped))
        }
    }

    func adjust(by deltaSeconds: Int) {
        guard isRunning, let currentEnd = targetEndDate else { return }
        let newEnd = currentEnd.addingTimeInterval(TimeInterval(deltaSeconds))
        let newRemaining = newEnd.timeIntervalSinceNow

        if newRemaining <= 0 {
            skip()
            return
        }

        targetEndDate = newEnd
        if newRemaining > totalDuration {
            totalDuration = newRemaining
        }
        remainingSeconds = Int(ceil(newRemaining))

        cancelPendingNotification()
        if notificationStatus == .authorized || notificationStatus == .provisional {
            scheduleNotification(in: newRemaining)
        }
    }

    func skip() {
        ticker?.invalidate()
        ticker = nil
        targetEndDate = nil
        totalDuration = 0
        remainingSeconds = 0
        isRunning = false
        cancelPendingNotification()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.syncRemainingTime()
        }
        if let ticker = ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func syncRemainingTime() {
        guard isRunning, let endDate = targetEndDate else { return }
        let remaining = endDate.timeIntervalSinceNow

        if remaining <= 0 {
            ticker?.invalidate()
            ticker = nil
            targetEndDate = nil
            totalDuration = 0
            remainingSeconds = 0
            isRunning = false

            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        } else {
            let rounded = Int(ceil(remaining))
            if rounded != remainingSeconds {
                remainingSeconds = rounded
            }
        }
    }

    private func scheduleNotification(in interval: TimeInterval) {
        cancelPendingNotification()

        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei!"
        content.body = "Zeit für den nächsten Satz."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1.0, interval),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPendingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier]
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
