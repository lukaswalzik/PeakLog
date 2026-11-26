import Foundation
import GRDB

final class AppDatabase {
    static let shared: AppDatabase = makeShared()

    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Migrations.makeMigrator().migrate(dbWriter)
    }

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = appSupportURL.appendingPathComponent("StrongTracker", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("strongtracker.sqlite")
            var config = Configuration()
            config.foreignKeysEnabled = true

            let dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
            return try AppDatabase(dbPool)
        } catch {
            fatalError("Fehler beim Initialisieren der StrongTracker-Datenbank: \(error)")
        }
    }

    static func makeInMemory() -> AppDatabase {
        do {
            var config = Configuration()
            config.foreignKeysEnabled = true
            let dbQueue = try DatabaseQueue(configuration: config)
            return try AppDatabase(dbQueue)
        } catch {
            fatalError("Fehler beim Erstellen der In-Memory-Datenbank: \(error)")
        }
    }
}

// MARK: - Exercise Operations

extension AppDatabase {
    func saveExercise(_ exercise: Exercise) throws {
        try dbWriter.write { db in
            try exercise.save(db)
        }
    }

    func archiveOrDeleteExercise(id: String) throws {
        try dbWriter.write { db in
            let usedInRoutines = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM routine_exercises WHERE exerciseId = ?",
                arguments: [id]
            ) ?? 0
            let usedInWorkouts = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM workout_exercises WHERE exerciseId = ?",
                arguments: [id]
            ) ?? 0

            if usedInRoutines == 0 && usedInWorkouts == 0 {
                _ = try Exercise.deleteOne(db, key: id)
            } else {
                try db.execute(
                    sql: "UPDATE exercises SET isArchived = 1 WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }
}

// MARK: - Routine Operations

extension AppDatabase {
    static func fetchRoutinesWithExercises(in db: Database) throws -> [RoutineWithExercises] {
        let routines = try Routine
            .order(Routine.Columns.sortOrder.asc, Routine.Columns.createdAt.desc)
            .fetchAll(db)

        guard !routines.isEmpty else { return [] }

        let allRoutineExercises = try RoutineExercise
            .order(RoutineExercise.Columns.sortOrder.asc)
            .fetchAll(db)

        let exerciseIds = Set(allRoutineExercises.map { $0.exerciseId })
        let exercisesById: [String: Exercise]
        if exerciseIds.isEmpty {
            exercisesById = [:]
        } else {
            let exercises = try Exercise
                .filter(exerciseIds.contains(Exercise.Columns.id))
                .fetchAll(db)
            exercisesById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        }

        let groupedByRoutine = Dictionary(grouping: allRoutineExercises, by: { $0.routineId })

        return routines.map { routine in
            let items = (groupedByRoutine[routine.id] ?? []).compactMap { re -> RoutineExerciseDetail? in
                guard let exercise = exercisesById[re.exerciseId] else { return nil }
                return RoutineExerciseDetail(routineExercise: re, exercise: exercise)
            }
            return RoutineWithExercises(routine: routine, exercises: items)
        }
    }

    func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) throws {
        try dbWriter.write { db in
            var updatedRoutine = routine
            updatedRoutine.updatedAt = Date()
            try updatedRoutine.save(db)

            try RoutineExercise
                .filter(RoutineExercise.Columns.routineId == updatedRoutine.id)
                .deleteAll(db)

            for (index, item) in exercises.enumerated() {
                var normalized = item
                normalized.routineId = updatedRoutine.id
                normalized.sortOrder = index
                try normalized.insert(db)
            }
        }
    }

    func deleteRoutine(id: String) throws {
        try dbWriter.write { db in
            _ = try Routine.deleteOne(db, key: id)
        }
    }

    func reorderRoutines(ids: [String]) throws {
        try dbWriter.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE routines SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                    arguments: [index, Date(), id]
                )
            }
        }
    }
}

// MARK: - Workout Operations

extension AppDatabase {
    static func fetchActiveWorkoutDetail(in db: Database) throws -> WorkoutDetail? {
        guard let activeWorkout = try Workout
            .filter(Workout.Columns.finishedAt == nil)
            .order(Workout.Columns.startedAt.desc)
            .fetchOne(db) else {
            return nil
        }

        return try fetchWorkoutDetail(for: activeWorkout, includePreviousSets: true, in: db)
    }

