import Foundation

enum OpenFoodFactsError: LocalizedError {
    case invalidURL
    case notFound
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Suchanfrage."
        case .notFound:
            return "Kein Produkt mit diesem Barcode in Open Food Facts gefunden."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        }
    }
}

enum OpenFoodFactsService {
    private static let userAgent = "PeakLog-iOS/1.0 (local fitness tracker)"

    static func fetchProduct(barcode: String) async throws -> FoodItem {
        let cleaned = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(cleaned).json") else {
            throw OpenFoodFactsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 18

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenFoodFactsError.networkError(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw OpenFoodFactsError.notFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any],
              let food = parseProduct(product, fallbackBarcode: cleaned) else {
            throw OpenFoodFactsError.notFound
        }

        return food
    }

    static func searchProducts(query: String) async throws -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Try German Open Food Facts first, fallback to world if needed
        do {
            let results = try await performSearch(host: "de.openfoodfacts.org", query: trimmed)
            if !results.isEmpty {
                return results
            }
            return try await performSearch(host: "world.openfoodfacts.org", query: trimmed)
        } catch {
            return try await performSearch(host: "world.openfoodfacts.org", query: trimmed)
        }
    }

    private static func performSearch(host: String, query: String) async throws -> [FoodItem] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/cgi/search.pl"
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_de,brands,serving_quantity,nutriments")
        ]

        guard let url = components.url else {
            throw OpenFoodFactsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenFoodFactsError.networkError(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            return []
        }

        return products.compactMap { parseProduct($0, fallbackBarcode: nil) }
    }

    private static func parseProduct(_ dict: [String: Any], fallbackBarcode: String?) -> FoodItem? {
        let deName = (dict["product_name_de"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultName = (dict["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = !deName.isEmpty ? deName : defaultName
        guard !name.isEmpty else { return nil }

        let brand = (dict["brands"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let barcode = (dict["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackBarcode
        let nutriments = dict["nutriments"] as? [String: Any] ?? [:]

        let kcal: Double
        if let directKcal = doubleValue(nutriments["energy-kcal_100g"]) {
            kcal = directKcal
        } else if let kj = doubleValue(nutriments["energy-kj_100g"]) {
            kcal = kj / 4.184
        } else if let energy = doubleValue(nutriments["energy_100g"]) {
            kcal = energy > 1200 ? energy / 4.184 : energy
        } else {
            kcal = 0
        }

        let protein = doubleValue(nutriments["proteins_100g"]) ?? 0
        let carbs = doubleValue(nutriments["carbohydrates_100g"]) ?? 0
        let fat = doubleValue(nutriments["fat_100g"]) ?? 0
        let fiber = doubleValue(nutriments["fiber_100g"]) ?? 0
        let sugar = doubleValue(nutriments["sugars_100g"]) ?? 0
        let salt = doubleValue(nutriments["salt_100g"]) ?? 0

        let rawVitC = doubleValue(nutriments["vitamin-c_100g"]) ?? 0
        let vitCMg = rawVitC > 0 && rawVitC < 1.0 ? rawVitC * 1000.0 : rawVitC

        let rawCalcium = doubleValue(nutriments["calcium_100g"]) ?? 0
        let calciumMg = rawCalcium > 0 && rawCalcium < 5.0 ? rawCalcium * 1000.0 : rawCalcium

        let rawIron = doubleValue(nutriments["iron_100g"]) ?? 0
        let ironMg = rawIron > 0 && rawIron < 1.0 ? rawIron * 1000.0 : rawIron

        let servingGrams = doubleValue(dict["serving_quantity"]) ?? 100

        return FoodItem(
            id: (barcode?.isEmpty == false) ? "off-\(barcode!)" : UUID().uuidString,
            name: name,
            brand: (brand?.isEmpty ?? true) ? nil : brand,
            barcode: (barcode?.isEmpty ?? true) ? nil : barcode,
            servingSizeGrams: max(1, servingGrams),
            caloriesPer100g: max(0, kcal),
            proteinPer100g: max(0, protein),
            carbsPer100g: max(0, carbs),
            fatPer100g: max(0, fat),
            fiberPer100g: max(0, fiber),
            sugarPer100g: max(0, sugar),
            saltPer100g: max(0, salt),
            vitaminCMgPer100g: max(0, vitCMg),
            calciumMgPer100g: max(0, calciumMg),
            ironMgPer100g: max(0, ironMg),
            isCustom: false,
            isFavorite: false
        )
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}
