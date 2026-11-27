import Foundation
import GRDB

enum SeedData {
    static func defaultExercises(createdAt: Date = Date()) -> [Exercise] {
        let items: [(String, String, MuscleGroup, Equipment, Int)] = [
            // Brust
            ("seed-bench-press-barbell", "Bankdrücken (Langhantel)", .chest, .barbell, 150),
            ("seed-bench-press-dumbbell", "Bankdrücken (Kurzhantel)", .chest, .dumbbell, 120),
            ("seed-incline-bench-barbell", "Schrägbankdrücken (Langhantel)", .chest, .barbell, 150),
            ("seed-incline-bench-dumbbell", "Schrägbankdrücken (Kurzhantel)", .chest, .dumbbell, 120),
            ("seed-chest-press-machine", "Brustpresse (Maschine)", .chest, .machine, 90),
            ("seed-incline-chest-press-machine", "Schrägbankpresse (Maschine)", .chest, .machine, 90),
            ("seed-butterfly-machine", "Butterfly (Maschine / Pec Deck)", .chest, .machine, 60),
            ("seed-cable-fly", "Cable Flys", .chest, .cable, 60),
            ("seed-dips-chest", "Dips", .chest, .bodyweight, 120),
            ("seed-pushups", "Liegestütze", .chest, .bodyweight, 60),

            // Rücken
            ("seed-deadlift-barbell", "Kreuzheben (Langhantel)", .back, .barbell, 180),
            ("seed-pullups", "Klimmzüge", .back, .bodyweight, 120),
            ("seed-assisted-pullups", "Klimmzüge (Maschine / Unterstützt)", .back, .machine, 90),
            ("seed-lat-pulldown", "Latzug", .back, .cable, 90),
            ("seed-lat-pulldown-close", "Enger Latzug (V-Griff)", .back, .cable, 90),
            ("seed-barbell-row", "Langhantelrudern", .back, .barbell, 120),
            ("seed-seated-cable-row", "Sitzendes Kabelrudern", .back, .cable, 90),
            ("seed-chest-supported-row-machine", "Rudermaschine (Brustgestützt)", .back, .machine, 90),
            ("seed-high-row-machine", "High Row (Maschine)", .back, .machine, 90),
            ("seed-t-bar-row", "T-Bar Rudern", .back, .machine, 120),
            ("seed-dumbbell-row", "Einarmiges Kurzhantelrudern", .back, .dumbbell, 90),
            ("seed-cable-pullover", "Überzüge am Kabelzug", .back, .cable, 60),
            ("seed-back-extension", "Rückenstrecker / Hyperextensions", .back, .bodyweight, 60),
            ("seed-shrugs-dumbbell", "Shrugs / Nackenheben (Kurzhantel)", .back, .dumbbell, 60),

            // Schultern
            ("seed-overhead-press-barbell", "Schulterdrücken (Langhantel)", .shoulders, .barbell, 120),
            ("seed-overhead-press-dumbbell", "Schulterdrücken (Kurzhantel)", .shoulders, .dumbbell, 120),
            ("seed-shoulder-press-machine", "Schulterpresse (Maschine)", .shoulders, .machine, 90),
            ("seed-arnold-press", "Arnold Press (Kurzhantel)", .shoulders, .dumbbell, 90),
            ("seed-lateral-raise-dumbbell", "Seitheben (Kurzhantel)", .shoulders, .dumbbell, 60),
            ("seed-lateral-raise-cable", "Seitheben (Kabelzug)", .shoulders, .cable, 60),
            ("seed-lateral-raise-machine", "Seitheben (Maschine)", .shoulders, .machine, 60),
            ("seed-front-raise-dumbbell", "Frontheben (Kurzhantel)", .shoulders, .dumbbell, 60),
            ("seed-face-pulls", "Face Pulls", .shoulders, .cable, 60),
            ("seed-reverse-fly-machine", "Reverse Butterfly (Maschine)", .shoulders, .machine, 60),

            // Beine
            ("seed-squat-barbell", "Kniebeugen (Langhantel)", .legs, .barbell, 180),
            ("seed-hack-squat", "Hackenschmidt-Kniebeuge (Hack Squat)", .legs, .machine, 120),
            ("seed-goblet-squat", "Goblet Squat (Kurzhantel)", .legs, .dumbbell, 90),
            ("seed-romanian-deadlift", "Rumänisches Kreuzheben", .legs, .barbell, 150),
            ("seed-hip-thrust", "Hip Thrust (Langhantel)", .legs, .barbell, 120),
            ("seed-leg-press", "Beinpresse", .legs, .machine, 120),
            ("seed-bulgarian-split-squat", "Bulgarian Split Squats", .legs, .dumbbell, 90),
            ("seed-lunges-dumbbell", "Ausfallschritte / Lunges (Kurzhantel)", .legs, .dumbbell, 90),
            ("seed-leg-extension", "Beinstrecker (Maschine)", .legs, .machine, 60),
            ("seed-leg-curl", "Beinbeuger liegend (Maschine)", .legs, .machine, 60),
            ("seed-seated-leg-curl", "Beinbeuger sitzend (Maschine)", .legs, .machine, 60),
            ("seed-hip-adduction-machine", "Adduktoren (Maschine)", .legs, .machine, 60),
            ("seed-hip-abduction-machine", "Abduktoren (Maschine)", .legs, .machine, 60),
            ("seed-standing-calf-raise", "Wadenheben stehend", .legs, .machine, 60),
            ("seed-seated-calf-raise", "Wadenheben sitzend (Maschine)", .legs, .machine, 60),

            // Bizeps
            ("seed-barbell-curl", "Bizepscurls (Langhantel)", .biceps, .barbell, 60),
            ("seed-ez-bar-curl", "SZ-Bizepscurls", .biceps, .barbell, 60),
            ("seed-dumbbell-curl", "Bizepscurls (Kurzhantel)", .biceps, .dumbbell, 60),
            ("seed-incline-dumbbell-curl", "Schrägbank-Curls (Kurzhantel)", .biceps, .dumbbell, 60),
            ("seed-hammer-curl", "Hammercurls", .biceps, .dumbbell, 60),
            ("seed-preacher-curl", "Scottcurls / Preacher Curls (Maschine)", .biceps, .machine, 60),
            ("seed-concentration-curl", "Konzentrationscurls (Kurzhantel)", .biceps, .dumbbell, 60),
            ("seed-cable-curl", "Bizepscurls (Kabelzug)", .biceps, .cable, 60),

            // Trizeps
            ("seed-triceps-pushdown", "Trizepsdrücken (Kabelzug)", .triceps, .cable, 60),
            ("seed-overhead-triceps-cable", "Überkopf-Trizepsdrücken (Kabelzug)", .triceps, .cable, 60),
            ("seed-overhead-triceps-dumbbell", "Überkopf-Trizepsdrücken (Kurzhantel)", .triceps, .dumbbell, 60),
            ("seed-skullcrushers", "French Press / Skullcrushers", .triceps, .barbell, 90),
            ("seed-triceps-dip-machine", "Dip-Maschine (Trizeps)", .triceps, .machine, 90),
            ("seed-close-grip-bench", "Enges Bankdrücken (Langhantel)", .triceps, .barbell, 120),
            ("seed-triceps-kickbacks", "Trizeps-Kickbacks (Kurzhantel)", .triceps, .dumbbell, 60),

            // Core
            ("seed-hanging-leg-raise", "Hängendes Beinheben", .core, .bodyweight, 60),
            ("seed-captain-chair-leg-raise", "Beinheben (Captain's Chair)", .core, .bodyweight, 60),
            ("seed-ab-crunch-machine", "Bauchpresse / Crunch-Maschine", .core, .machine, 60),
            ("seed-cable-crunch", "Cable Crunches", .core, .cable, 60),
            ("seed-cable-woodchopper", "Cable Woodchopper", .core, .cable, 60),
            ("seed-russian-twist", "Russian Twist", .core, .bodyweight, 60),
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
