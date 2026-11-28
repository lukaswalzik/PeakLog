import Foundation
import GRDB
import SwiftUI

enum CardioActivityType: String, CaseIterable, Codable, Identifiable, Hashable, DatabaseValueConvertible {
    case running
    case cycling
    case rowing
    case treadmill
    case ergometer
    case stairmaster
    case swimming
    case hiit
    case walking
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Laufen"
        case .cycling: return "Radfahren"
        case .rowing: return "Rudern"
        case .treadmill: return "Laufband"
        case .ergometer: return "Ergometer"
        case .stairmaster: return "Treppensteiger"
        case .swimming: return "Schwimmen"
        case .hiit: return "HIIT"
        case .walking: return "Gehen / Incline"
        case .other: return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .rowing: return "figure.rower"
        case .treadmill: return "speedometer"
        case .ergometer: return "figure.indoor.cycle"
        case .stairmaster: return "figure.stair.stepper"
        case .swimming: return "figure.pool.swim"
        case .hiit: return "flame.fill"
        case .walking: return "figure.walk"
        case .other: return "heart.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .running: return .green
        case .cycling: return .blue
        case .rowing: return .indigo
        case .treadmill: return .teal
        case .ergometer: return .cyan
        case .stairmaster: return .orange
        case .swimming: return .mint
        case .hiit: return .red
        case .walking: return .purple
        case .other: return .pink
        }
    }
}

enum HeartRateZone: Int, CaseIterable, Identifiable, Hashable, Codable {
    case z1 = 1
    case z2 = 2
    case z3 = 3
    case z4 = 4
    case z5 = 5

    var id: Int { rawValue }

    var shortName: String {
        "Z\(rawValue)"
    }

    var title: String {
        switch self {
        case .z1: return "Zone 1 · Regeneration"
        case .z2: return "Zone 2 · Grundlagen"
        case .z3: return "Zone 3 · Aerob"
        case .z4: return "Zone 4 · Schwelle"
        case .z5: return "Zone 5 · Maximal"
        }
    }

    var color: Color {
        switch self {
        case .z1: return .cyan
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }

    var percentBounds: (Double, Double) {
        switch self {
        case .z1: return (0.50, 0.60)
        case .z2: return (0.60, 0.70)
        case .z3: return (0.70, 0.80)
        case .z4: return (0.80, 0.90)
        case .z5: return (0.90, 1.00)
        }
    }

    func bpmRangeText(maxHR: Int) -> String {
        let lower = Int(round(Double(maxHR) * percentBounds.0))
        let upper = Int(round(Double(maxHR) * percentBounds.1))
        return "\(lower)–\(upper) bpm"
    }

    static func zone(for bpm: Int, maxHR: Int) -> HeartRateZone? {
        let safeMax = max(120, maxHR)
        let ratio = Double(bpm) / Double(safeMax)
        if ratio < 0.50 { return nil }
        if ratio < 0.60 { return .z1 }
        if ratio < 0.70 { return .z2 }
        if ratio < 0.80 { return .z3 }
        if ratio < 0.90 { return .z4 }
        return .z5
    }

    static func clampedZone(for bpm: Int, maxHR: Int) -> HeartRateZone {
        zone(for: bpm, maxHR: maxHR) ?? .z1
    }
}

struct CardioSession: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cardio_sessions"

    var id: String
    var activityType: CardioActivityType
    var startedAt: Date
    var durationSeconds: Int
    var distanceKm: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var zone1Seconds: Int
    var zone2Seconds: Int
    var zone3Seconds: Int
    var zone4Seconds: Int
    var zone5Seconds: Int
    var notes: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let activityType = Column(CodingKeys.activityType)
        static let startedAt = Column(CodingKeys.startedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let distanceKm = Column(CodingKeys.distanceKm)
        static let avgHeartRate = Column(CodingKeys.avgHeartRate)
        static let maxHeartRate = Column(CodingKeys.maxHeartRate)
        static let calories = Column(CodingKeys.calories)
        static let zone1Seconds = Column(CodingKeys.zone1Seconds)
        static let zone2Seconds = Column(CodingKeys.zone2Seconds)
        static let zone3Seconds = Column(CodingKeys.zone3Seconds)
        static let zone4Seconds = Column(CodingKeys.zone4Seconds)
        static let zone5Seconds = Column(CodingKeys.zone5Seconds)
        static let notes = Column(CodingKeys.notes)
    }

    init(
        id: String = UUID().uuidString,
        activityType: CardioActivityType = .running,
        startedAt: Date = Date(),
        durationSeconds: Int = 1800,
        distanceKm: Double? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        calories: Int? = nil,
        zone1Seconds: Int = 0,
        zone2Seconds: Int = 0,
        zone3Seconds: Int = 0,
        zone4Seconds: Int = 0,
        zone5Seconds: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.calories = calories
        self.zone1Seconds = zone1Seconds
        self.zone2Seconds = zone2Seconds
        self.zone3Seconds = zone3Seconds
        self.zone4Seconds = zone4Seconds
        self.zone5Seconds = zone5Seconds
        self.notes = notes
    }

    var totalZoneSeconds: Int {
        zone1Seconds + zone2Seconds + zone3Seconds + zone4Seconds + zone5Seconds
    }

    func seconds(for zone: HeartRateZone) -> Int {
        switch zone {
        case .z1: return zone1Seconds
        case .z2: return zone2Seconds
        case .z3: return zone3Seconds
        case .z4: return zone4Seconds
        case .z5: return zone5Seconds
        }
    }

    func fraction(for zone: HeartRateZone) -> Double {
        let total = totalZoneSeconds
        guard total > 0 else { return 0 }
        return Double(seconds(for: zone)) / Double(total)
    }
}