    static func fetchWorkoutDetail(
        for workout: Workout,
        includePreviousSets: Bool,
        in db: Database
    ) throws -> WorkoutDetail {
        let workoutExercises = try WorkoutExercise
            .filter(WorkoutExercise.Columns.workoutId == workout.id)
            .order(WorkoutExercise.Columns.sortOrder.asc)
            .fetchAll(db)

        guard !workoutExercises.isEmpty else {
            return WorkoutDetail(workout: workout, exercises: [])
        }

        let exerciseIds = Set(workoutExercises.map { $0.exerciseId })
        let exercises = try Exercise
            .filter(exerciseIds.contains(Exercise.Columns.id))
            .fetchAll(db)
        let exercisesById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        let weIds = workoutExercises.map { $0.id }
        let allSets = try WorkoutSet
            .filter(weIds.contains(WorkoutSet.Columns.workoutExerciseId))
            .order(WorkoutSet.Columns.setOrder.asc)
            .fetchAll(db)
        let setsByWorkoutExercise = Dictionary(grouping: allSets, by: { $0.workoutExerciseId })

        let details: [WorkoutExerciseDetail] = try workoutExercises.compactMap { we in
            guard let exercise = exercisesById[we.exerciseId] else { return nil }
            let sets = setsByWorkoutExercise[we.id] ?? []
            let previousSets: [Int: PreviousSetReference]
            if includePreviousSets {
                previousSets = try fetchPreviousSets(forExerciseId: we.exerciseId, excludingWorkoutId: workout.id, in: db)
            } else {
                previousSets = [:]
            }
            return WorkoutExerciseDetail(
                workoutExercise: we,
                exercise: exercise,
                sets: sets,
                previousSets: previousSets
            )
        }

        return WorkoutDetail(workout: workout, exercises: details)
    }

    private static func fetchPreviousSets(
        forExerciseId exerciseId: String,
        excludingWorkoutId: String,
        in db: Database
    ) throws -> [Int: PreviousSetReference] {
        let previousWorkoutExerciseId = try String.fetchOne(
            db,
            sql: """
                SELECT we.id
                FROM workout_exercises we
                JOIN workouts w ON w.id = we.workoutId
                WHERE we.exerciseId = ?
                  AND w.id != ?
                  AND w.finishedAt IS NOT NULL
                ORDER BY w.startedAt DESC
                LIMIT 1
                """,
            arguments: [exerciseId, excludingWorkoutId]
        )

        guard let prevWeId = previousWorkoutExerciseId else {
            return [:]
        }

        let prevSets = try WorkoutSet
            .filter(WorkoutSet.Columns.workoutExerciseId == prevWeId && WorkoutSet.Columns.isCompleted == true)
            .order(WorkoutSet.Columns.setOrder.asc)
            .fetchAll(db)

        var result: [Int: PreviousSetReference] = [:]
        for (index, set) in prevSets.enumerated() {
            result[index + 1] = PreviousSetReference(weightKg: set.weightKg, reps: set.reps)
        }
        return result
    }

    func startEmptyWorkout(name: String = "Freies Training") throws -> String {
        let workout = Workout(name: name, startedAt: Date(), finishedAt: nil)
        try dbWriter.write { db in
            try workout.insert(db)
        }
        return workout.id
    }

    func startWorkout(from routineDetail: RoutineWithExercises) throws -> String {
        let workout = Workout(
            routineId: routineDetail.routine.id,
            name: routineDetail.routine.name,
            startedAt: Date(),
            finishedAt: nil,
            notes: routineDetail.routine.notes
        )

        try dbWriter.write { db in
            try workout.insert(db)

            for (index, item) in routineDetail.exercises.enumerated() {
                let we = WorkoutExercise(
                    workoutId: workout.id,
                    exerciseId: item.exercise.id,
                    sortOrder: index,
                    restSeconds: item.effectiveRestSeconds,
                    notes: item.routineExercise.notes
                )
                try we.insert(db)

                let setCount = max(1, item.routineExercise.targetSets)
                for setIndex in 1...setCount {
                    let set = WorkoutSet(
                        workoutExerciseId: we.id,
                        setOrder: setIndex,
                        setType: .normal,
                        weightKg: nil,
                        reps: nil,
                        isCompleted: false,
                        completedAt: nil
                    )
                    try set.insert(db)
                }
            }
        }
        return workout.id
    }

