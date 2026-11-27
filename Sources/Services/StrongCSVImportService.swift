import Foundation
import GRDB

enum StrongWeightUnitMode: String, CaseIterable, Identifiable {
    case auto
    case kilograms
    case pounds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatisch (CSV)"
        case .kilograms: return "Kilogramm (kg)"
        case .pounds: return "Pfund (lbs → kg)"
        }
    }
}

enum StrongImportError: LocalizedError {
    case unreadableText
    case emptyFile
    case missingRequiredColumns
    case noWorkoutsFound

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "Die CSV-Datei konnte nicht als UTF-8 Text gelesen werden."
        case .emptyFile:
            return "Die ausgewählte CSV-Datei ist leer."
        case .missingRequiredColumns:
            return "Ungültiges Format: Es wurden keine Strong-Spalten ('Date'/'Datum' und 'Exercise Name'/'Übungsname') gefunden."
        case .noWorkoutsFound:
            return "In der CSV-Datei wurden keine gültigen Trainings-Sätze gefunden."
        }
    }
}

struct ParsedStrongSet: Equatable {
    let setType: SetType
    let weightKg: Double?
    let reps: Int?
    let rir: Int?
}

struct ParsedStrongExercise: Equatable {
    let rawName: String
    var notes: String?
    var sets: [ParsedStrongSet]
}

struct ParsedStrongWorkout: Identifiable, Equatable {
    let id: String
    let name: String
    let startedAt: Date
    let durationSeconds: Int
    var notes: String?
    var exercises: [ParsedStrongExercise]

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}

struct StrongImportPreview: Equatable {
    let workouts: [ParsedStrongWorkout]
    let totalSetCount: Int
    let uniqueExerciseCount: Int
    let matchedExerciseCount: Int
    let newExerciseNames: [String]
    let duplicateWorkoutCount: Int
    let earliestDate: Date?
    let latestDate: Date?
    let detectedDelimiter: String
    let detectedUnitHint: String

    var newWorkoutCount: Int {
        max(0, workouts.count - duplicateWorkoutCount)
    }
}

struct StrongImportResult: Equatable {
    let importedWorkouts: Int
    let skippedDuplicates: Int
    let importedSets: Int
    let createdExercises: Int
}

enum StrongCSVImportService {
    private static let lbsToKgFactor = 0.45359237

    // MARK: - Public API

