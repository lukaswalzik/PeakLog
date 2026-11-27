import Foundation
import Security
import UIKit

enum MistralModel: String, CaseIterable, Identifiable, Codable {
    case smallLatest = "mistral-small-latest"
    case largeLatest = "mistral-large-latest"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smallLatest: return "Mistral Small 4 (Schnell & Vision)"
        case .largeLatest: return "Mistral Large 4 (Top Analyse & Vision)"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .smallLatest: return "Sehr schnell & günstig – ideal für Foto-/Text-Scanner"
        case .largeLatest: return "Maximale Qualität für Coaching & komplexe Bilder"
        }
    }
}

struct AIEstimatedFood: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var grams: Double
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double
    var note: String?
    var isSelected: Bool = true

    enum CodingKeys: String, CodingKey {
        case name, grams, caloriesPer100g, proteinPer100g, carbsPer100g, fatPer100g, fiberPer100g, note
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        grams: Double,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        note: String? = nil,
        isSelected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.note = note
        self.isSelected = isSelected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        grams = max(1, (try? c.decode(Double.self, forKey: .grams)) ?? 100)
        caloriesPer100g = max(0, (try? c.decode(Double.self, forKey: .caloriesPer100g)) ?? 0)
        proteinPer100g = max(0, (try? c.decode(Double.self, forKey: .proteinPer100g)) ?? 0)
        carbsPer100g = max(0, (try? c.decode(Double.self, forKey: .carbsPer100g)) ?? 0)
        fatPer100g = max(0, (try? c.decode(Double.self, forKey: .fatPer100g)) ?? 0)
        fiberPer100g = max(0, (try? c.decode(Double.self, forKey: .fiberPer100g)) ?? 0)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        isSelected = true
    }

    private var factor: Double { grams / 100.0 }
    var totalCalories: Double { caloriesPer100g * factor }
    var totalProtein: Double { proteinPer100g * factor }
    var totalCarbs: Double { carbsPer100g * factor }
    var totalFat: Double { fatPer100g * factor }

    func toFoodItem() -> FoodItem {
        FoodItem(
            name: name,
            brand: "Mistral KI",
            servingSizeGrams: grams,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            fiberPer100g: fiberPer100g,
            isCustom: true
        )
    }
}

enum MistralAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Kein Mistral API-Key hinterlegt. Öffne Profil → Mistral KI-Einstellungen und füge deinen Key ein."
        case .invalidResponse:
            return "Ungültige Antwort von der Mistral API."
        case .apiError(let code, let message):
            if code == 401 {
                return "API-Key ungültig oder abgelaufen (HTTP 401). Bitte prüfe deinen Key unter console.mistral.ai."
            }
            if code == 429 {
                return "Rate-Limit oder Monats-Budget erreicht (HTTP 429). Bitte kurz warten oder Budget prüfen."
            }
            return "Mistral API Fehler (\(code)): \(message)"
        case .decodingFailed(let detail):
            return "Antwort konnte nicht verarbeitet werden: \(detail)"
        }
    }
}

final class MistralAIService: ObservableObject {
    static let shared = MistralAIService()

    private static let keychainService = "com.local.strongtracker.mistral"
    private static let keychainAccount = "api_key"
    private static let fallbackDefaultsKey = "strongtracker.mistral.apikey.fallback"
    private static let modelDefaultsKey = "strongtracker.mistral.model"
    private static let lastReportDefaultsKey = "strongtracker.mistral.lastCoachReport"

    @Published var apiKey: String {
        didSet {
            saveAPIKey(apiKey)
        }
    }

