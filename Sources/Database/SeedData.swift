import Foundation
import GRDB

enum SeedData {
    static func defaultExercises(createdAt: Date = Date()) -> [Exercise] {
        let items: [(String, String, MuscleGroup, Equipment, Int)] = [
            // Brust
            ("seed-bench-press-barbell", "Bankdrücken (Langhantel)", .chest, .barbell, 150),
            ("seed-incline-bench-dumbbell", "Schrägbankdrücken (Kurzhantel)", .chest, .dumbbell, 120),
            ("seed-chest-press-machine", "Brustpresse (Maschine)", .chest, .machine, 90),
            ("seed-cable-fly", "Cable Flys", .chest, .cable, 60),
            ("seed-dips-chest", "Dips", .chest, .bodyweight, 120),
            ("seed-pushups", "Liegestütze", .chest, .bodyweight, 60),

            // Rücken
            ("seed-deadlift-barbell", "Kreuzheben (Langhantel)", .back, .barbell, 180),
            ("seed-pullups", "Klimmzüge", .back, .bodyweight, 120),
            ("seed-lat-pulldown", "Latzug", .back, .cable, 90),
            ("seed-barbell-row", "Langhantelrudern", .back, .barbell, 120),
            ("seed-seated-cable-row", "Sitzendes Kabelrudern", .back, .cable, 90),
            ("seed-dumbbell-row", "Einarmiges Kurzhantelrudern", .back, .dumbbell, 90),

            // Schultern
            ("seed-overhead-press-barbell", "Schulterdrücken (Langhantel)", .shoulders, .barbell, 120),
            ("seed-overhead-press-dumbbell", "Schulterdrücken (Kurzhantel)", .shoulders, .dumbbell, 120),
            ("seed-lateral-raise-dumbbell", "Seitheben (Kurzhantel)", .shoulders, .dumbbell, 60),
            ("seed-lateral-raise-cable", "Seitheben (Kabelzug)", .shoulders, .cable, 60),
            ("seed-face-pulls", "Face Pulls", .shoulders, .cable, 60),
            ("seed-reverse-fly-machine", "Reverse Butterfly (Maschine)", .shoulders, .machine, 60),

            // Beine
            ("seed-squat-barbell", "Kniebeugen (Langhantel)", .legs, .barbell, 180),
            ("seed-romanian-deadlift", "Rumänisches Kreuzheben", .legs, .barbell, 150),
            ("seed-leg-press", "Beinpresse", .legs, .machine, 120),
            ("seed-bulgarian-split-squat", "Bulgarian Split Squats", .legs, .dumbbell, 90),
            ("seed-leg-extension", "Beinstrecker (Maschine)", .legs, .machine, 60),
            ("seed-leg-curl", "Beinbeuger (Maschine)", .legs, .machine, 60),
            ("seed-standing-calf-raise", "Wadenheben stehend", .legs, .machine, 60),

            // Bizeps
            ("seed-barbell-curl", "Bizepscurls (Langhantel)", .biceps, .barbell, 60),
            ("seed-dumbbell-curl", "Bizepscurls (Kurzhantel)", .biceps, .dumbbell, 60),
            ("seed-hammer-curl", "Hammercurls", .biceps, .dumbbell, 60),
            ("seed-cable-curl", "Bizepscurls (Kabelzug)", .biceps, .cable, 60),

            // Trizeps
            ("seed-triceps-pushdown", "Trizepsdrücken (Kabelzug)", .triceps, .cable, 60),
            ("seed-overhead-triceps-cable", "Überkopf-Trizepsdrücken (Kabelzug)", .triceps, .cable, 60),
            ("seed-skullcrushers", "French Press / Skullcrushers", .triceps, .barbell, 90),

            // Core
            ("seed-hanging-leg-raise", "Hängendes Beinheben", .core, .bodyweight, 60),
            ("seed-cable-crunch", "Cable Crunches", .core, .cable, 60),
            ("seed-plank", "Plank", .core, .bodyweight, 60),
            ("seed-ab-wheel", "Ab-Wheel Rollouts", .core, .other, 60)
        ]

        return items.map { id, name, muscleGroup, equipment, rest in
            Exercise(
                id: id,
                name: name,
                muscleGroup: muscleGroup,
                equipment: equipment,
                defaultRestSeconds: rest,
                isCustom: false,
                isArchived: false,
                notes: nil,
                createdAt: createdAt
            )
        }
    }

    static func insertDefaultExercises(in db: Database) throws {
        for exercise in defaultExercises() {
            try exercise.insert(db, onConflict: .ignore)
        }
    }
}