    static func parseAndPreview(
        data: Data,
        weightUnitMode: StrongWeightUnitMode = .auto,
        database: AppDatabase
    ) throws -> StrongImportPreview {
        let parsed = try parseCSV(data: data, weightUnitMode: weightUnitMode)
        guard !parsed.workouts.isEmpty else {
            throw StrongImportError.noWorkoutsFound
        }

        return try database.dbWriter.read { db in
            let existingExercises = try Exercise.fetchAll(db)
            let existingWorkouts = try Workout.fetchAll(db)

            let exercisesByLowerName = Dictionary(
                existingExercises.map { (normalizeKey($0.name), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let exercisesById = Dictionary(
                existingExercises.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var uniqueNames: [String] = []
            var seenLower: Set<String> = []
            var matchedCount = 0
            var newNames: [String] = []

            for workout in parsed.workouts {
                for ex in workout.exercises {
                    let key = normalizeKey(ex.rawName)
                    if seenLower.insert(key).inserted {
                        uniqueNames.append(ex.rawName)
                        if resolveExistingExercise(
                            rawName: ex.rawName,
                            byLowerName: exercisesByLowerName,
                            byId: exercisesById
                        ) != nil {
                            matchedCount += 1
                        } else {
                            newNames.append(ex.rawName)
                        }
                    }
                }
            }

            let duplicateCount = parsed.workouts.filter { candidate in
                isDuplicate(candidate: candidate, in: existingWorkouts)
            }.count

            let dates = parsed.workouts.map { $0.startedAt }
            let totalSets = parsed.workouts.reduce(0) { $0 + $1.totalSets }

            return StrongImportPreview(
                workouts: parsed.workouts,
                totalSetCount: totalSets,
                uniqueExerciseCount: uniqueNames.count,
                matchedExerciseCount: matchedCount,
                newExerciseNames: newNames.sorted(),
                duplicateWorkoutCount: duplicateCount,
                earliestDate: dates.min(),
                latestDate: dates.max(),
                detectedDelimiter: parsed.delimiter == ";" ? "Semikolon (;)" : "Komma (,)",
                detectedUnitHint: parsed.detectedUnitHint
            )
        }
    }

    static func performImport(
        preview: StrongImportPreview,
        skipDuplicates: Bool = true,
        gymId: String? = nil,
        into database: AppDatabase
    ) throws -> StrongImportResult {
        try database.dbWriter.write { db in
            let existingExercises = try Exercise.fetchAll(db)
            let existingWorkouts = try Workout.fetchAll(db)

            var exercisesByLowerName = Dictionary(
                existingExercises.map { (normalizeKey($0.name), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var exercisesById = Dictionary(
                existingExercises.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var importedWorkouts = 0
            var skippedDuplicates = 0
            var importedSets = 0
            var createdExercises = 0

            for parsedWorkout in preview.workouts {
                if skipDuplicates && isDuplicate(candidate: parsedWorkout, in: existingWorkouts) {
                    skippedDuplicates += 1
                    continue
                }

                let nonEmptyExercises = parsedWorkout.exercises.filter { !$0.sets.isEmpty }
                guard !nonEmptyExercises.isEmpty else { continue }

                let finishedAt = parsedWorkout.startedAt.addingTimeInterval(TimeInterval(max(60, parsedWorkout.durationSeconds)))
                let workout = Workout(
                    routineId: nil,
                    gymId: gymId,
                    name: parsedWorkout.name,
                    startedAt: parsedWorkout.startedAt,
                    finishedAt: finishedAt,
                    notes: parsedWorkout.notes
                )
                try workout.insert(db)
                importedWorkouts += 1

                for (exIdx, parsedEx) in nonEmptyExercises.enumerated() {
                    let exercise: Exercise
                    if let matched = resolveExistingExercise(
                        rawName: parsedEx.rawName,
                        byLowerName: exercisesByLowerName,
                        byId: exercisesById
                    ) {
                        exercise = matched
                    } else {
                        let created = makeCustomExercise(from: parsedEx.rawName, createdAt: parsedWorkout.startedAt)
                        try created.insert(db)
                        exercisesByLowerName[normalizeKey(created.name)] = created
                        exercisesById[created.id] = created
                        exercise = created
                        createdExercises += 1
                    }

                    let we = WorkoutExercise(
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        sortOrder: exIdx,
                        restSeconds: exercise.defaultRestSeconds,
                        notes: parsedEx.notes
                    )
                    try we.insert(db)

                    for (setIdx, parsedSet) in parsedEx.sets.enumerated() {
                        let normalizedWeight: Double?
                        if let w = parsedSet.weightKg, w > 0 {
                            normalizedWeight = w
                        } else {
                            normalizedWeight = nil
                        }
                        let setRecord = WorkoutSet(
                            workoutExerciseId: we.id,
                            setOrder: setIdx + 1,
                            setType: parsedSet.setType,
                            weightKg: normalizedWeight,
                            reps: parsedSet.reps,
                            rir: parsedSet.rir,
                            isCompleted: true,
                            completedAt: finishedAt
                        )
                        try setRecord.insert(db)
                        importedSets += 1
                    }
                }
            }

            return StrongImportResult(
                importedWorkouts: importedWorkouts,
                skippedDuplicates: skippedDuplicates,
                importedSets: importedSets,
                createdExercises: createdExercises
            )
        }
    }

    // MARK: - CSV Parsing

    private struct RawParseOutput {
        let workouts: [ParsedStrongWorkout]
        let delimiter: Character
        let detectedUnitHint: String
    }

    private struct ColumnMap {
        let workoutNumber: Int?
        let date: Int
        let workoutName: Int?
        let duration: Int?
        let exerciseName: Int
        let setOrder: Int?
        let weight: Int?
        let weightUnit: Int?
        let reps: Int?
        let rpe: Int?
        let seconds: Int?
        let notes: Int?
        let workoutNotes: Int?
        let headerImpliesPounds: Bool
    }

    private static func parseCSV(
        data: Data,
        weightUnitMode: StrongWeightUnitMode
    ) throws -> RawParseOutput {
        guard var content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw StrongImportError.unreadableText
        }

        // Strip UTF-8 BOM if present
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }

        let trimmedCheck = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCheck.isEmpty else {
            throw StrongImportError.emptyFile
        }

        let delimiter = detectDelimiter(in: content)
        let rows = parseRFC4180Rows(content, delimiter: delimiter)
        guard rows.count >= 2 else {
            throw StrongImportError.emptyFile
        }

        let headerRow = rows[0]
        guard let cols = buildColumnMap(from: headerRow) else {
            throw StrongImportError.missingRequiredColumns
        }

        var workoutOrder: [String] = []
        var workoutsByKey: [String: ParsedStrongWorkout] = [:]
        var sawPoundsInRows = false
        var sawKgInRows = false

        for row in rows.dropFirst() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            let rawDate = field(row, cols.date)
            let rawExercise = field(row, cols.exerciseName)
            guard !rawDate.isEmpty, !rawExercise.isEmpty else { continue }

            let rawSetOrder = cols.setOrder.map { field(row, $0) } ?? ""
            let lowerSetOrder = rawSetOrder.lowercased()

            // Skip Strong rest-timer rows
            if lowerSetOrder.contains("rest timer") || lowerSetOrder.contains("pausentimer") {
                continue
            }

            guard let startedAt = parseDate(rawDate) else { continue }

            let rawWorkoutName = cols.workoutName.map { field(row, $0) } ?? ""
            let workoutName = rawWorkoutName.isEmpty ? "Strong Import" : rawWorkoutName
            let workoutNum = cols.workoutNumber.map { field(row, $0) } ?? ""
            let workoutKey = workoutNum.isEmpty
                ? "\(rawDate)|\(workoutName)"
                : "\(workoutNum)|\(rawDate)"

            let durationStr = cols.duration.map { field(row, $0) } ?? ""
            let durationSeconds = parseDurationSeconds(durationStr) ?? 0
            let workoutNoteStr = cols.workoutNotes.map { field(row, $0) } ?? ""
            let rowNoteStr = cols.notes.map { field(row, $0) } ?? ""

            if workoutsByKey[workoutKey] == nil {
                workoutOrder.append(workoutKey)
                workoutsByKey[workoutKey] = ParsedStrongWorkout(
                    id: workoutKey,
                    name: workoutName,
                    startedAt: startedAt,
                    durationSeconds: durationSeconds,
                    notes: workoutNoteStr.isEmpty ? nil : workoutNoteStr,
                    exercises: []
                )
            } else if var existing = workoutsByKey[workoutKey] {
                if existing.durationSeconds == 0 && durationSeconds > 0 {
                    existing = ParsedStrongWorkout(
                        id: existing.id,
                        name: existing.name,
                        startedAt: existing.startedAt,
                        durationSeconds: durationSeconds,
                        notes: existing.notes ?? (workoutNoteStr.isEmpty ? nil : workoutNoteStr),
                        exercises: existing.exercises
                    )
                    workoutsByKey[workoutKey] = existing
                } else if existing.notes == nil && !workoutNoteStr.isEmpty {
                    existing.notes = workoutNoteStr
                    workoutsByKey[workoutKey] = existing
                }
            }

            guard var workout = workoutsByKey[workoutKey] else { continue }

            let exIndex: Int
            if let foundIdx = workout.exercises.firstIndex(where: { normalizeKey($0.rawName) == normalizeKey(rawExercise) }) {
                exIndex = foundIdx
            } else {
                workout.exercises.append(ParsedStrongExercise(rawName: rawExercise, notes: nil, sets: []))
                exIndex = workout.exercises.count - 1
            }

            // Strong "Note" rows attach to exercise notes rather than creating a set
            if lowerSetOrder == "note" || lowerSetOrder == "notiz" {
                if !rowNoteStr.isEmpty {
                    if let existingNote = workout.exercises[exIndex].notes, !existingNote.isEmpty {
                        if !existingNote.contains(rowNoteStr) {
                            workout.exercises[exIndex].notes = existingNote + "\n" + rowNoteStr
                        }
                    } else {
                        workout.exercises[exIndex].notes = rowNoteStr
                    }
                }
                workoutsByKey[workoutKey] = workout
                continue
            }

            if !rowNoteStr.isEmpty {
                if let existingNote = workout.exercises[exIndex].notes, !existingNote.isEmpty {
                    if !existingNote.contains(rowNoteStr) {
                        workout.exercises[exIndex].notes = existingNote + "\n" + rowNoteStr
                    }
                } else {
                    workout.exercises[exIndex].notes = rowNoteStr
                }
            }

            let rowUnit = cols.weightUnit.map { field(row, $0).lowercased() } ?? ""
            if rowUnit.contains("lb") { sawPoundsInRows = true }
            if rowUnit.contains("kg") { sawKgInRows = true }

            let usePounds: Bool
            switch weightUnitMode {
            case .kilograms:
                usePounds = false
            case .pounds:
                usePounds = true
            case .auto:
                if rowUnit.contains("lb") {
                    usePounds = true
                } else if rowUnit.contains("kg") {
                    usePounds = false
                } else {
                    usePounds = cols.headerImpliesPounds
                }
            }

            let rawWeight = cols.weight.flatMap { parseDouble(field(row, $0)) }
            let weightKg: Double?
            if let w = rawWeight {
                if usePounds {
                    weightKg = ((w * lbsToKgFactor) * 100.0).rounded() / 100.0
                } else {
                    weightKg = w
                }
            } else {
                weightKg = nil
            }

            let rawReps = cols.reps.flatMap { parseInt(field(row, $0)) }
            let reps = (rawReps ?? 0) > 0 ? rawReps : nil
            let seconds = cols.seconds.flatMap { parseInt(field(row, $0)) }

            // Ignore completely empty rows that have neither weight, reps, nor timed seconds
            if (weightKg ?? 0) <= 0 && reps == nil && (seconds ?? 0) <= 0 {
                workoutsByKey[workoutKey] = workout
                continue
            }

            let rir: Int?
            if let rpe = cols.rpe.flatMap({ parseDouble(field(row, $0)) }), rpe >= 5.0, rpe <= 10.0 {
                rir = max(0, min(4, Int((10.0 - rpe).rounded())))
            } else {
                rir = nil
            }

            let setType = parseSetType(rawSetOrder)
            workout.exercises[exIndex].sets.append(
                ParsedStrongSet(
                    setType: setType,
                    weightKg: weightKg,
                    reps: reps,
                    rir: rir
                )
            )
            workoutsByKey[workoutKey] = workout
        }

        let workouts: [ParsedStrongWorkout] = workoutOrder.compactMap { key in
            guard var w = workoutsByKey[key] else { return nil }
            w.exercises = w.exercises.filter { !$0.sets.isEmpty }
            guard !w.exercises.isEmpty else { return nil }
            if w.durationSeconds <= 0 {
                // Reasonable fallback duration if Strong CSV omitted Duration
                let estimated = max(600, min(5400, w.totalSets * 150))
                return ParsedStrongWorkout(
                    id: w.id,
                    name: w.name,
                    startedAt: w.startedAt,
                    durationSeconds: estimated,
                    notes: w.notes,
                    exercises: w.exercises
                )
            }
            return w
        }
        .sorted { $0.startedAt > $1.startedAt }

        let unitHint: String
        switch weightUnitMode {
        case .kilograms:
            unitHint = "kg (manuell)"
        case .pounds:
            unitHint = "lbs → kg (manuell)"
        case .auto:
            if sawPoundsInRows && sawKgInRows {
                unitHint = "Gemischt (kg & lbs → kg)"
            } else if sawPoundsInRows || cols.headerImpliesPounds {
                unitHint = "lbs → kg (erkannt)"
            } else {
                unitHint = "kg (Standard/erkannt)"
            }
        }

        return RawParseOutput(
            workouts: workouts,
            delimiter: delimiter,
            detectedUnitHint: unitHint
        )
    }

    private static func detectDelimiter(in text: String) -> Character {
        var inQuotes = false
        var commaCount = 0
        var semicolonCount = 0

        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if ch == "\n" || ch == "\r" {
                    break
                } else if ch == "," {
                    commaCount += 1
                } else if ch == ";" {
                    semicolonCount += 1
                }
            }
        }
        return semicolonCount > commaCount ? ";" : ","
    }

    private static func parseRFC4180Rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if c == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 1
                    }
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else if c == "\n" {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(c)
                }
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    private static func buildColumnMap(from headers: [String]) -> ColumnMap? {
        let normalized = headers.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        func find(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let idx = normalized.firstIndex(of: candidate) {
                    return idx
                }
            }
            return nil
        }

        guard let dateIdx = find(["date", "datum"]),
              let exerciseIdx = find(["exercise name", "übungsname", "exercise", "übung"]) else {
            return nil
        }

        let weightIdx = find([
            "weight", "gewicht",
            "weight (kg)", "weight (lbs)", "weight (lb)",
            "gewicht (kg)", "gewicht (lbs)", "gewicht (lb)"
        ])
        let headerImpliesPounds = weightIdx.map { normalized[$0].contains("lb") } ?? false

        return ColumnMap(
            workoutNumber: find(["workout #", "workout number", "workout-nr", "workout-nr."]),
            date: dateIdx,
            workoutName: find(["workout name", "workout-name", "title", "name"]),
            duration: find(["duration", "workout duration", "dauer", "trainingsdauer"]),
            exerciseName: exerciseIdx,
            setOrder: find(["set order", "satzreihenfolge", "set", "satz"]),
            weight: weightIdx,
            weightUnit: find(["weight unit", "gewichtseinheit"]),
            reps: find(["reps", "wiederholungen", "wdh", "wdh."]),
            rpe: find(["rpe"]),
            seconds: find(["seconds", "sekunden", "duration (sec)"]),
            notes: find(["notes", "notizen", "set notes", "satznotizen"]),
            workoutNotes: find(["workout notes", "workout-notizen", "trainingsnotizen"]),
            headerImpliesPounds: headerImpliesPounds
        )
    }

    private static func field(_ row: [String], _ index: Int) -> String {
        guard index >= 0 && index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Field Parsers

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "dd.MM.yyyy HH:mm:ss",
            "dd.MM.yyyy HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        if let iso = isoFormatterWithFractional.date(from: trimmed) ?? isoFormatterStandard.date(from: trimmed) {
            return iso
        }
        return nil
    }

