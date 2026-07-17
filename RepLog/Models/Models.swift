import Foundation
import SwiftData

@Model
final class UserProfile {
    var heightCm: Double
    var goalWeightKg: Double
    var dailyCalories: Int
    var dailyProteinG: Int
    var dailyCarbsG: Int
    var dailyFatG: Int
    var createdAt: Date

    init(
        heightCm: Double = 170,
        goalWeightKg: Double = 75,
        dailyCalories: Int = 2500,
        dailyProteinG: Int = 150,
        dailyCarbsG: Int = 300,
        dailyFatG: Int = 80
    ) {
        self.heightCm = heightCm
        self.goalWeightKg = goalWeightKg
        self.dailyCalories = dailyCalories
        self.dailyProteinG = dailyProteinG
        self.dailyCarbsG = dailyCarbsG
        self.dailyFatG = dailyFatG
        self.createdAt = .now
    }
}

@Model
final class Exercise {
    var name: String
    var aliases: [String]
    var muscleGroups: [String]
    var createdAt: Date

    init(name: String, aliases: [String] = [], muscleGroups: [String] = []) {
        self.name = name
        self.aliases = aliases
        self.muscleGroups = muscleGroups
        self.createdAt = .now
    }
}

@Model
final class WorkoutSet {
    var exercise: Exercise?
    var weightKg: Double
    var reps: Int
    var timestamp: Date

    init(exercise: Exercise?, weightKg: Double, reps: Int, timestamp: Date = .now) {
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
        self.timestamp = timestamp
    }
}

enum FoodSource: String, Codable {
    case text
    case photo
}

@Model
final class FoodEntry {
    var timestamp: Date
    var foodDescription: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var sourceRaw: String
    @Attribute(.externalStorage) var photoData: Data?

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .text }

    init(
        timestamp: Date = .now,
        foodDescription: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        source: FoodSource = .text,
        photoData: Data? = nil
    ) {
        self.timestamp = timestamp
        self.foodDescription = foodDescription
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sourceRaw = source.rawValue
        self.photoData = photoData
    }
}

@Model
final class BodyWeightEntry {
    var date: Date
    var weightKg: Double

    init(date: Date = .now, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

@Model
final class SupplementEntry {
    var name: String
    var amount: String?
    var timestamp: Date

    init(name: String, amount: String? = nil, timestamp: Date = .now) {
        self.name = name
        self.amount = amount
        self.timestamp = timestamp
    }
}

enum RawLogStatus: String, Codable {
    case pending
    case parsed
    case failed
    case note
}

@Model
final class RawLog {
    var timestamp: Date
    var input: String
    var parsedJSON: String?
    var statusRaw: String
    var clarification: String?
    var errorMessage: String?
    /// Attached meal photo (downscaled JPEG) — kept on the log so retry works.
    @Attribute(.externalStorage) var photoData: Data?

    var status: RawLogStatus {
        get { RawLogStatus(rawValue: statusRaw) ?? .note }
        set { statusRaw = newValue.rawValue }
    }

    init(timestamp: Date = .now, input: String, parsedJSON: String? = nil, status: RawLogStatus = .pending) {
        self.timestamp = timestamp
        self.input = input
        self.parsedJSON = parsedJSON
        self.statusRaw = status.rawValue
    }
}
