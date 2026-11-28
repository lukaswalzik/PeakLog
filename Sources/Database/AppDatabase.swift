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
        let gymName: String?
        if let gymId = workout.gymId {
            gymName = try Gym.fetchOne(db, key: gymId)?.name
        } else {
            gymName = nil
        }

        let workoutExercises = try WorkoutExercise
            .filter(WorkoutExercise.Columns.workoutId == workout.id)
            .order(WorkoutExercise.Columns.sortOrder.asc)
            .fetchAll(db)

        guard !workoutExercises.isEmpty else {
            return WorkoutDetail(workout: workout, gymName: gymName, exercises: [])
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
            var histBest1RM: Double = 0
            var histBestWeight: Double = 0
            var setupNote: String? = nil
            var progressionSuggestion: ProgressionSuggestion? = nil
            if includePreviousSets {
                previousSets = try fetchPreviousSets(
                    forExerciseId: we.exerciseId,
                    excludingWorkoutId: workout.id,
                    preferredGymId: workout.gymId,
                    in: db
                )
                let bests = try fetchHistoricalBests(
                    forExerciseId: we.exerciseId,
                    excludingWorkoutId: workout.id,
                    in: db
                )
                histBest1RM = bests.best1RM
                histBestWeight = bests.bestWeight
                setupNote = try fetchExerciseGymNote(
                    exerciseId: we.exerciseId,
                    gymId: workout.gymId,
                    in: db
                )
                progressionSuggestion = computeProgressionSuggestion(
                    for: exercise,
                    previousSets: previousSets
                )
            } else {
                previousSets = [:]
            }
            return WorkoutExerciseDetail(
                workoutExercise: we,
                exercise: exercise,
                sets: sets,
                previousSets: previousSets,
                historicalBest1RM: histBest1RM,
                historicalBestWeightKg: histBestWeight,
                setupNote: setupNote,
                progressionSuggestion: progressionSuggestion
            )
        }

        return WorkoutDetail(workout: workout, gymName: gymName, exercises: details)
    }

    private static func fetchHistoricalBests(
        forExerciseId exerciseId: String,
        excludingWorkoutId: String,
        in db: Database
    ) throws -> (best1RM: Double, bestWeight: Double) {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT ws.weightKg AS weightKg, ws.reps AS reps
                FROM workout_sets ws
                JOIN workout_exercises we ON we.id = ws.workoutExerciseId
                JOIN workouts w ON w.id = we.workoutId
                WHERE we.exerciseId = ?
                  AND w.id != ?
                  AND w.finishedAt IS NOT NULL
                  AND ws.isCompleted = 1
                  AND ws.setType != 'warmup'
                  AND ws.weightKg IS NOT NULL
                  AND ws.weightKg > 0
                  AND ws.reps IS NOT NULL
                  AND ws.reps > 0
                """,
            arguments: [exerciseId, excludingWorkoutId]
        )

        var best1RM: Double = 0
        var bestWeight: Double = 0
        for row in rows {
            let w: Double = row["weightKg"]
            let r: Int = row["reps"]
            if w > bestWeight { bestWeight = w }
            let est = OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
            if est > best1RM { best1RM = est }
        }
        return (best1RM, bestWeight)
    }

    private static func fetchExerciseGymNote(
        exerciseId: String,
        gymId: String?,
        in db: Database
    ) throws -> String? {
        if let gymId = gymId {
            if let specific = try ExerciseGymNote
                .filter(ExerciseGymNote.Columns.exerciseId == exerciseId && ExerciseGymNote.Columns.gymId == gymId)
                .fetchOne(db) {
                return specific.note
            }
        }
        if let globalNote = try ExerciseGymNote
            .filter(ExerciseGymNote.Columns.exerciseId == exerciseId && ExerciseGymNote.Columns.gymId == nil)
            .fetchOne(db) {
            return globalNote.note
        }
        return nil
    }

    private static func computeProgressionSuggestion(
        for exercise: Exercise,
        previousSets: [Int: PreviousSetReference]
    ) -> ProgressionSuggestion? {
        let validSets = previousSets.keys.sorted().compactMap { key -> (weight: Double, reps: Int)? in
            guard let ref = previousSets[key],
                  let w = ref.weightKg, let r = ref.reps,
                  w > 0, r > 0 else { return nil }
            return (w, r)
        }
        guard !validSets.isEmpty else { return nil }

        let topWeight = validSets.map { $0.weight }.max() ?? 0
        let workingSets = validSets.filter { $0.weight >= topWeight * 0.85 }
        guard !workingSets.isEmpty else { return nil }

        let minReps = workingSets.map { $0.reps }.min() ?? 0
        let maxReps = workingSets.map { $0.reps }.max() ?? 0
        let setCount = workingSets.count

        // Double progression: if all working sets hit >= 10 reps (or >= 12 for isolation/arms), recommend weight increase
        let isIsolation = exercise.muscleGroup == .biceps || exercise.muscleGroup == .triceps || exercise.muscleGroup == .core
        let repCeiling = isIsolation ? 12 : 10
        let stepKg: Double = (exercise.equipment == .dumbbell || isIsolation) ? 2.0 : 2.5

        if minReps >= repCeiling {
            let nextWeight = topWeight + stepKg
            return ProgressionSuggestion(
                message: "Letztes Mal \(setCount)×\(minReps) @ \(Formatters.weight(topWeight)) kg → heute \(Formatters.weight(nextWeight)) kg anpeilen",
                isWeightIncrease: true
            )
        } else {
            let targetReps = maxReps + 1
            return ProgressionSuggestion(
                message: "Letztes Mal \(setCount) Sätze @ \(Formatters.weight(topWeight)) kg → heute \(targetReps) Wdh. versuchen",
                isWeightIncrease: false
            )
        }
    }

    func saveExerciseGymNote(exerciseId: String, gymId: String?, note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try dbWriter.write { db in
            let existing: ExerciseGymNote?
            if let gymId = gymId {
                existing = try ExerciseGymNote
                    .filter(ExerciseGymNote.Columns.exerciseId == exerciseId && ExerciseGymNote.Columns.gymId == gymId)
                    .fetchOne(db)
            } else {
                existing = try ExerciseGymNote
                    .filter(ExerciseGymNote.Columns.exerciseId == exerciseId && ExerciseGymNote.Columns.gymId == nil)
                    .fetchOne(db)
            }

            if trimmed.isEmpty {
                if let existing = existing {
                    _ = try ExerciseGymNote.deleteOne(db, key: existing.id)
                }
            } else if var existing = existing {
                existing.note = trimmed
                existing.updatedAt = Date()
                try existing.update(db)
            } else {
                let fresh = ExerciseGymNote(exerciseId: exerciseId, gymId: gymId, note: trimmed)
                try fresh.insert(db)
            }
        }
    }

    func replaceWorkoutExercise(workoutExerciseId: String, newExercise: Exercise) throws {
        try dbWriter.write { db in
            guard var we = try WorkoutExercise.fetchOne(db, key: workoutExerciseId) else { return }
            we.exerciseId = newExercise.id
            we.restSeconds = newExercise.defaultRestSeconds
            try we.update(db)
        }
    }

    func insertWarmupSets(for workoutExerciseId: String, workingWeightKg: Double) throws {
        guard workingWeightKg > 0 else { return }
        let roundTo2_5: (Double) -> Double = { val in
            max(2.5, (val / 2.5).rounded() * 2.5)
        }
        let warmups: [(Double, Int)] = workingWeightKg >= 40
            ? [(roundTo2_5(workingWeightKg * 0.5), 8), (roundTo2_5(workingWeightKg * 0.72), 5), (roundTo2_5(workingWeightKg * 0.85), 2)]
            : [(roundTo2_5(workingWeightKg * 0.55), 8), (roundTo2_5(workingWeightKg * 0.75), 4)]

        try dbWriter.write { db in
            let existingSets = try WorkoutSet
                .filter(WorkoutSet.Columns.workoutExerciseId == workoutExerciseId)
                .order(WorkoutSet.Columns.setOrder.asc)
                .fetchAll(db)

            let offset = warmups.count
            for set in existingSets {
                try db.execute(
                    sql: "UPDATE workout_sets SET setOrder = ? WHERE id = ?",
                    arguments: [set.setOrder + offset, set.id]
                )
            }

            for (idx, item) in warmups.enumerated() {
                let warmupSet = WorkoutSet(
                    workoutExerciseId: workoutExerciseId,
                    setOrder: idx + 1,
                    setType: .warmup,
                    weightKg: item.0,
                    reps: item.1,
                    isCompleted: false
                )
                try warmupSet.insert(db)
            }
        }
    }

    private static func fetchPreviousSets(
        forExerciseId exerciseId: String,
        excludingWorkoutId: String,
        preferredGymId: String?,
        in db: Database
    ) throws -> [Int: PreviousSetReference] {
        var previousWorkoutExerciseId: String?

        // Prefer the most recent completed session in the same gym (different machines/pulleys!)
        if let gymId = preferredGymId {
            previousWorkoutExerciseId = try String.fetchOne(
                db,
                sql: """
                    SELECT we.id
                    FROM workout_exercises we
                    JOIN workouts w ON w.id = we.workoutId
                    WHERE we.exerciseId = ?
                      AND w.id != ?
                      AND w.gymId = ?
                      AND w.finishedAt IS NOT NULL
                    ORDER BY w.startedAt DESC
                    LIMIT 1
                    """,
                arguments: [exerciseId, excludingWorkoutId, gymId]
            )
        }

        if previousWorkoutExerciseId == nil {
            previousWorkoutExerciseId = try String.fetchOne(
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
        }

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

    func startEmptyWorkout(name: String = "Freies Training", gymId: String? = nil) throws -> String {
        let workout = Workout(gymId: gymId, name: name, startedAt: Date(), finishedAt: nil)
        try dbWriter.write { db in
            try workout.insert(db)
        }
        return workout.id
    }

    func startWorkout(
        from routineDetail: RoutineWithExercises,
        gymId: String? = nil,
        isDeload: Bool = false
    ) throws -> String {
        let workoutName = isDeload ? "\(routineDetail.routine.name) (Deload)" : routineDetail.routine.name
        let workout = Workout(
            routineId: routineDetail.routine.id,
            gymId: gymId,
            name: workoutName,
            startedAt: Date(),
            finishedAt: nil,
            notes: isDeload ? "Deload-Einheit (−20 % Gewicht, reduziertes Volumen)" : routineDetail.routine.notes
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

                let baseSets = max(1, item.routineExercise.targetSets)
                let setCount = isDeload ? max(1, baseSets - 1) : baseSets

                var prevSets: [Int: PreviousSetReference] = [:]
                if isDeload {
                    prevSets = try Self.fetchPreviousSets(
                        forExerciseId: item.exercise.id,
                        excludingWorkoutId: workout.id,
                        preferredGymId: gymId,
                        in: db
                    )
                }

                for setIndex in 1...setCount {
                    var deloadWeight: Double? = nil
                    var deloadReps: Int? = nil
                    if isDeload, let prev = prevSets[setIndex] ?? prevSets[1] {
                        if let w = prev.weightKg, w > 0 {
                            deloadWeight = max(2.5, ((w * 0.8) / 2.5).rounded() * 2.5)
                        }
                        deloadReps = prev.reps
                    }
                    let set = WorkoutSet(
                        workoutExerciseId: we.id,
                        setOrder: setIndex,
                        setType: .normal,
                        weightKg: deloadWeight,
                        reps: deloadReps,
                        isCompleted: false,
                        completedAt: nil
                    )
                    try set.insert(db)
                }
            }
        }
        return workout.id
    }

    func moveWorkoutExercise(workoutId: String, workoutExerciseId: String, direction: Int) throws {
        try dbWriter.write { db in
            let exercises = try WorkoutExercise
                .filter(WorkoutExercise.Columns.workoutId == workoutId)
                .order(WorkoutExercise.Columns.sortOrder.asc)
                .fetchAll(db)

            guard let currentIndex = exercises.firstIndex(where: { $0.id == workoutExerciseId }) else { return }
            let targetIndex = currentIndex + direction
            guard targetIndex >= 0 && targetIndex < exercises.count else { return }

            var reordered = exercises
            let item = reordered.remove(at: currentIndex)
            reordered.insert(item, at: targetIndex)

            for (idx, ex) in reordered.enumerated() {
                try db.execute(
                    sql: "UPDATE workout_exercises SET sortOrder = ? WHERE id = ?",
                    arguments: [idx, ex.id]
                )
            }
        }
    }

    func updateWorkoutExerciseRestSeconds(workoutExerciseId: String, restSeconds: Int) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE workout_exercises SET restSeconds = ? WHERE id = ?",
                arguments: [max(15, restSeconds), workoutExerciseId]
            )
        }
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

    func finishWorkout(
        id: String,
        updateRoutine: Bool = false,
        pendingHeartRateSamples: [WorkoutHeartRateSample] = []
    ) throws {
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

            var setCountsByWeId: [String: Int] = [:]
            for (exIndex, var we) in remainingExercises.enumerated() {
                if we.sortOrder != exIndex {
                    we.sortOrder = exIndex
                    try we.update(db)
                }
                let sets = try WorkoutSet
                    .filter(WorkoutSet.Columns.workoutExerciseId == we.id)
                    .order(WorkoutSet.Columns.setOrder.asc)
                    .fetchAll(db)
                setCountsByWeId[we.id] = sets.count
                for (setIndex, var set) in sets.enumerated() {
                    if set.setOrder != setIndex + 1 {
                        set.setOrder = setIndex + 1
                        try set.update(db)
                    }
                }
            }

            if updateRoutine,
               let workout = try Workout.fetchOne(db, key: id),
               let routineId = workout.routineId,
               !remainingExercises.isEmpty {
                try RoutineExercise
                    .filter(RoutineExercise.Columns.routineId == routineId)
                    .deleteAll(db)

                for (index, we) in remainingExercises.enumerated() {
                    let re = RoutineExercise(
                        routineId: routineId,
                        exerciseId: we.exerciseId,
                        sortOrder: index,
                        targetSets: max(1, setCountsByWeId[we.id] ?? 3),
                        targetReps: nil,
                        restSeconds: we.restSeconds,
                        notes: we.notes
                    )
                    try re.insert(db)
                }

                try db.execute(
                    sql: "UPDATE routines SET updatedAt = ? WHERE id = ?",
                    arguments: [Date(), routineId]
                )
            }

            for sample in pendingHeartRateSamples where sample.workoutId == id {
                try sample.insert(db, onConflict: .ignore)
            }

            var avgHR: Int? = nil
            var maxHR: Int? = nil
            var minHR: Int? = nil
            if let hrRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS cnt,
                           AVG(bpm) AS avgBpm,
                           MAX(bpm) AS maxBpm,
                           MIN(bpm) AS minBpm
                    FROM workout_heart_rate_samples
                    WHERE workoutId = ?
                    """,
                arguments: [id]
            ) {
                let cnt: Int = (hrRow["cnt"] as Int?) ?? 0
                if cnt > 0 {
                    let avgDouble: Double? = hrRow["avgBpm"]
                    avgHR = avgDouble.map { Int($0.rounded()) }
                    maxHR = hrRow["maxBpm"]
                    minHR = hrRow["minBpm"]
                }
            }

            try db.execute(
                sql: """
                    UPDATE workouts
                    SET finishedAt = ?,
                        avgHeartRate = ?,
                        maxHeartRate = ?,
                        minHeartRate = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), avgHR, maxHR, minHR, id]
            )
        }
    }

    func insertHeartRateSamples(_ samples: [WorkoutHeartRateSample]) throws {
        guard !samples.isEmpty else { return }
        try dbWriter.write { db in
            for sample in samples {
                try sample.insert(db, onConflict: .ignore)
            }
        }
    }

    static func fetchHeartRateSamples(forWorkoutId workoutId: String, in db: Database) throws -> [WorkoutHeartRateSample] {
        try WorkoutHeartRateSample
            .filter(WorkoutHeartRateSample.Columns.workoutId == workoutId)
            .order(WorkoutHeartRateSample.Columns.recordedAt.asc)
            .fetchAll(db)
    }

    func fetchHeartRateSamples(forWorkoutId workoutId: String) throws -> [WorkoutHeartRateSample] {
        try dbWriter.read { db in
            try Self.fetchHeartRateSamples(forWorkoutId: workoutId, in: db)
        }
    }

    func linkSupersetWithNext(workoutId: String, workoutExerciseId: String) throws {
        try dbWriter.write { db in
            let all = try WorkoutExercise
                .filter(WorkoutExercise.Columns.workoutId == workoutId)
                .order(WorkoutExercise.Columns.sortOrder.asc)
                .fetchAll(db)

            guard let idx = all.firstIndex(where: { $0.id == workoutExerciseId }),
                  idx + 1 < all.count else {
                return
            }

            var current = all[idx]
            var next = all[idx + 1]
            let maxGroup = all.compactMap { $0.supersetGroup }.max() ?? 0
            let groupNumber = current.supersetGroup ?? next.supersetGroup ?? (maxGroup + 1)

            current.supersetGroup = groupNumber
            next.supersetGroup = groupNumber
            try current.update(db)
            try next.update(db)
        }
    }

    func clearSuperset(workoutExerciseId: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE workout_exercises SET supersetGroup = NULL WHERE id = ?",
                arguments: [workoutExerciseId]
            )
        }
    }

    func discardWorkout(id: String) throws {
        try dbWriter.write { db in
            _ = try Workout.deleteOne(db, key: id)
        }
    }
}

// MARK: - History, Stats & Backup Operations

extension AppDatabase {
    static func fetchCompletedWorkouts(in db: Database) throws -> [WorkoutDetail] {
        let completed = try Workout
            .filter(Workout.Columns.finishedAt != nil)
            .order(Workout.Columns.startedAt.desc)
            .fetchAll(db)

        return try completed.map { workout in
            try fetchWorkoutDetail(for: workout, includePreviousSets: false, in: db)
        }
    }

    func deleteWorkout(id: String) throws {
        try dbWriter.write { db in
            _ = try Workout.deleteOne(db, key: id)
        }
    }

    static func fetchExerciseStats(exerciseId: String, in db: Database) throws -> ExerciseStats {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT we.id AS weId, w.id AS workoutId, w.name AS workoutName, w.startedAt AS startedAt
                FROM workout_exercises we
                JOIN workouts w ON w.id = we.workoutId
                WHERE we.exerciseId = ?
                  AND w.finishedAt IS NOT NULL
                ORDER BY w.startedAt ASC
                """,
            arguments: [exerciseId]
        )

        guard !rows.isEmpty else { return .empty }

        let weIds: [String] = rows.map { $0["weId"] }
        let allSets = try WorkoutSet
            .filter(weIds.contains(WorkoutSet.Columns.workoutExerciseId) && WorkoutSet.Columns.isCompleted == true)
            .order(WorkoutSet.Columns.setOrder.asc)
            .fetchAll(db)
        let setsByWeId = Dictionary(grouping: allSets, by: { $0.workoutExerciseId })

        var overallBestWeight: Double?
        var overallBest1RM: Double?
        var overallBestSetVolume: Double?
        var totalCompletedSets = 0
        var historyPoints: [ExerciseProgressPoint] = []

        for row in rows {
            let weId: String = row["weId"]
            let workoutId: String = row["workoutId"]
            let workoutName: String = row["workoutName"]
            let startedAt: Date = row["startedAt"]

            let sets = setsByWeId[weId] ?? []
            guard !sets.isEmpty else { continue }
            totalCompletedSets += sets.count

            let workingSets = sets.filter { $0.setType != .warmup }
            let evaluatedSets = workingSets.isEmpty ? sets : workingSets

            var sessionBest1RM: Double = 0
            var sessionBestWeight: Double = 0
            var sessionVolume: Double = 0

            for set in evaluatedSets {
                let w = set.weightKg ?? 0
                let r = set.reps ?? 0
                let est1RM = OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r)
                let vol = OneRepMaxCalculator.setVolume(weightKg: set.weightKg, reps: set.reps)

                if w > sessionBestWeight { sessionBestWeight = w }
                if est1RM > sessionBest1RM { sessionBest1RM = est1RM }
                sessionVolume += vol

                if w > 0 {
                    overallBestWeight = max(overallBestWeight ?? 0, w)
                }
                if est1RM > 0 {
                    overallBest1RM = max(overallBest1RM ?? 0, est1RM)
                }
                if vol > 0 {
                    overallBestSetVolume = max(overallBestSetVolume ?? 0, vol)
                }
            }

            historyPoints.append(
                ExerciseProgressPoint(
                    id: workoutId,
                    date: startedAt,
                    workoutName: workoutName,
                    bestEstimated1RM: sessionBest1RM,
                    bestWeightKg: sessionBestWeight,
                    totalVolumeKg: sessionVolume,
                    sets: sets
                )
            )
        }

        return ExerciseStats(
            bestWeightKg: overallBestWeight,
            bestEstimated1RM: overallBest1RM,
            bestSetVolumeKg: overallBestSetVolume,
            totalCompletedSets: totalCompletedSets,
            history: historyPoints
        )
    }

    static func fetchAllExercisePRs(in db: Database) throws -> [ExercisePRSummary] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT we.exerciseId AS exerciseId,
                       ws.weightKg AS weightKg,
                       ws.reps AS reps,
                       ws.setType AS setType,
                       w.startedAt AS startedAt
                FROM workout_sets ws
                JOIN workout_exercises we ON we.id = ws.workoutExerciseId
                JOIN workouts w ON w.id = we.workoutId
                WHERE w.finishedAt IS NOT NULL
                  AND ws.isCompleted = 1
                  AND ws.weightKg IS NOT NULL
                  AND ws.weightKg > 0
                  AND ws.reps IS NOT NULL
                  AND ws.reps > 0
                  AND ws.setType != 'warmup'
                """
        )

        guard !rows.isEmpty else { return [] }

        var bestByExercise: [String: (est1RM: Double, weight: Double, date: Date)] = [:]
        for row in rows {
            let exerciseId: String = row["exerciseId"]
            let weight: Double = row["weightKg"]
            let reps: Int = row["reps"]
            let startedAt: Date = row["startedAt"]

            let est1RM = OneRepMaxCalculator.estimatedOneRepMax(weightKg: weight, reps: reps)
            if let current = bestByExercise[exerciseId] {
                let newBest1RM = max(current.est1RM, est1RM)
                let newBestWeight = max(current.weight, weight)
                let newDate = est1RM >= current.est1RM ? startedAt : current.date
                bestByExercise[exerciseId] = (newBest1RM, newBestWeight, newDate)
            } else {
                bestByExercise[exerciseId] = (est1RM, weight, startedAt)
            }
        }

        let exerciseIds = Set(bestByExercise.keys)
        let exercises = try Exercise
            .filter(exerciseIds.contains(Exercise.Columns.id))
            .fetchAll(db)
        let exercisesById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        return bestByExercise.compactMap { exerciseId, stats -> ExercisePRSummary? in
            guard let exercise = exercisesById[exerciseId] else { return nil }
            return ExercisePRSummary(
                exercise: exercise,
                bestEstimated1RM: stats.est1RM,
                bestWeightKg: stats.weight,
                achievedAt: stats.date
            )
        }
        .sorted { lhs, rhs in
            if lhs.bestEstimated1RM != rhs.bestEstimated1RM {
                return lhs.bestEstimated1RM > rhs.bestEstimated1RM
            }
            return lhs.exercise.name < rhs.exercise.name
        }
    }

    func exportBackupPayload() throws -> BackupPayload {
        try dbWriter.read { db in
            BackupPayload(
                schemaVersion: 10,
                exportedAt: Date(),
                exercises: try Exercise.fetchAll(db),
                routines: try Routine.fetchAll(db),
                routineExercises: try RoutineExercise.fetchAll(db),
                workouts: try Workout.fetchAll(db),
                workoutExercises: try WorkoutExercise.fetchAll(db),
                workoutSets: try WorkoutSet.fetchAll(db),
                bodyweightEntries: try BodyweightEntry.fetchAll(db),
                bodyweightPhotos: try BodyweightPhoto.fetchAll(db),
                cardioSessions: try CardioSession.fetchAll(db),
                gyms: try Gym.fetchAll(db),
                foodItems: try FoodItem.fetchAll(db),
                foodLogEntries: try FoodLogEntry.fetchAll(db),
                savedMeals: try SavedMeal.fetchAll(db),
                savedMealItems: try SavedMealItem.fetchAll(db),
                dailyWaterLogs: try DailyWaterLog.fetchAll(db),
                supplements: try Supplement.fetchAll(db),
                supplementLogs: try SupplementLog.fetchAll(db),
                bodyMeasurements: try BodyMeasurement.fetchAll(db),
                readinessLogs: try ReadinessLog.fetchAll(db),
                exerciseGymNotes: try ExerciseGymNote.fetchAll(db),
                dayTemplates: try DayTemplate.fetchAll(db),
                dayTemplateItems: try DayTemplateItem.fetchAll(db),
                workoutHeartRateSamples: try WorkoutHeartRateSample.fetchAll(db)
            )
        }
    }

    func importBackupPayload(_ payload: BackupPayload) throws {
        try dbWriter.write { db in
            // Delete in reverse foreign-key dependency order
            try DayTemplateItem.deleteAll(db)
            try DayTemplate.deleteAll(db)
            try ExerciseGymNote.deleteAll(db)
            try ReadinessLog.deleteAll(db)
            try BodyMeasurement.deleteAll(db)
            try SupplementLog.deleteAll(db)
            try Supplement.deleteAll(db)
            try DailyWaterLog.deleteAll(db)
            try SavedMealItem.deleteAll(db)
            try SavedMeal.deleteAll(db)
            try FoodLogEntry.deleteAll(db)
            try FoodItem.deleteAll(db)
            try CardioSession.deleteAll(db)
            try BodyweightPhoto.deleteAll(db)
            try BodyweightEntry.deleteAll(db)
            try WorkoutHeartRateSample.deleteAll(db)
            try WorkoutSet.deleteAll(db)
            try WorkoutExercise.deleteAll(db)
            try Workout.deleteAll(db)
            try Gym.deleteAll(db)
            try RoutineExercise.deleteAll(db)
            try Routine.deleteAll(db)
            try Exercise.deleteAll(db)

            // Insert in foreign-key dependency order
            for item in payload.exercises { try item.insert(db) }
            for item in payload.routines { try item.insert(db) }
            for item in payload.routineExercises { try item.insert(db) }
            for item in payload.gyms ?? [] { try item.insert(db) }
            for item in payload.workouts { try item.insert(db) }
            for item in payload.workoutExercises { try item.insert(db) }
            for item in payload.workoutSets { try item.insert(db) }
            for item in payload.workoutHeartRateSamples ?? [] { try item.insert(db) }
            for item in payload.bodyweightEntries ?? [] { try item.insert(db) }
            for item in payload.bodyweightPhotos ?? [] { try item.insert(db) }
            for item in payload.cardioSessions ?? [] { try item.insert(db) }
            if let foods = payload.foodItems, !foods.isEmpty {
                for item in foods { try item.insert(db) }
            } else {
                try SeedFoods.insertDefaultFoods(in: db)
            }
            for item in payload.foodLogEntries ?? [] { try item.insert(db) }
            for item in payload.savedMeals ?? [] { try item.insert(db) }
            for item in payload.savedMealItems ?? [] { try item.insert(db) }
            for item in payload.dailyWaterLogs ?? [] { try item.insert(db) }
            for item in payload.supplements ?? [] { try item.insert(db) }
            for item in payload.supplementLogs ?? [] { try item.insert(db) }
            for item in payload.bodyMeasurements ?? [] { try item.insert(db) }
            for item in payload.readinessLogs ?? [] { try item.insert(db) }
            for item in payload.exerciseGymNotes ?? [] { try item.insert(db) }
            for item in payload.dayTemplates ?? [] { try item.insert(db) }
            for item in payload.dayTemplateItems ?? [] { try item.insert(db) }
        }
    }
}

// MARK: - Bodyweight Operations

extension AppDatabase {
    static func fetchBodyweightEntriesWithPhotos(in db: Database) throws -> [BodyweightEntryWithPhotos] {
        let entries = try BodyweightEntry
            .order(BodyweightEntry.Columns.recordedAt.desc)
            .fetchAll(db)

        guard !entries.isEmpty else { return [] }

        let allPhotos = try BodyweightPhoto
            .order(BodyweightPhoto.Columns.createdAt.asc)
            .fetchAll(db)
        let photosByEntry = Dictionary(grouping: allPhotos, by: { $0.entryId })

        return entries.map { entry in
            BodyweightEntryWithPhotos(
                entry: entry,
                photos: photosByEntry[entry.id] ?? []
            )
        }
    }

    func saveBodyweightEntry(_ entry: BodyweightEntry, photos: [BodyweightPhoto]) throws {
        try dbWriter.write { db in
            try entry.save(db)
            try BodyweightPhoto
                .filter(BodyweightPhoto.Columns.entryId == entry.id)
                .deleteAll(db)
            for photo in photos {
                var normalized = photo
                normalized.entryId = entry.id
                try normalized.insert(db)
            }
        }
    }

    func deleteBodyweightEntry(id: String) throws -> [String] {
        try dbWriter.write { db in
            let photos = try BodyweightPhoto
                .filter(BodyweightPhoto.Columns.entryId == id)
                .fetchAll(db)
            let filenames = photos.map { $0.imageFilename }
            _ = try BodyweightEntry.deleteOne(db, key: id)
            return filenames
        }
    }
}

// MARK: - Cardio Operations

extension AppDatabase {
    static func fetchCardioSessions(in db: Database) throws -> [CardioSession] {
        try CardioSession
            .order(CardioSession.Columns.startedAt.desc)
            .fetchAll(db)
    }

    func saveCardioSession(_ session: CardioSession) throws {
        try dbWriter.write { db in
            try session.save(db)
        }
    }

    func deleteCardioSession(id: String) throws {
        try dbWriter.write { db in
            _ = try CardioSession.deleteOne(db, key: id)
        }
    }
}

// MARK: - Gym Operations

extension AppDatabase {
    static func fetchGyms(in db: Database) throws -> [Gym] {
        try Gym
            .order(Gym.Columns.sortOrder.asc, Gym.Columns.createdAt.asc)
            .fetchAll(db)
    }

    func saveGym(_ gym: Gym) throws {
        try dbWriter.write { db in
            try gym.save(db)
        }
    }

    func deleteGym(id: String) throws {
        try dbWriter.write { db in
            _ = try Gym.deleteOne(db, key: id)
        }
    }

    func updateWorkoutGym(workoutId: String, gymId: String?) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE workouts SET gymId = ? WHERE id = ?",
                arguments: [gymId, workoutId]
            )
        }
    }
}

// MARK: - Nutrition Operations

extension AppDatabase {
    static func fetchFoodItems(in db: Database) throws -> [FoodItem] {
        try FoodItem
            .order(
                FoodItem.Columns.isFavorite.desc,
                FoodItem.Columns.name.collating(.localizedCaseInsensitiveCompare)
            )
            .fetchAll(db)
    }

    static func fetchSavedMealsWithItems(in db: Database) throws -> [SavedMealWithItems] {
        let meals = try SavedMeal
            .order(SavedMeal.Columns.name.collating(.localizedCaseInsensitiveCompare))
            .fetchAll(db)

        guard !meals.isEmpty else { return [] }

        let allItems = try SavedMealItem
            .order(SavedMealItem.Columns.sortOrder.asc)
            .fetchAll(db)

        let foodIds = Set(allItems.map { $0.foodItemId })
        let foodsById: [String: FoodItem]
        if foodIds.isEmpty {
            foodsById = [:]
        } else {
            let foods = try FoodItem
                .filter(foodIds.contains(FoodItem.Columns.id))
                .fetchAll(db)
            foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        }

        let grouped = Dictionary(grouping: allItems, by: { $0.mealId })

        return meals.map { meal in
            let details = (grouped[meal.id] ?? []).compactMap { item -> SavedMealItemDetail? in
                guard let food = foodsById[item.foodItemId] else { return nil }
                return SavedMealItemDetail(item: item, food: food)
            }
            return SavedMealWithItems(meal: meal, items: details)
        }
    }

    static func fetchFoodLogEntries(forDay day: Date, in db: Database) throws -> [FoodLogEntryDetail] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let entries = try FoodLogEntry
            .filter(FoodLogEntry.Columns.loggedAt >= startOfDay && FoodLogEntry.Columns.loggedAt < endOfDay)
            .order(FoodLogEntry.Columns.loggedAt.asc)
            .fetchAll(db)

        guard !entries.isEmpty else { return [] }

        let foodIds = Set(entries.map { $0.foodItemId })
        let foods = try FoodItem
            .filter(foodIds.contains(FoodItem.Columns.id))
            .fetchAll(db)
        let foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })

        return entries.compactMap { entry in
            guard let food = foodsById[entry.foodItemId] else { return nil }
            return FoodLogEntryDetail(entry: entry, food: food)
        }
    }

    func findFoodItem(byBarcode barcode: String) throws -> FoodItem? {
        try dbWriter.read { db in
            try FoodItem
                .filter(FoodItem.Columns.barcode == barcode)
                .fetchOne(db)
        }
    }

    func saveFoodItem(_ item: FoodItem) throws {
        try dbWriter.write { db in
            try item.save(db)
        }
    }

    func toggleFoodFavorite(id: String, isFavorite: Bool) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE food_items SET isFavorite = ? WHERE id = ?",
                arguments: [isFavorite, id]
            )
        }
    }

    func deleteFoodItem(id: String) throws {
        try dbWriter.write { db in
            _ = try FoodItem.deleteOne(db, key: id)
        }
    }

    func saveFoodLogEntry(_ entry: FoodLogEntry) throws {
        try dbWriter.write { db in
            try entry.save(db)
        }
    }

    func deleteFoodLogEntry(id: String) throws {
        try dbWriter.write { db in
            _ = try FoodLogEntry.deleteOne(db, key: id)
        }
    }

    func saveSavedMeal(_ meal: SavedMeal, items: [SavedMealItem]) throws {
        try dbWriter.write { db in
            try meal.save(db)
            try SavedMealItem
                .filter(SavedMealItem.Columns.mealId == meal.id)
                .deleteAll(db)
            for (index, var item) in items.enumerated() {
                item.mealId = meal.id
                item.sortOrder = index
                try item.insert(db)
            }
        }
    }

    func deleteSavedMeal(id: String) throws {
        try dbWriter.write { db in
            _ = try SavedMeal.deleteOne(db, key: id)
        }
    }

    func logSavedMeal(_ meal: SavedMealWithItems, mealType: MealType, multiplier: Double, date: Date) throws {
        try dbWriter.write { db in
            for detail in meal.items {
                let entry = FoodLogEntry(
                    foodItemId: detail.food.id,
                    loggedAt: date,
                    mealType: mealType,
                    grams: max(1, detail.item.grams * multiplier)
                )
                try entry.insert(db)
            }
        }
    }

    func copyMealFromPreviousDay(mealType: MealType, toDay targetDay: Date) throws -> Int {
        let cal = Calendar.current
        guard let prevDay = cal.date(byAdding: .day, value: -1, to: targetDay) else { return 0 }
        let prevStart = cal.startOfDay(for: prevDay)
        guard let prevEnd = cal.date(byAdding: .day, value: 1, to: prevStart) else { return 0 }

        return try dbWriter.write { db in
            let prevEntries = try FoodLogEntry
                .filter(
                    FoodLogEntry.Columns.mealType == mealType
                    && FoodLogEntry.Columns.loggedAt >= prevStart
                    && FoodLogEntry.Columns.loggedAt < prevEnd
                )
                .fetchAll(db)

            for item in prevEntries {
                let copy = FoodLogEntry(
                    foodItemId: item.foodItemId,
                    loggedAt: targetDay,
                    mealType: mealType,
                    grams: item.grams
                )
                try copy.insert(db)
            }
            return prevEntries.count
        }
    }

    static func fetchDailyNutritionPoints(days: Int = 7, in db: Database) throws -> [DailyNutritionPoint] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let startDate = cal.date(byAdding: .day, value: -(days - 1), to: todayStart),
              let endDate = cal.date(byAdding: .day, value: 1, to: todayStart) else {
            return []
        }

        let entries = try FoodLogEntry
            .filter(FoodLogEntry.Columns.loggedAt >= startDate && FoodLogEntry.Columns.loggedAt < endDate)
            .fetchAll(db)

        let foodIds = Set(entries.map { $0.foodItemId })
        let foodsById: [String: FoodItem]
        if foodIds.isEmpty {
            foodsById = [:]
        } else {
            let foods = try FoodItem.filter(foodIds.contains(FoodItem.Columns.id)).fetchAll(db)
            foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        }

        var totalsByDay: [Date: (kcal: Double, protein: Double)] = [:]
        for entry in entries {
            guard let food = foodsById[entry.foodItemId] else { continue }
            let day = cal.startOfDay(for: entry.loggedAt)
            let factor = entry.grams / 100.0
            let current = totalsByDay[day] ?? (0, 0)
            totalsByDay[day] = (
                current.kcal + food.caloriesPer100g * factor,
                current.protein + food.proteinPer100g * factor
            )
        }

        return (0..<days).compactMap { offset -> DailyNutritionPoint? in
            guard let day = cal.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let vals = totalsByDay[day] ?? (0, 0)
            return DailyNutritionPoint(date: day, calories: vals.kcal, protein: vals.protein)
        }
    }
}

// MARK: - Water, Supplements, Measurements & Readiness Operations

extension AppDatabase {
    static func fetchWaterMilliliters(forDayKey dayKey: String, in db: Database) throws -> Int {
        try DailyWaterLog.fetchOne(db, key: dayKey)?.milliliters ?? 0
    }

    func adjustWater(forDayKey dayKey: String, deltaMl: Int) throws {
        try dbWriter.write { db in
            let current = try DailyWaterLog.fetchOne(db, key: dayKey)?.milliliters ?? 0
            let updated = max(0, current + deltaMl)
            try DailyWaterLog(dayKey: dayKey, milliliters: updated).save(db)
        }
    }

    static func fetchSupplements(in db: Database) throws -> [Supplement] {
        try Supplement
            .order(Supplement.Columns.sortOrder.asc, Supplement.Columns.name.asc)
            .fetchAll(db)
    }

    static func fetchTakenSupplementIds(forDayKey dayKey: String, in db: Database) throws -> Set<String> {
        let logs = try SupplementLog
            .filter(SupplementLog.Columns.dayKey == dayKey)
            .fetchAll(db)
        return Set(logs.map { $0.supplementId })
    }

    func saveSupplement(_ supplement: Supplement) throws {
        try dbWriter.write { db in
            try supplement.save(db)
        }
    }

    func deleteSupplement(id: String) throws {
        try dbWriter.write { db in
            _ = try Supplement.deleteOne(db, key: id)
        }
    }

    func toggleSupplementTaken(supplementId: String, dayKey: String) throws {
        try dbWriter.write { db in
            let existing = try SupplementLog
                .filter(SupplementLog.Columns.supplementId == supplementId && SupplementLog.Columns.dayKey == dayKey)
                .fetchOne(db)

            if let existing = existing {
                _ = try SupplementLog.deleteOne(db, key: existing.id)
            } else {
                try SupplementLog(supplementId: supplementId, dayKey: dayKey).insert(db)
            }
        }
    }

    static func fetchBodyMeasurements(in db: Database) throws -> [BodyMeasurement] {
        try BodyMeasurement
            .order(BodyMeasurement.Columns.recordedAt.desc)
            .fetchAll(db)
    }

    func saveBodyMeasurement(_ measurement: BodyMeasurement) throws {
        try dbWriter.write { db in
            try measurement.save(db)
        }
    }

    func deleteBodyMeasurement(id: String) throws {
        try dbWriter.write { db in
            _ = try BodyMeasurement.deleteOne(db, key: id)
        }
    }

    static func fetchReadinessLogs(in db: Database) throws -> [ReadinessLog] {
        try ReadinessLog
            .order(ReadinessLog.Columns.recordedAt.desc)
            .fetchAll(db)
    }

    func saveReadinessLog(_ log: ReadinessLog) throws {
        try dbWriter.write { db in
            try ReadinessLog
                .filter(ReadinessLog.Columns.dayKey == log.dayKey)
                .deleteAll(db)
            try log.insert(db)
        }
    }

    func deleteReadinessLog(id: String) throws {
        try dbWriter.write { db in
            _ = try ReadinessLog.deleteOne(db, key: id)
        }
    }

    static func fetchSaunaSessions(in db: Database) throws -> [SaunaSession] {
        try SaunaSession
            .order(SaunaSession.Columns.startedAt.desc)
            .fetchAll(db)
    }

    func saveSaunaSession(_ session: SaunaSession) throws {
        try dbWriter.write { db in
            try session.save(db)
        }
    }

    func deleteSaunaSession(id: String) throws {
        try dbWriter.write { db in
            _ = try SaunaSession.deleteOne(db, key: id)
        }
    }
}

// MARK: - Day Template Operations

extension AppDatabase {
    static func fetchDayTemplatesWithItems(in db: Database) throws -> [DayTemplateWithItems] {
        let templates = try DayTemplate
            .order(DayTemplate.Columns.createdAt.desc)
            .fetchAll(db)
        guard !templates.isEmpty else { return [] }

        let allItems = try DayTemplateItem
            .order(DayTemplateItem.Columns.sortOrder.asc)
            .fetchAll(db)

        let foodIds = Set(allItems.map { $0.foodItemId })
        let foodsById: [String: FoodItem]
        if foodIds.isEmpty {
            foodsById = [:]
        } else {
            let foods = try FoodItem.filter(foodIds.contains(FoodItem.Columns.id)).fetchAll(db)
            foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        }

        let grouped = Dictionary(grouping: allItems, by: { $0.templateId })
        return templates.map { tpl in
            let details = (grouped[tpl.id] ?? []).compactMap { item -> DayTemplateItemDetail? in
                guard let food = foodsById[item.foodItemId] else { return nil }
                return DayTemplateItemDetail(item: item, food: food)
            }
            return DayTemplateWithItems(template: tpl, items: details)
        }
    }

    func saveDayTemplate(name: String, fromEntries entries: [FoodLogEntryDetail]) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entries.isEmpty else { return }

        let template = DayTemplate(name: trimmed)
        try dbWriter.write { db in
            try template.insert(db)
            for (idx, detail) in entries.enumerated() {
                let item = DayTemplateItem(
                    templateId: template.id,
                    foodItemId: detail.food.id,
                    mealType: detail.entry.mealType,
                    grams: detail.entry.grams,
                    sortOrder: idx
                )
                try item.insert(db)
            }
        }
    }

    func applyDayTemplate(_ template: DayTemplateWithItems, toDay date: Date) throws {
        try dbWriter.write { db in
            for detail in template.items {
                let entry = FoodLogEntry(
                    foodItemId: detail.food.id,
                    loggedAt: date,
                    mealType: detail.item.mealType,
                    grams: detail.item.grams
                )
                try entry.insert(db)
            }
        }
    }

    func deleteDayTemplate(id: String) throws {
        try dbWriter.write { db in
            _ = try DayTemplate.deleteOne(db, key: id)
        }
    }
}
