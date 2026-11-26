import AuthenticationServices
import Foundation
import Security
import UIKit

struct OuraDailySummary: Identifiable, Codable, Equatable {
    var day: String // yyyy-MM-dd
    var readinessScore: Int?
    var sleepScore: Int?
    var sleepHours: Double?
    var deepSleepMinutes: Int?
    var remSleepMinutes: Int?
    var averageHRV: Int?
    var lowestHeartRate: Int?
    var steps: Int?
    var activeCalories: Int?
    var activityScore: Int?
    var stressSummary: String?
    var spo2Average: Double?

    var id: String { day }

    var date: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: day) ?? Date()
    }
}

struct OuraWorkoutRecord: Identifiable, Codable, Equatable {
    var id: String
    var activity: String
    var label: String?
    var day: String
    var startDatetime: String
    var endDatetime: String
    var calories: Double?
    var distanceMeters: Double?
    var intensity: String?

    var startDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: startDatetime) { return d }
        let isoBasic = ISO8601DateFormatter()
        return isoBasic.date(from: startDatetime) ?? Date()
    }

    var endDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: endDatetime) { return d }
        let isoBasic = ISO8601DateFormatter()
        return isoBasic.date(from: endDatetime) ?? startDate
    }

    var durationSeconds: Int {
        max(60, Int(endDate.timeIntervalSince(startDate)))
    }

    var displayTitle: String {
        if let label = label, !label.isEmpty { return label }
        return activity.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func toCardioSession() -> CardioSession {
        let lower = activity.lowercased()
        let mappedType: CardioActivityType
        if lower.contains("run") || lower.contains("jog") {
            mappedType = .running
        } else if lower.contains("cycl") || lower.contains("bik") || lower.contains("spin") {
            mappedType = .cycling
        } else if lower.contains("row") {
            mappedType = .rowing
        } else if lower.contains("swim") {
            mappedType = .swimming
        } else if lower.contains("walk") || lower.contains("hik") {
            mappedType = .walking
        } else if lower.contains("hiit") || lower.contains("circuit") {
            mappedType = .hiit
        } else {
            mappedType = .other
        }

        let distKm = distanceMeters.map { $0 / 1000.0 }
        return CardioSession(
            id: "oura-\(id)",
            activityType: mappedType,
            startedAt: startDate,
            durationSeconds: durationSeconds,
            distanceKm: (distKm ?? 0) > 0.05 ? distKm : nil,
            calories: calories.map { Int(round($0)) },
            notes: "Importiert von Oura (\(displayTitle))"
        )
    }
}

struct OuraSnapshot: Codable, Equatable {
    var syncedAt: Date
    var days: [OuraDailySummary]
    var workouts: [OuraWorkoutRecord]

    var latestDay: OuraDailySummary? {
        days.sorted { $0.day > $1.day }.first
    }
}

enum OuraError: LocalizedError {
    case missingClientCredentials
    case notAuthenticated
    case authCancelled
    case authFailed(String)
    case apiError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingClientCredentials:
            return "Bitte gib zuerst deine Oura Client ID und dein Client Secret ein."
        case .notAuthenticated:
            return "Noch nicht mit Oura verbunden. Tippe auf „Mit Oura verbinden“."
        case .authCancelled:
            return "Oura-Anmeldung wurde abgebrochen."
        case .authFailed(let msg):
            return "Oura OAuth-Fehler: \(msg)"
        case .apiError(let code, let msg):
            if code == 401 {
                return "Oura-Sitzung abgelaufen (HTTP 401). Bitte erneut mit Oura verbinden."
            }
            if code == 403 {
                return "Kein Zugriff (HTTP 403). Hinweis: Für Oura API v2 ist bei Gen 3/4 eine aktive Oura Membership nötig."
            }
            return "Oura API Fehler (\(code)): \(msg)"
        case .invalidResponse:
            return "Ungültige Antwort von der Oura API."
        }
    }
}

