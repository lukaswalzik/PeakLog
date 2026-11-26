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
            if includePreviousSets {
                previousSets = try fetchPreviousSets(
                    forExerciseId: we.exerciseId,
                    excludingWorkoutId: workout.id,
                    preferredGymId: workout.gymId,
                    in: db
                )
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

        return WorkoutDetail(workout: workout, gymName: gymName, exercises: details)
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

    func startWorkout(from routineDetail: RoutineWithExercises, gymId: String? = nil) throws -> String {
        let workout = Workout(
            routineId: routineDetail.routine.id,
            gymId: gymId,
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
                schemaVersion: 6,
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
                savedMealItems: try SavedMealItem.fetchAll(db)
            )
        }
    }

    func importBackupPayload(_ payload: BackupPayload) throws {
        try dbWriter.write { db in
            // Delete in reverse foreign-key dependency order
            try SavedMealItem.deleteAll(db)
            try SavedMeal.deleteAll(db)
            try FoodLogEntry.deleteAll(db)
            try FoodItem.deleteAll(db)
            try CardioSession.deleteAll(db)
            try BodyweightPhoto.deleteAll(db)
            try BodyweightEntry.deleteAll(db)
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
}