    @Published var selectedModel: MistralModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
        }
    }

    @Published var lastCoachReport: String {
        didSet {
            UserDefaults.standard.set(lastCoachReport, forKey: Self.lastReportDefaultsKey)
        }
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.apiKey = Self.loadAPIKey()
        if let savedModel = UserDefaults.standard.string(forKey: Self.modelDefaultsKey),
           let parsed = MistralModel(rawValue: savedModel) {
            self.selectedModel = parsed
        } else {
            self.selectedModel = .smallLatest
        }
        self.lastCoachReport = UserDefaults.standard.string(forKey: Self.lastReportDefaultsKey) ?? ""
    }

    // MARK: - Secure Local Storage (Keychain with UserDefaults fallback for unsigned TrollStore IPAs)

    private static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
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
        return UserDefaults.standard.string(forKey: fallbackDefaultsKey) ?? ""
    }

    private func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(baseQuery as CFDictionary)

        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.fallbackDefaultsKey)
            return
        }

        if let data = trimmed.data(using: .utf8) {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status != errSecSuccess {
                UserDefaults.standard.set(trimmed, forKey: Self.fallbackDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.fallbackDefaultsKey)
            }
        }
    }

    // MARK: - Connection Test

    func testConnection() async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MistralAIError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MistralAIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw MistralAIError.apiError(http.statusCode, msg)
        }

        struct ModelsList: Decodable {
            struct ModelEntry: Decodable { let id: String }
            let data: [ModelEntry]
        }
        if let decoded = try? JSONDecoder().decode(ModelsList.self, from: data) {
            return "Verbunden! \(decoded.data.count) Mistral-Modelle verfügbar."
        }
        return "Verbindung erfolgreich!"
    }

    // MARK: - Meal Text Analysis

    func analyzeMealText(_ text: String) async throws -> [AIEstimatedFood] {
        let systemPrompt = """
        Du bist ein präziser deutscher Ernährungs-Assistent. Zerlege die beschriebene Mahlzeit in einzelne Lebensmittel mit realistischen Nährwerten pro 100g und geschätzter Portionsgröße in Gramm.
        Antworte AUSSCHLIESSLICH mit einem validen JSON-Objekt im Format:
        {
          "items": [
            {
              "name": "Magerquark",
              "grams": 250,
              "caloriesPer100g": 67,
              "proteinPer100g": 12.0,
              "carbsPer100g": 4.0,
              "fatPer100g": 0.3,
              "fiberPer100g": 0.0,
              "note": "optionaler kurzer Hinweis"
            }
          ]
        }
        Keine Erklärungen außerhalb des JSON.
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]

        let content = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: true,
            temperature: 0.2
        )
        return try parseEstimatedFoods(from: content)
    }

    // MARK: - Meal Photo Analysis (Vision)

    func analyzeMealPhoto(_ image: UIImage, hint: String? = nil) async throws -> [AIEstimatedFood] {
        guard let base64 = encodeImageForVision(image) else {
            throw MistralAIError.decodingFailed("Bild konnte nicht komprimiert werden.")
        }

        let systemPrompt = """
        Du bist ein präziser deutscher Ernährungs- und Vision-Assistent.
        Analysiere das Foto:
        - Wenn es ein Teller/Essen ist: Erkenne alle sichtbaren Komponenten, schätze realistische Portionsgrößen in Gramm und gib die Nährwerte pro 100g an.
        - Wenn es eine Nährwerttabelle / Verpackung ist: Lies die exakten Nährwerte pro 100g ab und setze grams auf eine typische Portion (oder 100g).
        Antworte AUSSCHLIESSLICH mit einem validen JSON-Objekt im Format:
        {
          "items": [
            {
              "name": "Hähnchenbrust gebraten",
              "grams": 180,
              "caloriesPer100g": 165,
              "proteinPer100g": 31.0,
              "carbsPer100g": 0.0,
              "fatPer100g": 3.6,
              "fiberPer100g": 0.0,
              "note": "geschätzte Portion"
            }
          ]
        }
        Keine Erklärungen außerhalb des JSON.
        """

        var userText = "Bitte analysiere dieses Foto und gib alle erkannten Lebensmittel als JSON zurück."
        if let hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            userText += " Zusatzhinweis vom Nutzer: \(hint)"
        }

        let userContent: [[String: Any]] = [
            ["type": "text", "text": userText],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
        ]

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]

        let content = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: true,
            temperature: 0.2
        )
        return try parseEstimatedFoods(from: content)
    }

    // MARK: - AI Coach Analysis

    func generateCoachingReport(dataSummary: String, question: String) async throws -> String {
        let systemPrompt = """
        Du bist ein evidenzbasierter Kraftsport-, Hypertrophie- und Ernährungs-Coach (auf Deutsch, per Du).
        Du analysierst die echten Trainings- und Ernährungsdaten des Nutzers aus StrongTracker.
        Strukturiere deine Antwort klar, knapp und praxisnah mit kurzen Abschnitten und Bulletpoints:
        1. Was richtig gut läuft
        2. Auffälligkeiten / Baustellen
        3. Konkrete Empfehlungen für die nächste Woche
        Bleibe realistisch, wissenschaftlich fundiert (Hypertrophie 10–20 Sätze/Muskelgruppe, Protein ~1,8–2,2 g/kg, Progressive Overload) und vermeide Floskeln.
        """

        let userMessage = """
        Hier sind meine aktuellen Daten aus StrongTracker:
        \(dataSummary)

        Meine Frage / Fokus:
        \(question)
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let content = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: false,
            temperature: 0.4
        )
        await MainActor.run {
            self.lastCoachReport = content
        }
        return content
    }

    // MARK: - AI Training Plan Generator

    struct AIGeneratedExerciseSpec: Identifiable, Decodable {
        var id: String = UUID().uuidString
        let exerciseName: String
        let targetSets: Int
        let targetReps: Int
        let restSeconds: Int

        enum CodingKeys: String, CodingKey {
            case exerciseName, targetSets, targetReps, restSeconds
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID().uuidString
            exerciseName = try c.decode(String.self, forKey: .exerciseName)
            targetSets = max(1, min(8, (try? c.decode(Int.self, forKey: .targetSets)) ?? 3))
            targetReps = max(3, min(30, (try? c.decode(Int.self, forKey: .targetReps)) ?? 10))
            restSeconds = max(30, min(300, (try? c.decode(Int.self, forKey: .restSeconds)) ?? 90))
        }
    }

    struct AIGeneratedRoutine: Identifiable, Decodable {
        var id: String = UUID().uuidString
        let name: String
        let notes: String?
        let exercises: [AIGeneratedExerciseSpec]

        enum CodingKeys: String, CodingKey {
            case name, notes, exercises
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID().uuidString
            name = try c.decode(String.self, forKey: .name)
            notes = try? c.decodeIfPresent(String.self, forKey: .notes)
            exercises = (try? c.decode([AIGeneratedExerciseSpec].self, forKey: .exercises)) ?? []
        }
    }

    func generateTrainingPlan(
        daysPerWeek: Int,
        durationMinutes: Int,
        focus: String,
        availableExerciseNames: [String]
    ) async throws -> [AIGeneratedRoutine] {
        let exerciseList = availableExerciseNames.joined(separator: ", ")
        let systemPrompt = """
        Du bist ein evidenzbasierter Kraftsport- & Hypertrophie-Coach.
        Erstelle einen strukturierten Trainingsplan mit genau \(daysPerWeek) Einheiten pro Woche (ca. \(durationMinutes) Min. pro Einheit).
        Verwende nach Möglichkeit EXAKT die Übungsnamen aus dieser vorhandenen Bibliothek:
        \(exerciseList)

        Antworte AUSSCHLIESSLICH mit validem JSON im Format:
        {
          "routines": [
            {
              "name": "Oberkörper A",
              "notes": "Fokus Brust & Rücken",
              "exercises": [
                { "exerciseName": "Bankdrücken (Langhantel)", "targetSets": 3, "targetReps": 8, "restSeconds": 150 }
              ]
            }
          ]
        }
        Keine Erklärungen außerhalb des JSON.
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Fokus / Wunsch: \(focus)"]
        ]

        let raw = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: true,
            temperature: 0.3
        )

        struct Wrapper: Decodable { let routines: [AIGeneratedRoutine] }
        let jsonStr = extractJSONSubstring(from: raw)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Wrapper.self, from: data),
              !decoded.routines.isEmpty else {
            throw MistralAIError.decodingFailed("Trainingsplan konnte nicht als JSON gelesen werden.")
        }
        return decoded.routines
    }

    // MARK: - AI Macro Recipe Chef

    struct AIGeneratedRecipe: Decodable {
        let title: String
        let prepTimeMinutes: Int
        let steps: [String]
        let ingredients: [AIEstimatedFood]

        enum CodingKeys: String, CodingKey {
            case title, prepTimeMinutes, steps, ingredients
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decode(String.self, forKey: .title)) ?? "High-Protein Rezept"
            prepTimeMinutes = max(2, (try? c.decode(Int.self, forKey: .prepTimeMinutes)) ?? 10)
            steps = (try? c.decode([String].self, forKey: .steps)) ?? []
            ingredients = (try? c.decode([AIEstimatedFood].self, forKey: .ingredients)) ?? []
        }
    }

    func generateMacroRecipe(
        remainingCalories: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        remainingFat: Int,
        availableIngredients: String,
        style: String
    ) async throws -> AIGeneratedRecipe {
        let systemPrompt = """
        Du bist ein deutscher Fitness-Koch & Ernährungs-Assistent.
        Erstelle EIN schnelles, realistisches, leckeres Rezept, das möglichst genau in das offene Makro-Budget des Nutzers passt.
        Antworte AUSSCHLIESSLICH mit validem JSON im Format:
        {
          "title": "Beeren-Skyr Protein-Bowl",
          "prepTimeMinutes": 5,
          "steps": ["Skyr in eine Schüssel geben.", "Haferflocken & Beeren darüber geben."],
          "ingredients": [
            {
              "name": "Skyr Natur",
              "grams": 250,
              "caloriesPer100g": 63,
              "proteinPer100g": 11.0,
              "carbsPer100g": 4.0,
              "fatPer100g": 0.2,
              "fiberPer100g": 0.0
            }
          ]
        }
        Keine Erklärungen außerhalb des JSON.
        """

        let userPrompt = """
        Offenes Tagesbudget: ca. \(max(150, remainingCalories)) kcal, ca. \(max(15, remainingProtein))g Eiweiß, ca. \(max(0, remainingCarbs))g Kohlenhydrate, ca. \(max(0, remainingFat))g Fett.
        Gewünschter Stil: \(style)
        Vorhandene Zutaten / Wünsche: \(availableIngredients.isEmpty ? "Egal, einfache Supermarkt-Zutaten" : availableIngredients)
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let raw = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: true,
            temperature: 0.4
        )

        let jsonStr = extractJSONSubstring(from: raw)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIGeneratedRecipe.self, from: data),
              !decoded.ingredients.isEmpty else {
            throw MistralAIError.decodingFailed("Rezept konnte nicht geparst werden.")
        }
        return decoded
    }

    // MARK: - AI Nutrition Label Scanner (for Custom Food Form)

    struct AIScannedNutritionLabel: Decodable {
        let name: String?
        let brand: String?
        let servingSizeGrams: Double?
        let caloriesPer100g: Double?
        let proteinPer100g: Double?
        let carbsPer100g: Double?
        let fatPer100g: Double?
        let fiberPer100g: Double?
        let sugarPer100g: Double?
        let saltPer100g: Double?
    }

    func scanNutritionLabel(_ image: UIImage) async throws -> AIScannedNutritionLabel {
        guard let base64 = encodeImageForVision(image) else {
            throw MistralAIError.decodingFailed("Bild konnte nicht verarbeitet werden.")
        }

        let systemPrompt = """
        Du liest Nährwerttabellen von Lebensmittelverpackungen präzise aus (Werte pro 100g / 100ml).
        Antworte AUSSCHLIESSLICH mit validem JSON:
        {
          "name": "Produktname falls sichtbar oder null",
          "brand": "Marke falls sichtbar oder null",
          "servingSizeGrams": 100,
          "caloriesPer100g": 240,
          "proteinPer100g": 12.5,
          "carbsPer100g": 30.0,
          "fatPer100g": 6.5,
          "fiberPer100g": 4.0,
          "sugarPer100g": 5.0,
          "saltPer100g": 0.8
        }
        Nutze null für Werte, die nicht lesbar sind.
        """

        let userContent: [[String: Any]] = [
            ["type": "text", "text": "Lies die Nährwerttabelle pro 100g aus diesem Foto aus."],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
        ]

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]

        let raw = try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: true,
            temperature: 0.1
        )

        let jsonStr = extractJSONSubstring(from: raw)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIScannedNutritionLabel.self, from: data) else {
            throw MistralAIError.decodingFailed("Nährwerttabelle konnte nicht ausgelesen werden.")
        }
        return decoded
    }

    // MARK: - Post-Workout Recap Feedback

    func generateWorkoutFeedback(recap: CompletedWorkoutRecap) async throws -> String {
        let mins = max(1, recap.durationSeconds / 60)
        let prs = recap.prDescriptions.isEmpty ? "Keine neuen PRs" : recap.prDescriptions.joined(separator: "; ")

        let systemPrompt = """
        Du bist ein motivierender, evidenzbasierter Kraftsport-Coach (auf Deutsch, per Du).
        Gib in genau 3 kurzen, knackigen Stichpunkten (ohne Floskeln) Feedback zum gerade abgeschlossenen Training:
        1. Einordnung von Volumen & Dauer
        2. Lob zu PRs oder Konstanz
        3. Ein konkreter Tipp für Regeneration / nächstes Training (Protein/Schlaf/Progression).
        """

        let hrLine: String
        if let avgHR = recap.avgHeartRate {
            let maxPart = recap.maxHeartRate.map { " | Max-Puls: \($0) bpm" } ?? ""
            hrLine = "\nHerzfrequenz: Ø \(avgHR) bpm\(maxPart)"
        } else {
            hrLine = ""
        }

        let userText = """
        Gerade abgeschlossenes Workout: \(recap.workoutName)
        Dauer: \(mins) Min. | Übungen: \(recap.exerciseCount) | Abgehakte Sätze: \(recap.completedSets) | Gesamtvolumen: \(Formatters.weight(recap.totalVolumeKg)) kg\(hrLine)
        Neue Bestleistungen: \(prs)
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userText]
        ]

        return try await sendChatCompletion(
            model: selectedModel.rawValue,
            messages: messages,
            expectJSON: false,
            temperature: 0.4
        )
    }

    private func extractJSONSubstring(from raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end {
            return String(cleaned[start...end])
        }
        return cleaned
    }

    // MARK: - HTTP Core

    private func sendChatCompletion(
        model: String,
        messages: [[String: Any]],
        expectJSON: Bool,
        temperature: Double
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MistralAIError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature
        ]
        if expectJSON {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MistralAIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let errText = String(data: data, encoding: .utf8) ?? "Unbekannter API-Fehler"
            throw MistralAIError.apiError(http.statusCode, errText)
        }

        let text = try extractAssistantText(from: data)
        guard !text.isEmpty else {
            throw MistralAIError.invalidResponse
        }
        return text
    }

    /// Supports both classic String `message.content` and Mistral Large 4 / Small 4 chunked reasoning arrays
    /// (`[{"type": "thinking", ...}, {"type": "text", "text": "..."}]`).
    private func extractAssistantText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw MistralAIError.invalidResponse
        }

        if let plainString = message["content"] as? String {
            return plainString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let chunks = message["content"] as? [[String: Any]] {
            var textParts: [String] = []
            for chunk in chunks {
                let type = (chunk["type"] as? String)?.lowercased() ?? ""
                // Skip internal reasoning/thinking blocks
                if type == "thinking" || type == "reasoning" {
                    continue
                }
                if let t = chunk["text"] as? String, !t.isEmpty {
                    textParts.append(t)
                } else if let c = chunk["content"] as? String, !c.isEmpty {
                    textParts.append(c)
                }
            }
            let joined = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                return joined
            }
        }

        throw MistralAIError.decodingFailed("Antwort enthielt keinen lesbaren Text.")
    }

    private func parseEstimatedFoods(from rawContent: String) throws -> [AIEstimatedFood] {
        var cleaned = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct Wrapper: Decodable {
            let items: [AIEstimatedFood]
        }

        func tryDecode(_ candidate: String) -> [AIEstimatedFood]? {
            guard let data = candidate.data(using: .utf8) else { return nil }
            if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data), !wrapped.items.isEmpty {
                return wrapped.items
            }
            if let directArray = try? JSONDecoder().decode([AIEstimatedFood].self, from: data), !directArray.isEmpty {
                return directArray
            }
            return nil
        }

        if let decoded = tryDecode(cleaned) {
            return decoded
        }

        // Fallback: extract first JSON object or array substring if model added prose
        if let startObj = cleaned.firstIndex(of: "{"), let endObj = cleaned.lastIndex(of: "}"), startObj < endObj {
            if let decoded = tryDecode(String(cleaned[startObj...endObj])) {
                return decoded
            }
        }
        if let startArr = cleaned.firstIndex(of: "["), let endArr = cleaned.lastIndex(of: "]"), startArr < endArr {
            if let decoded = tryDecode(String(cleaned[startArr...endArr])) {
                return decoded
            }
        }

        throw MistralAIError.decodingFailed("Keine Lebensmittel in der KI-Antwort erkannt.")
    }

    private func encodeImageForVision(_ image: UIImage) -> String? {
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.72)?.base64EncodedString()
    }
}
