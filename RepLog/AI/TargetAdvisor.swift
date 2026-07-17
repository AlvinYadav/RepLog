import Foundation
import SwiftData

struct TargetSuggestion: Decodable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case calories, rationale
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }
}

extension TargetSuggestion: Identifiable {
    var id: String { "\(calories)-\(proteinG)-\(carbsG)-\(fatG)-\(fiberG)" }
}

/// Reviews the user's last two weeks of real data and proposes adjusted
/// daily targets, with a short rationale. Applied only when the user taps Apply.
@MainActor
enum TargetAdvisor {
    static func suggest(context: ModelContext) async throws -> TargetSuggestion {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -14, to: .now)!

        let foods = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []).filter { $0.timestamp >= start }
        let sets = ((try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []).filter { $0.timestamp >= start }
        let weights = ((try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? [])
            .filter { $0.date >= start }
            .sorted { $0.date < $1.date }
        let profile = ((try? context.fetch(FetchDescriptor<UserProfile>())) ?? []).first

        var dayCalories: [Date: Int] = [:]
        var dayProtein: [Date: Double] = [:]
        for food in foods {
            let day = calendar.startOfDay(for: food.timestamp)
            dayCalories[day, default: 0] += food.calories
            dayProtein[day, default: 0] += food.proteinG
        }
        let trainingDays = Set(sets.map { calendar.startOfDay(for: $0.timestamp) }).count

        var payload: [String: Any] = [
            "days_with_food_logged": dayCalories.count,
            "avg_calories_on_logged_days": dayCalories.isEmpty ? 0 : dayCalories.values.reduce(0, +) / dayCalories.count,
            "avg_protein_g_on_logged_days": dayProtein.isEmpty ? 0 : Int(dayProtein.values.reduce(0, +)) / dayProtein.count,
            "training_days": trainingDays
        ]
        if let first = weights.first, let last = weights.last {
            payload["body_weight_start_kg"] = first.weightKg
            payload["body_weight_end_kg"] = last.weightKg
        }
        if let profile {
            payload["current_targets"] = [
                "calories": profile.dailyCalories,
                "protein_g": profile.dailyProteinG,
                "carbs_g": profile.dailyCarbsG,
                "fat_g": profile.dailyFatG,
                "fiber_g": profile.dailyFiberG
            ]
        }
        let json = String(data: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), encoding: .utf8) ?? "{}"

        let profileLine = profile.map {
            "User: 170 cm, currently ~70 kg, lean bulk, goal \(Int($0.goalWeightKg)) kg."
        } ?? "User: 170 cm, lean bulk."

        let system = """
        You are a sports nutrition coach. \(profileLine) Target rate: gaining roughly 0.25-0.5 kg per week — adjust calories up if weight is flat, down if gaining too fast. Protein ~2-2.2 g/kg bodyweight. You receive the last 14 days of the user's logged data as JSON.
        Reply ONLY with JSON: {"calories": int, "protein_g": int, "carbs_g": int, "fat_g": int, "fiber_g": int, "rationale": "under 50 words, referencing their actual data"}
        """

        let reply = try await ReportEngine.generateWithFallback(system: system, user: json)
        let trimmed = reply.firstIndex(of: "{").map { String(reply[$0...]) } ?? reply
        return try JSONDecoder().decode(TargetSuggestion.self, from: Data(trimmed.utf8))
    }
}