    private static func parseDurationSeconds(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        // Pure number (seconds, e.g. "3600")
        if let secs = Int(s), secs > 0 {
            return secs
        }

        // Colon format HH:mm:ss or mm:ss
        if s.contains(":") {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 {
                return parts[0] * 3600 + parts[1] * 60 + parts[2]
            } else if parts.count == 2 {
                return parts[0] * 60 + parts[1]
            }
        }

        // Token format like "1h 12m 30s", "45m", "3600s", "1 std 15 min"
        var total = 0
        var numberBuffer = ""
        var unitBuffer = ""

        func flush() {
            guard let val = Int(numberBuffer), val > 0 else {
                numberBuffer = ""
                unitBuffer = ""
                return
            }
            let u = unitBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if u.hasPrefix("h") || u.hasPrefix("std") {
                total += val * 3600
            } else if u.hasPrefix("m") {
                total += val * 60
            } else if u.hasPrefix("s") {
                total += val
            }
            numberBuffer = ""
            unitBuffer = ""
        }

        for ch in s {
            if ch.isNumber {
                if !unitBuffer.isEmpty {
                    flush()
                }
                numberBuffer.append(ch)
            } else if ch.isLetter {
                unitBuffer.append(ch)
            } else if ch.isWhitespace && !unitBuffer.isEmpty {
                flush()
            }
        }
        flush()

        return total > 0 ? total : nil
    }

