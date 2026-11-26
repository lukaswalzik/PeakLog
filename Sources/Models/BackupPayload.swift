import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupPayload: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var exercises: [Exercise]
    var routines: [Routine]
    var routineExercises: [RoutineExercise]
    var workouts: [Workout]
    var workoutExercises: [WorkoutExercise]
    var workoutSets: [WorkoutSet]
    var bodyweightEntries: [BodyweightEntry]?
    var bodyweightPhotos: [BodyweightPhoto]?
    var cardioSessions: [CardioSession]?
    var gyms: [Gym]?
    var foodItems: [FoodItem]?
    var foodLogEntries: [FoodLogEntry]?
    var savedMeals: [SavedMeal]?
    var savedMealItems: [SavedMealItem]?

    init(
        schemaVersion: Int = 6,
        exportedAt: Date = Date(),
        exercises: [Exercise],
        routines: [Routine],
        routineExercises: [RoutineExercise],
        workouts: [Workout],
        workoutExercises: [WorkoutExercise],
        workoutSets: [WorkoutSet],
        bodyweightEntries: [BodyweightEntry]? = nil,
        bodyweightPhotos: [BodyweightPhoto]? = nil,
        cardioSessions: [CardioSession]? = nil,
        gyms: [Gym]? = nil,
        foodItems: [FoodItem]? = nil,
        foodLogEntries: [FoodLogEntry]? = nil,
        savedMeals: [SavedMeal]? = nil,
        savedMealItems: [SavedMealItem]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.exercises = exercises
        self.routines = routines
        self.routineExercises = routineExercises
        self.workouts = workouts
        self.workoutExercises = workoutExercises
        self.workoutSets = workoutSets
        self.bodyweightEntries = bodyweightEntries
        self.bodyweightPhotos = bodyweightPhotos
        self.cardioSessions = cardioSessions
        self.gyms = gyms
        self.foodItems = foodItems
        self.foodLogEntries = foodLogEntries
        self.savedMeals = savedMeals
        self.savedMealItems = savedMealItems
    }
}

struct BackupImportSummary: Equatable {
    let exerciseCount: Int
    let routineCount: Int
    let workoutCount: Int
}

struct StrongTrackerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
