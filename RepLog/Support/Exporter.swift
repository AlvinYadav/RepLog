import Foundation
import SwiftData

/// Dumps every record to a single JSON file for backup / portability.
@MainActor
enum Exporter {
    static func exportJSON(context: ModelContext) throws -> URL {
        let formatter = ISO8601DateFormatter()

        func date(_ d: Date) -> String { formatter.string(from: d) }

        let sets = ((try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []).map { set in
            [
                "exercise": set.exercise?.name ?? "",
                "weight_kg": set.weightKg,
                "reps": set.reps,
                "timestamp": date(set.timestamp)
            ] as [String: Any]
        }
        let foods = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []).map { food in
            [
                "description": food.foodDescription,
                "calories": food.calories,
                "protein_g": food.proteinG,
                "carbs_g": food.carbsG,
                "fat_g": food.fatG,
                "fiber_g": food.fiberG,
                "timestamp": date(food.timestamp)
            ] as [String: Any]
        }
        let weights = ((try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []).map { entry in
            ["weight_kg": entry.weightKg, "date": date(entry.date)] as [String: Any]
        }
        let supplements = ((try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []).map { entry in
            ["name": entry.name, "amount": entry.amount ?? "", "timestamp": date(entry.timestamp)] as [String: Any]
        }
        let water = ((try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []).map { entry in
            ["milliliters": entry.milliliters, "timestamp": date(entry.timestamp)] as [String: Any]
        }
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { exercise in
            ["name": exercise.name, "aliases": exercise.aliases, "muscle_groups": exercise.muscleGroups] as [String: Any]
        }

        let payload: [String: Any] = [
            "exported_at": date(.now),
            "exercises": exercises,
            "workout_sets": sets,
            "food_entries": foods,
            "body_weight": weights,
            "supplements": supplements,
            "water": water
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepLog-export-\(stamp).json")
        try data.write(to: url)
        return url
    }
}
