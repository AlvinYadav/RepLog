import Foundation
import SwiftData

/// Turns a tapped Plan line into a concrete, personal suggestion —
/// grounded in the foods and exercises the user actually logs.
@MainActor
enum SuggestionEngine {
    static func suggest(for item: PlanItem, context: ModelContext) async throws -> String {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -21, to: .now)!

        // The user's real diet: most-logged foods of the last 3 weeks.
        let foods = ((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [])
            .filter { $0.timestamp >= cutoff }
        var foodCounts: [String: Int] = [:]
        for food in foods {
            foodCounts[food.foodDescription, default: 0] += 1
        }
        let usualFoods = foodCounts.sorted { $0.value > $1.value }.prefix(12).map(\.key)

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseList = exercises.map { exercise in
            exercise.muscleGroups.isEmpty
                ? exercise.name
                : "\(exercise.name) (\(exercise.muscleGroups.joined(separator: ", ")))"
        }
        let profile = ((try? context.fetch(FetchDescriptor<UserProfile>())) ?? []).first

        let hour = calendar.component(.hour, from: .now)
        let profileLine = profile.map {
            "User: \(Int($0.heightCm)) cm, bulking toward \(Int($0.goalWeightKg)) kg. Daily targets: \($0.dailyCalories) kcal, \($0.dailyProteinG)g protein."
        } ?? "User: bulking."

        let ask: String
        switch item.kind {
        case .protein(let gap):
            ask = "They still need ~\(gap)g protein today. Suggest 2-3 realistic options (with rough protein and kcal each), strongly preferring foods from their usual list or easy variations of them."
        case .calories(let gap):
            ask = "They're ~\(gap) kcal below their bulking target today. Suggest 2-3 easy, calorie-dense options (with rough kcal each), preferring their usual foods or simple additions like nuts, olive oil, or a shake."
        case .muscleGroup(let group, let exercise):
            ask = "They haven't trained \(group) in days\(exercise.map { "; their usual exercise for it is \($0)" } ?? ""). Suggest a specific mini-plan for today: which of THEIR exercises, sets × reps, and a sensible weight progression hint."
        case .water(let gap):
            ask = "They're \(gap) ml short on water. One short practical tip for catching up this evening without disrupting sleep."
        case .supplement(let name):
            ask = "They usually take \(name) but haven't logged it today. One short reminder-style tip (best timing, with what)."
        }

        let system = """
        You are RepLog's coach. \(profileLine) Local time: \(hour):00.

        Foods this user actually logs (most frequent first):
        \(usualFoods.isEmpty ? "(no history yet — suggest simple common foods)" : usualFoods.map { "- \($0)" }.joined(separator: "\n"))

        Their exercises:
        \(exerciseList.isEmpty ? "(none listed)" : exerciseList.map { "- \($0)" }.joined(separator: "\n"))

        Reply in plain text, max 80 words, no markdown, no preamble — just the suggestion. Be specific with numbers.
        """

        return try await GeminiClient(model: GeminiClient.defaultParseModel)
            .generate(system: system, user: ask)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
