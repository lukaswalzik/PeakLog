import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppThemePreset: String, CaseIterable, Identifiable, Codable {
    case liquidBlue
    case obsidian
    case emerald
    case ember
    case violet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidBlue: return "Liquid Blue"
        case .obsidian: return "Obsidian Minimal"
        case .emerald: return "Emerald Vitality"
        case .ember: return "Sunset Ember"
        case .violet: return "Royal Violet"
        }
    }

    var subtitle: String {
        switch self {
        case .liquidBlue: return "Signature Ozeanblau & Indigo (Standard)"
        case .obsidian: return "Reduzierter Graphit- & Silber-Look"
        case .emerald: return "Frisches Smaragdgrün & Teal"
        case .ember: return "Energiegeladenes Orange & Tiefrot"
        case .violet: return "Modernes Ultraviolett & Tiefblau"
        }
    }

    var accentColor: Color {
        switch self {
        case .liquidBlue: return Color(red: 0.12, green: 0.44, blue: 0.96)
        case .obsidian: return Color(red: 0.28, green: 0.36, blue: 0.48)
        case .emerald: return Color(red: 0.06, green: 0.66, blue: 0.48)
        case .ember: return Color(red: 0.92, green: 0.36, blue: 0.14)
        case .violet: return Color(red: 0.46, green: 0.28, blue: 0.94)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .liquidBlue:
            return [
                Color(red: 0.11, green: 0.36, blue: 0.92),
                Color(red: 0.25, green: 0.21, blue: 0.82)
            ]
        case .obsidian:
            return [
                Color(red: 0.14, green: 0.16, blue: 0.20),
                Color(red: 0.24, green: 0.28, blue: 0.35)
            ]
        case .emerald:
            return [
                Color(red: 0.04, green: 0.56, blue: 0.44),
                Color(red: 0.07, green: 0.42, blue: 0.56)
            ]
        case .ember:
            return [
                Color(red: 0.88, green: 0.32, blue: 0.12),
                Color(red: 0.68, green: 0.12, blue: 0.26)
            ]
        case .violet:
            return [
                Color(red: 0.36, green: 0.18, blue: 0.86),
                Color(red: 0.18, green: 0.16, blue: 0.58)
            ]
        }
    }

    var heroGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

final class ThemeManager: ObservableObject {
    private static let appearanceKey = "strongtracker.theme.appearance.v1"
    private static let presetKey = "strongtracker.theme.preset.v1"
    private static let compactStartKey = "strongtracker.theme.compactStart.v1"

    @Published var appearance: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    @Published var preset: AppThemePreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
        }
    }

    @Published var compactStartScreen: Bool {
        didSet {
            UserDefaults.standard.set(compactStartScreen, forKey: Self.compactStartKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.appearanceKey),
           let parsed = AppAppearanceMode(rawValue: raw) {
            self.appearance = parsed
        } else {
            self.appearance = .system
        }

        if let raw = UserDefaults.standard.string(forKey: Self.presetKey),
           let parsed = AppThemePreset(rawValue: raw) {
            self.preset = parsed
        } else {
            self.preset = .liquidBlue
        }

        if UserDefaults.standard.object(forKey: Self.compactStartKey) != nil {
            self.compactStartScreen = UserDefaults.standard.bool(forKey: Self.compactStartKey)
        } else {
            self.compactStartScreen = true
        }
    }

    var shortSummary: String {
        "\(appearance.displayName) · \(preset.displayName)"
    }
}