    func addExercisesToWorkout(workoutId: String, exercises: [Exercise]) throws {
        try dbWriter.write { db in
            let currentMaxOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sortOrder), -1) FROM workout_exercises WHERE workoutId = ?",
                arguments: [workoutId]
            ) ?? -1

            for (offset, exercise) in exercises.enumerated() {
                let we = WorkoutExercise(
                    workoutId: workoutId,
                    exerciseId: exercise.id,
                    sortOrder: currentMaxOrder + 1 + offset,
                    restSeconds: exercise.defaultRestSeconds,
                    notes: nil
                )
                try we.insert(db)

                let initialSet = WorkoutSet(
                    workoutExerciseId: we.id,
                    setOrder: 1,
                    setType: .normal
                )
                try initialSet.insert(db)
            }
        }
    }

    func removeWorkoutExercise(id: String) throws {
        try dbWriter.write { db in
            _ = try WorkoutExercise.deleteOne(db, key: id)
        }
    }

    func addSet(to workoutExerciseId: String) throws {
        try dbWriter.write { db in
            let existingSets = try WorkoutSet
                .filter(WorkoutSet.Columns.workoutExerciseId == workoutExerciseId)
                .order(WorkoutSet.Columns.setOrder.asc)
                .fetchAll(db)

            let nextOrder = (existingSets.last?.setOrder ?? 0) + 1
            let lastSet = existingSets.last
            let newSet = WorkoutSet(
                workoutExerciseId: workoutExerciseId,
                setOrder: nextOrder,
                setType: .normal,
                weightKg: lastSet?.weightKg,
                reps: lastSet?.reps,
                isCompleted: false,
                completedAt: nil
            )
            try newSet.insert(db)
        }
    }

    func updateSet(_ set: WorkoutSet) throws {
        try dbWriter.write { db in
            try set.update(db)
        }
    }

    func deleteSet(id: String, workoutExerciseId: String) throws {
        try dbWriter.write { db in
            _ = try WorkoutSet.deleteOne(db, key: id)

            let remaining = try WorkoutSet
                .filter(WorkoutSet.Columns.workoutExerciseId == workoutExerciseId)
                .order(WorkoutSet.Columns.setOrder.asc)
                .fetchAll(db)

            for (index, var item) in remaining.enumerated() {
                let desiredOrder = index + 1
                if item.setOrder != desiredOrder {
                    item.setOrder = desiredOrder
                    try item.update(db)
                }
            }
        }
    }

    func updateWorkoutHeader(id: String, name: String, notes: String?) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE workouts SET name = ?, notes = ? WHERE id = ?",
                arguments: [name, notes, id]
            )
        }
    }

    func finishWorkout(id: String) throws {
        try dbWriter.write { db in
            // Remove uncompleted sets so history & stats only contain completed work
            try db.execute(
                sql: """
                    DELETE FROM workout_sets
                    WHERE isCompleted = 0
                      AND workoutExerciseId IN (
                          SELECT id FROM workout_exercises WHERE workoutId = ?
                      )
                    """,
                arguments: [id]
            )

            // Remove exercises that have no completed sets left
            try db.execute(
                sql: """
                    DELETE FROM workout_exercises
                    WHERE workoutId = ?
                      AND id NOT IN (SELECT DISTINCT workoutExerciseId FROM workout_sets)
                    """,
                arguments: [id]
            )

            // Re-number remaining sets cleanly per exercise
            let remainingExercises = try WorkoutExercise
                .filter(WorkoutExercise.Columns.workoutId == id)
                .order(WorkoutExercise.Columns.sortOrder.asc)
                .fetchAll(db)

            for (exIndex, var we) in remainingExercises.enumerated() {
                if we.sortOrder != exIndex {
                    we.sortOrder = exIndex
                    try we.update(db)
                }
                let sets = try WorkoutSet
                    .filter(WorkoutSet.Columns.workoutExerciseId == we.id)
                    .order(WorkoutSet.Columns.setOrder.asc)
                    .fetchAll(db)
                for (setIndex, var set) in sets.enumerated() {
                    if set.setOrder != setIndex + 1 {
                        set.setOrder = setIndex + 1
                        try set.update(db)
                    }
                }
            }

            try db.execute(
                sql: "UPDATE workouts SET finishedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    func discardWorkout(id: String) throws {
        try dbWriter.write { db in
            _ = try Workout.deleteOne(db, key: id)
        }
    }
}