    private static func parseDouble(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static func parseInt(_ raw: String) -> Int? {
        if let exact = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return exact
        }
        if let dbl = parseDouble(raw) {
            return Int(dbl.rounded())
        }
        return nil
    }

    private static func parseSetType(_ raw: String) -> SetType {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "w" || lower.contains("warm") || lower.contains("aufwärm") {
            return .warmup
        }
        if lower == "d" || lower.contains("drop") {
            return .dropset
        }
        if lower == "f" || lower.contains("fail") || lower.contains("versagen") {
            return .failure
        }
        return .normal
    }

    // MARK: - Duplicate Detection & Exercise Matching

    private static func normalizeKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func isDuplicate(candidate: ParsedStrongWorkout, in existingWorkouts: [Workout]) -> Bool {
        let candidateName = normalizeKey(candidate.name)
        return existingWorkouts.contains { existing in
            normalizeKey(existing.name) == candidateName
                && abs(existing.startedAt.timeIntervalSince(candidate.startedAt)) < 60
        }
    }

    private static let strongAliasToSeedId: [String: String] = [
        // Chest
        "bench press (barbell)": "seed-bench-press-barbell",
        "incline bench press (dumbbell)": "seed-incline-bench-dumbbell",
        "chest press (machine)": "seed-chest-press-machine",
        "chest fly (cable)": "seed-cable-fly",
        "cable crossover": "seed-cable-fly",
        "cable fly": "seed-cable-fly",
        "chest dip": "seed-dips-chest",
        "triceps dip": "seed-dips-chest",
        "dip": "seed-dips-chest",
        "push up": "seed-pushups",
        "push-up": "seed-pushups",
        "push ups": "seed-pushups",

        // Back
        "deadlift (barbell)": "seed-deadlift-barbell",
        "pull up": "seed-pullups",
        "pull-up": "seed-pullups",
        "pull ups": "seed-pullups",
        "lat pulldown (cable)": "seed-lat-pulldown",
        "lat pulldown (machine)": "seed-lat-pulldown",
        "lat pulldown": "seed-lat-pulldown",
        "bent over row (barbell)": "seed-barbell-row",
        "barbell row": "seed-barbell-row",
        "seated row (cable)": "seed-seated-cable-row",
        "seated cable row": "seed-seated-cable-row",
        "bent over one arm row (dumbbell)": "seed-dumbbell-row",
        "bent over row (dumbbell)": "seed-dumbbell-row",
        "dumbbell row": "seed-dumbbell-row",

        // Shoulders
        "overhead press (barbell)": "seed-overhead-press-barbell",
        "military press (barbell)": "seed-overhead-press-barbell",
        "shoulder press (barbell)": "seed-overhead-press-barbell",
        "overhead press (dumbbell)": "seed-overhead-press-dumbbell",
        "seated overhead press (dumbbell)": "seed-overhead-press-dumbbell",
        "shoulder press (dumbbell)": "seed-overhead-press-dumbbell",
        "lateral raise (dumbbell)": "seed-lateral-raise-dumbbell",
        "lateral raise (cable)": "seed-lateral-raise-cable",
        "face pull (cable)": "seed-face-pulls",
        "face pull": "seed-face-pulls",
        "reverse fly (machine)": "seed-reverse-fly-machine",
        "rear delt reverse fly (machine)": "seed-reverse-fly-machine",

        // Legs
        "squat (barbell)": "seed-squat-barbell",
        "back squat (barbell)": "seed-squat-barbell",
        "romanian deadlift (barbell)": "seed-romanian-deadlift",
        "leg press": "seed-leg-press",
        "leg press (machine)": "seed-leg-press",
        "sled leg press": "seed-leg-press",
        "bulgarian split squat": "seed-bulgarian-split-squat",
        "bulgarian split squat (dumbbell)": "seed-bulgarian-split-squat",
        "leg extension (machine)": "seed-leg-extension",
        "lying leg curl (machine)": "seed-leg-curl",
        "seated leg curl (machine)": "seed-leg-curl",
        "leg curl (machine)": "seed-leg-curl",
        "standing calf raise (machine)": "seed-standing-calf-raise",
        "calf raise (standing)": "seed-standing-calf-raise",

        // Biceps
        "bicep curl (barbell)": "seed-barbell-curl",
        "barbell curl": "seed-barbell-curl",
        "bicep curl (dumbbell)": "seed-dumbbell-curl",
        "dumbbell curl": "seed-dumbbell-curl",
        "hammer curl (dumbbell)": "seed-hammer-curl",
        "hammer curl": "seed-hammer-curl",
        "bicep curl (cable)": "seed-cable-curl",
        "cable curl": "seed-cable-curl",

        // Triceps
        "triceps pushdown (cable - straight bar)": "seed-triceps-pushdown",
        "triceps pushdown (cable)": "seed-triceps-pushdown",
        "tricep pushdown (cable)": "seed-triceps-pushdown",
        "triceps rope pushdown": "seed-triceps-pushdown",
        "triceps extension (cable)": "seed-overhead-triceps-cable",
        "overhead triceps extension (cable)": "seed-overhead-triceps-cable",
        "skullcrusher (barbell)": "seed-skullcrushers",
        "skullcrusher (ez bar)": "seed-skullcrushers",
        "skullcrusher (dumbbell)": "seed-skullcrushers",

        // Core
        "hanging leg raise": "seed-hanging-leg-raise",
        "hanging knee raise": "seed-hanging-leg-raise",
        "cable crunch": "seed-cable-crunch",
        "plank": "seed-plank",
        "ab wheel": "seed-ab-wheel"
    ]

