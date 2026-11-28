import Foundation
import SwiftUI

enum CardioPlanTiming: String, CaseIterable, Codable, Identifiable, Hashable {
    case postWorkout
    case restDay
    case flexible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .postWorkout: return "Nach Krafttraining"
        case .restDay: return "Trainingsfreier Tag"
        case .flexible: return "Flexibel"
        }
    }

    var shortBadge: String {
        switch self {
        case .postWorkout: return "Nach Training"
        case .restDay: return "Freier Tag"
        case .flexible: return "Flexibel"
        }
    }

    var systemImage: String {
        switch self {
        case .postWorkout: return "dumbbell.fill"
        case .restDay: return "calendar.badge.clock"
        case .flexible: return "clock"
        }
    }

    var color: Color {
        switch self {
        case .postWorkout: return .blue
        case .restDay: return .green
        case .flexible: return .purple
        }
    }
}

struct CardioPlanSession: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var activityType: CardioActivityType
    var timing: CardioPlanTiming
    var targetDurationMinutes: Int
    var targetZone: HeartRateZone
    var intensityGuide: String
    var notes: String?
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        title: String,
        activityType: CardioActivityType = .walking,
        timing: CardioPlanTiming = .postWorkout,
        targetDurationMinutes: Int = 20,
        targetZone: HeartRateZone = .z2,
        intensityGuide: String = "",
        notes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.activityType = activityType
        self.timing = timing
        self.targetDurationMinutes = max(5, targetDurationMinutes)
        self.targetZone = targetZone
        self.intensityGuide = intensityGuide
        self.notes = notes
        self.sortOrder = sortOrder
    }
}

struct CardioPlan: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var subtitle: String?
    var weeklyGoalSessions: Int
    var progressionNotes: String?
    var sessions: [CardioPlanSession]
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        subtitle: String? = nil,
        weeklyGoalSessions: Int = 3,
        progressionNotes: String? = nil,
        sessions: [CardioPlanSession] = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.weeklyGoalSessions = max(1, min(7, weeklyGoalSessions))
        self.progressionNotes = progressionNotes
        self.sessions = sessions
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalPlannedMinutesPerWeek: Int {
        let sorted = sessions.sorted { $0.sortOrder < $1.sortOrder }
        guard !sorted.isEmpty else { return 0 }
        let count = min(weeklyGoalSessions, sorted.count)
        return sorted.prefix(count).reduce(0) { $0 + $1.targetDurationMinutes }
    }

    /// Pre-installed starter plan tailored for joint-friendly foundational endurance
    /// (brisk incline walking & ergometer, post-workout & rest days, zero jogging).
    static func defaultStarterPlan() -> CardioPlan {
        CardioPlan(
            id: "seed-cardio-plan-grundfitness",
            name: "Grundfitness & Zone-2 Aufbau",
            subtitle: "Gelenkschonend ohne Joggen · Laufband & Ergometer",
            weeklyGoalSessions: 3,
            progressionNotes: """
            • Woche 1–2: Starte mit 2 Einheiten/Woche (1× 15–20 Min nach dem Krafttraining + 1× 25–30 Min am freien Tag). Fokus: Routine & Puls in Zone 2 halten.
            • Woche 3–4: Steigere auf 3 Einheiten/Woche. Erhöhe Steigung (+1 %) oder Widerstand (+10–15 W), sobald dein Puls bei gleichem Tempo niedriger bleibt.
            • Ab Woche 5+: 2× 20–25 Min nach dem Krafttraining + 1× 35–40 Min am freien Tag. Optional alle 1–2 Wochen den sanften Zone-3-Boost am Ergometer einbauen.
            • Faustregel ohne Pulsmesser: Du schwitzt leicht, kannst aber noch ganze Sätze sprechen (oder locker durch die Nase atmen).
            """,
            sessions: [
                CardioPlanSession(
                    id: "seed-cs-incline-post",
                    title: "Post-Workout Incline Walk",
                    activityType: .walking,
                    timing: .postWorkout,
                    targetDurationMinutes: 20,
                    targetZone: .z2,
                    intensityGuide: "4,8–5,5 km/h · 5–8 % Steigung",
                    notes: "3 Min locker einlaufen (0–2 %), dann 15 Min zügig bergauf in Zone 2 ohne am Geländer festzuhalten, 2 Min locker auslaufen. Ideal nach Oberkörper-Einheiten.",
                    sortOrder: 0
                ),
                CardioPlanSession(
                    id: "seed-cs-ergo-post",
                    title: "Post-Workout Ergometer Locker",
                    activityType: .ergometer,
                    timing: .postWorkout,
                    targetDurationMinutes: 20,
                    targetZone: .z2,
                    intensityGuide: "85–120 Watt · 75–85 U/min",
                    notes: "Extrem gelenkschonend – ideal auch nach Beintraining für aktive Durchblutung. Gleichmäßige Trittfrequenz halten und Widerstand sanft an Zone 2 anpassen.",
                    sortOrder: 1
                ),
                CardioPlanSession(
                    id: "seed-cs-restday-base",
                    title: "Rest-Day Grundlagen-Ausdauer",
                    activityType: .ergometer,
                    timing: .restDay,
                    targetDurationMinutes: 35,
                    targetZone: .z2,
                    intensityGuide: "90–130 W (oder Laufband 5,0 km/h @ 5–7 %)",
                    notes: "Die wichtigste Einheit für langfristige Ausdauer: 5 Min locker warmfahren, 25 Min entspannt konstant in Zone 2 (gerne Podcast/Serie an), 5 Min Cooldown.",
                    sortOrder: 2
                ),
                CardioPlanSession(
                    id: "seed-cs-ergo-z3-boost",
                    title: "Sanfter Herz-Kreislauf-Boost (ab Wo. 3)",
                    activityType: .ergometer,
                    timing: .restDay,
                    targetDurationMinutes: 25,
                    targetZone: .z3,
                    intensityGuide: "4× (3 Min zügig Z3 + 2 Min locker Z1–Z2)",
                    notes: "5 Min Warm-up, dann 4 kontrollierte 3-Minuten-Blöcke mit höherem Widerstand (spürbar fordernd, aber kein All-out-Sprint) im Wechsel mit 2 Min lockerem Ausrollen. Steigert die Kondition spürbar.",
                    sortOrder: 3
                )
            ],
            isActive: true
        )
    }
}