final class OuraService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OuraService()
    static let callbackScheme = "strongtracker"
    static let redirectURI = "strongtracker://oura-callback"

    private static let keychainService = "com.local.strongtracker.oura"
    private static let snapshotDefaultsKey = "strongtracker.oura.snapshot.v1"

    @Published var clientId: String {
        didSet { saveSecret(clientId, account: "client_id") }
    }
    @Published var clientSecret: String {
        didSet { saveSecret(clientSecret, account: "client_secret") }
    }
    @Published private(set) var accessToken: String = ""
    @Published private(set) var refreshToken: String = ""
    @Published private(set) var tokenExpiresAt: Date? = nil
    @Published private(set) var snapshot: OuraSnapshot? = nil

    @Published var isSyncing: Bool = false
    @Published var statusMessage: String? = nil

    var isConnected: Bool {
        !accessToken.isEmpty || !refreshToken.isEmpty
    }

    var hasClientCredentials: Bool {
        !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeAuthSession: ASWebAuthenticationSession?
    private let urlSession: URLSession

    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)

        self.clientId = Self.loadSecret(account: "client_id")
        self.clientSecret = Self.loadSecret(account: "client_secret")
        super.init()

        self.accessToken = Self.loadSecret(account: "access_token")
        self.refreshToken = Self.loadSecret(account: "refresh_token")
        let expTs = UserDefaults.standard.double(forKey: "strongtracker.oura.token_exp")
        if expTs > 0 {
            self.tokenExpiresAt = Date(timeIntervalSince1970: expTs)
        }
        if let data = UserDefaults.standard.data(forKey: Self.snapshotDefaultsKey),
           let decoded = try? JSONDecoder().decode(OuraSnapshot.self, from: data) {
            self.snapshot = decoded
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return scenes.first?.windows.first ?? ASPresentationAnchor()
    }

    // MARK: - OAuth2 Flow

    @MainActor
    func connectOAuth() async throws {
        let cid = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let csec = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !csec.isEmpty else {
            throw OuraError.missingClientCredentials
        }

        let state = UUID().uuidString
        var comps = URLComponents(string: "https://cloud.ouraring.com/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "daily personal heartrate workout session spo2 stress"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = comps.url else {
            throw OuraError.authFailed("Ungültige OAuth-URL.")
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OuraError.authCancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: OuraError.authFailed(error.localizedDescription))
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: OuraError.authFailed("Keine Callback-URL erhalten."))
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeAuthSession = session
            session.start()
        }

        self.activeAuthSession = nil

        let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        if let errParam = callbackComps?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw OuraError.authFailed(errParam)
        }
        guard let code = callbackComps?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OuraError.authFailed("Kein Authorization Code in der Antwort.")
        }

        try await exchangeCodeForTokens(code: code, clientId: cid, clientSecret: csec)
    }

    func disconnect() {
        accessToken = ""
        refreshToken = ""
        tokenExpiresAt = nil
        saveSecret("", account: "access_token")
        saveSecret("", account: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "strongtracker.oura.token_exp")
        statusMessage = "Oura-Verbindung getrennt."
    }

    private func exchangeCodeForTokens(code: String, clientId: String, clientSecret: String) async throws {
        var req = URLRequest(url: URL(string: "https://api.ouraring.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", Self.redirectURI),
            ("client_id", clientId),
            ("client_secret", clientSecret)
        ]
        req.httpBody = formEncoded(params)

        try await performTokenRequest(req)
    }

    private func refreshAccessTokenIfNeeded() async throws -> String {
        guard isConnected else { throw OuraError.notAuthenticated }

        // If token is still valid for at least 2 minutes, use it directly
        if !accessToken.isEmpty, let exp = tokenExpiresAt, exp.timeIntervalSinceNow > 120 {
            return accessToken
        }

        guard !refreshToken.isEmpty else {
            if !accessToken.isEmpty { return accessToken }
            throw OuraError.notAuthenticated
        }

        let cid = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let csec = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !csec.isEmpty else {
            throw OuraError.missingClientCredentials
        }

        var req = URLRequest(url: URL(string: "https://api.ouraring.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", cid),
            ("client_secret", csec)
        ]
        req.httpBody = formEncoded(params)

        try await performTokenRequest(req)
        return accessToken
    }

    private func performTokenRequest(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OuraError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Token-Fehler"
            throw OuraError.apiError(http.statusCode, msg)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expires_in ?? 86400))

        await MainActor.run {
            self.accessToken = decoded.access_token
            self.saveSecret(decoded.access_token, account: "access_token")
            if let newRefresh = decoded.refresh_token, !newRefresh.isEmpty {
                // Oura refresh tokens are single-use – always persist the rotated token immediately
                self.refreshToken = newRefresh
                self.saveSecret(newRefresh, account: "refresh_token")
            }
            self.tokenExpiresAt = expiresAt
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: "strongtracker.oura.token_exp")
        }
    }

    // MARK: - Full 14-Day Data Sync

    @MainActor
    func syncAll(days: Int = 14, wellnessStore: WellnessStore? = nil) async throws -> OuraSnapshot {
        isSyncing = true
        statusMessage = nil
        defer { isSyncing = false }

        let token = try await refreshAccessTokenIfNeeded()

        let cal = Calendar.current
        let today = Date()
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let startStr = DayKeyFormatter.string(from: start)
        let endStr = DayKeyFormatter.string(from: end)

        var byDay: [String: OuraDailySummary] = [:]
        func ensureDay(_ day: String) -> OuraDailySummary {
            byDay[day] ?? OuraDailySummary(day: day)
        }

        // 1. Daily Readiness
        if let rows = try? await fetchCollection("daily_readiness", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                var s = ensureDay(day)
                s.readinessScore = row["score"] as? Int
                byDay[day] = s
            }
        }

        // 2. Daily Sleep Score
        if let rows = try? await fetchCollection("daily_sleep", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                var s = ensureDay(day)
                s.sleepScore = row["score"] as? Int
                byDay[day] = s
            }
        }

        // 3. Detailed Sleep Periods (total duration, HRV, lowest HR, deep/REM)
        if let rows = try? await fetchCollection("sleep", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                let type = (row["type"] as? String) ?? ""
                // Prefer primary sleep ("long_sleep") if multiple entries exist for a day
                var s = ensureDay(day)
                let totalSec = row["total_sleep_duration"] as? Int ?? 0
                let hours = Double(totalSec) / 3600.0
                if type == "long_sleep" || s.sleepHours == nil || hours > (s.sleepHours ?? 0) {
                    if totalSec > 0 { s.sleepHours = hours }
                    if let hrv = row["average_hrv"] as? Int { s.averageHRV = hrv }
                    if let lhr = row["lowest_heart_rate"] as? Int { s.lowestHeartRate = lhr }
                    if let deep = row["deep_sleep_duration"] as? Int { s.deepSleepMinutes = deep / 60 }
                    if let rem = row["rem_sleep_duration"] as? Int { s.remSleepMinutes = rem / 60 }
                    byDay[day] = s
                }
            }
        }

        // 4. Daily Activity (Steps, Active Calories, Score)
        if let rows = try? await fetchCollection("daily_activity", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                var s = ensureDay(day)
                s.steps = row["steps"] as? Int
                s.activeCalories = row["active_calories"] as? Int
                s.activityScore = row["score"] as? Int
                byDay[day] = s
            }
        }

        // 5. Daily Stress
        if let rows = try? await fetchCollection("daily_stress", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                var s = ensureDay(day)
                s.stressSummary = row["day_summary"] as? String
                byDay[day] = s
            }
        }

        // 6. Daily SpO2
        if let rows = try? await fetchCollection("daily_spo2", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let day = row["day"] as? String else { continue }
                if let spo2Obj = row["spo2_percentage"] as? [String: Any],
                   let avg = spo2Obj["average"] as? Double {
                    var s = ensureDay(day)
                    s.spo2Average = avg
                    byDay[day] = s
                }
            }
        }

        // 7. Oura Workouts
        var parsedWorkouts: [OuraWorkoutRecord] = []
        if let rows = try? await fetchCollection("workout", start: startStr, end: endStr, token: token) {
            for row in rows {
                guard let id = row["id"] as? String,
                      let activity = row["activity"] as? String,
                      let day = row["day"] as? String,
                      let startDt = row["start_datetime"] as? String,
                      let endDt = row["end_datetime"] as? String else { continue }

                parsedWorkouts.append(
                    OuraWorkoutRecord(
                        id: id,
                        activity: activity,
                        label: row["label"] as? String,
                        day: day,
                        startDatetime: startDt,
                        endDatetime: endDt,
                        calories: row["calories"] as? Double,
                        distanceMeters: row["distance"] as? Double,
                        intensity: row["intensity"] as? String
                    )
                )
            }
        }

        let sortedDays = byDay.values.sorted { $0.day < $1.day }
        let sortedWorkouts = parsedWorkouts.sorted { $0.startDatetime > $1.startDatetime }
        let newSnapshot = OuraSnapshot(syncedAt: Date(), days: sortedDays, workouts: sortedWorkouts)

        self.snapshot = newSnapshot
        if let encoded = try? JSONEncoder().encode(newSnapshot) {
            UserDefaults.standard.set(encoded, forKey: Self.snapshotDefaultsKey)
        }

        // Auto-upsert Readiness & Sleep into StrongTracker's SQLite ReadinessLogs
        if let store = wellnessStore {
            for item in sortedDays {
                if let rScore = item.readinessScore {
                    let noteParts: [String] = [
                        item.averageHRV.map { "HRV \($0) ms" },
                        item.lowestHeartRate.map { "RHR \($0) bpm" },
                        item.steps.map { "\($0) Schritte" }
                    ].compactMap { $0 }

                    let log = ReadinessLog(
                        dayKey: item.day,
                        recordedAt: item.date,
                        readinessScore: rScore,
                        sleepHours: item.sleepHours ?? 7.5,
                        soreness: 2,
                        notes: noteParts.isEmpty ? "Oura Sync" : "Oura: " + noteParts.joined(separator: " · ")
                    )
                    store.saveReadiness(log)
                }
            }
        }

        statusMessage = "Sync erfolgreich: \(sortedDays.count) Tage & \(sortedWorkouts.count) Workouts geladen."
        return newSnapshot
    }

    private func fetchCollection(
        _ endpoint: String,
        start: String,
        end: String,
        token: String
    ) async throws -> [[String: Any]] {
        var comps = URLComponents(string: "https://api.ouraring.com/v2/usercollection/\(endpoint)")!
        comps.queryItems = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end)
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw OuraError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw OuraError.apiError(http.statusCode, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }
        return items
    }

    private func formEncoded(_ pairs: [(String, String)]) -> Data? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let parts: [String] = pairs.map { key, val in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = val.addingPercentEncoding(withAllowedCharacters: allowed) ?? val
            return "\(k)=\(v)"
        }
        let str: String = parts.joined(separator: "&")
        return str.data(using: .utf8)
    }

    // MARK: - Keychain with UserDefaults fallback

    private static func loadSecret(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }
        return UserDefaults.standard.string(forKey: "strongtracker.oura.fb.\(account)") ?? ""
    }

    private func saveSecret(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: "strongtracker.oura.fb.\(account)")
            return
        }

        if let data = trimmed.data(using: .utf8) {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status != errSecSuccess {
                UserDefaults.standard.set(trimmed, forKey: "strongtracker.oura.fb.\(account)")
            } else {
                UserDefaults.standard.removeObject(forKey: "strongtracker.oura.fb.\(account)")
            }
        }
    }
}