    private static func resolveExistingExercise(
        rawName: String,
        byLowerName: [String: Exercise],
        byId: [String: Exercise]
    ) -> Exercise? {
        let key = normalizeKey(rawName)
        if let direct = byLowerName[key] {
            return direct
        }
        if let seedId = strongAliasToSeedId[key], let seeded = byId[seedId] {
            return seeded
        }
        return nil
    }

    private static func makeCustomExercise(from rawName: String, createdAt: Date) -> Exercise {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let equipment = inferEquipment(from: trimmed)
        let muscleGroup = inferMuscleGroup(from: trimmed)
        let defaultRest: Int
        switch muscleGroup {
        case .legs, .back, .chest:
            defaultRest = equipment == .barbell ? 150 : 90
        case .shoulders:
            defaultRest = 90
        case .biceps, .triceps, .core, .other:
            defaultRest = 60
        }

        return Exercise(
            name: trimmed,
            muscleGroup: muscleGroup,
            equipment: equipment,
            defaultRestSeconds: defaultRest,
            isCustom: true,
            isArchived: false,
            notes: "Aus Strong-App importiert",
            createdAt: createdAt
        )
    }

    private static func inferEquipment(from name: String) -> Equipment {
        let lower = name.lowercased()
        if lower.contains("barbell") || lower.contains("langhantel") || lower.contains("ez bar") || lower.contains("trap bar") {
            return .barbell
        }
        if lower.contains("dumbbell") || lower.contains("kurzhantel") {
            return .dumbbell
        }
        if lower.contains("cable") || lower.contains("kabel") || lower.contains("rope") {
            return .cable
        }
        if lower.contains("machine") || lower.contains("maschine") || lower.contains("smith") || lower.contains("sled") || lower.contains("hack") {
            return .machine
        }
        if lower.contains("kettlebell") {
            return .kettlebell
        }
        if lower.contains("bodyweight") || lower.contains("körpergewicht") || lower.contains("push up") || lower.contains("pull up") || lower.contains("chin up") || lower.contains("plank") || lower.contains("dip") {
            return .bodyweight
        }
        return .other
    }

