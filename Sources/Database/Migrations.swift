import Foundation
import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "exercises") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("muscleGroup", .text).notNull()
                t.column("equipment", .text).notNull()
                t.column("defaultRestSeconds", .integer).notNull().defaults(to: 90)
                t.column("isCustom", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "routines") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("notes", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "routine_exercises") { t in
                t.column("id", .text).primaryKey()
                t.column("routineId", .text).notNull().references("routines", onDelete: .cascade)
                t.column("exerciseId", .text).notNull().references("exercises", onDelete: .restrict)
                t.column("sortOrder", .integer).notNull()
                t.column("targetSets", .integer).notNull().defaults(to: 3)
                t.column("targetReps", .integer)
                t.column("restSeconds", .integer)
                t.column("notes", .text)
            }

            try db.create(table: "workouts") { t in
                t.column("id", .text).primaryKey()
                t.column("routineId", .text).references("routines", onDelete: .setNull)
                t.column("name", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("notes", .text)
            }

            try db.create(table: "workout_exercises") { t in
                t.column("id", .text).primaryKey()
                t.column("workoutId", .text).notNull().references("workouts", onDelete: .cascade)
                t.column("exerciseId", .text).notNull().references("exercises", onDelete: .restrict)
                t.column("sortOrder", .integer).notNull()
                t.column("restSeconds", .integer).notNull().defaults(to: 90)
                t.column("notes", .text)
            }

            try db.create(table: "workout_sets") { t in
                t.column("id", .text).primaryKey()
                t.column("workoutExerciseId", .text).notNull().references("workout_exercises", onDelete: .cascade)
                t.column("setOrder", .integer).notNull()
                t.column("setType", .text).notNull().defaults(to: "normal")
                t.column("weightKg", .double)
                t.column("reps", .integer)
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
            }

            try db.create(
                index: "idx_routine_exercises_routineId",
                on: "routine_exercises",
                columns: ["routineId", "sortOrder"]
            )
            try db.create(
                index: "idx_workout_exercises_workoutId",
                on: "workout_exercises",
                columns: ["workoutId", "sortOrder"]
            )
            try db.create(
                index: "idx_workout_exercises_exerciseId",
                on: "workout_exercises",
                columns: ["exerciseId"]
            )
            try db.create(
                index: "idx_workout_sets_workoutExerciseId",
                on: "workout_sets",
                columns: ["workoutExerciseId", "setOrder"]
            )
            try db.create(
                index: "idx_workouts_startedAt",
                on: "workouts",
                columns: ["startedAt"]
            )
        }

        migrator.registerMigration("v1_seed_exercises") { db in
            try SeedData.insertDefaultExercises(in: db)
        }

        migrator.registerMigration("v2_exercise_images") { db in
            try db.alter(table: "exercises") { t in
                t.add(column: "imageFilename", .text)
            }
        }

        migrator.registerMigration("v3_bodyweight") { db in
            try db.create(table: "bodyweight_entries") { t in
                t.column("id", .text).primaryKey()
                t.column("recordedAt", .datetime).notNull()
                t.column("weightKg", .double).notNull()
                t.column("notes", .text)
            }

            try db.create(table: "bodyweight_photos") { t in
                t.column("id", .text).primaryKey()
                t.column("entryId", .text).notNull().references("bodyweight_entries", onDelete: .cascade)
                t.column("imageFilename", .text).notNull()
                t.column("caption", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_bodyweight_entries_recordedAt",
                on: "bodyweight_entries",
                columns: ["recordedAt"]
            )
            try db.create(
                index: "idx_bodyweight_photos_entryId",
                on: "bodyweight_photos",
                columns: ["entryId"]
            )
        }

        return migrator
    }
}