    private static func inferMuscleGroup(from name: String) -> MuscleGroup {
        let lower = name.lowercased()
        if lower.contains("bench") || lower.contains("chest") || lower.contains("pec") || lower.contains("fly") || lower.contains("brust") || lower.contains("bankdrück") || lower.contains("liegestütz") {
            if !lower.contains("reverse") && !lower.contains("rear") {
                return .chest
            }
        }
        if lower.contains("tricep") || lower.contains("trizeps") || lower.contains("pushdown") || lower.contains("skullcrusher") || lower.contains("french press") || lower.contains("kickback") {
            return .triceps
        }
        if lower.contains("bicep") || lower.contains("bizeps") || lower.contains("curl") || lower.contains("preacher") {
            if !lower.contains("leg") && !lower.contains("bein") && !lower.contains("wrist") {
                return .biceps
            }
        }
        if lower.contains("squat") || lower.contains("leg") || lower.contains("lunge") || lower.contains("calf") || lower.contains("glute") || lower.contains("hip thrust") || lower.contains("rdl") || lower.contains("romanian") || lower.contains("kniebeug") || lower.contains("bein") || lower.contains("wade") || lower.contains("ausfallschritt") {
            return .legs
        }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull up") || lower.contains("pull-up") || lower.contains("chin up") || lower.contains("deadlift") || lower.contains("lat") || lower.contains("back extension") || lower.contains("rücken") || lower.contains("rudern") || lower.contains("klimmzug") || lower.contains("latzug") || lower.contains("kreuzheben") {
            return .back
        }
        if lower.contains("shoulder") || lower.contains("overhead") || lower.contains("military") || lower.contains("lateral raise") || lower.contains("front raise") || lower.contains("delt") || lower.contains("shrug") || lower.contains("face pull") || lower.contains("reverse fly") || lower.contains("arnold") || lower.contains("schulter") || lower.contains("seitheben") {
            return .shoulders
        }
        if lower.contains("crunch") || lower.contains("plank") || lower.contains("ab ") || lower.contains("abs") || lower.contains("core") || lower.contains("sit up") || lower.contains("leg raise") || lower.contains("russian twist") || lower.contains("bauch") {
            return .core
        }
        return .other
    }
}
