import Foundation
import SwiftData

/// Builds compact weekly stats locally, sends them to Gemini for a coach-style
/// narrative, and caches the result per week.
@MainActor
enum ReportEngine {
    static func currentWeekStart(_ now: Date = .now) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    }

    static func generate(context: ModelContext) async throws -> WeeklyReport {
        let calendar = Calendar.current
        let weekStart = currentWeekStart()
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)!

        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let supplements = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let profile = ((try? context.fetch(FetchDescriptor<UserProfile>())) ?? []).first

        let thisWeek = stats(from: weekStart, days: 7, sets: sets, foods: foods, weights: weights, supplements: supplements)
        let lastWeek = stats(from: previousStart, days: 7, sets: sets, foods: foods, weights: weights, supplements: supplements)

        let payload: [String: Any] = ["this_week": thisWeek, "last_week": lastWeek]
        let json = String(
            data: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            encoding: .utf8
        ) ?? "{}"

        let profileLine = profile.map {
            "User: 170 cm, bulking, goal \(Int($0.goalWeightKg)) kg. Daily targets: \($0.dailyCalories) kcal, \($0.dailyProteinG)g protein."
        } ?? "User is bulking."

        let system = """
        You are a concise, no-nonsense strength coach reviewing a week of training and nutrition logs. \(profileLine)

        You receive JSON stats for this week and last week. Averages are computed over days that have any food logged; days_logged tells you how complete the tracking was. Write a weekly report in plain prose (no markdown, no headers):
        1. Two or three sentences on what actually happened — calories/protein vs targets, training volume, lift progression, weight trend.
        2. The single most important gap (undertrained muscle group, protein shortfall, inconsistent logging).
        3. Two or three specific, small actions for next week.
        Keep it under 170 words. Be direct and encouraging, never generic.
        """

        let text = try await GeminiClient(model: GeminiClient.defaultReportModel)
            .generate(system: system, user: json)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Upsert this week's report.
        if let existing = ((try? context.fetch(FetchDescriptor<WeeklyReport>())) ?? [])
            .first(where: { calendar.isDate($0.weekStart, inSameDayAs: weekStart) }) {
            existing.text = text
            existing.createdAt = .now
            return existing
        }
        let report = WeeklyReport(weekStart: weekStart, text: text)
        context.insert(report)
        return report
    }

    private static func stats(
        from start: Date,
        days: Int,
        sets: [WorkoutSet],
        foods: [FoodEntry],
        weights: [BodyWeightEntry],
        supplements: [SupplementEntry]
    ) -> [String: Any] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        let inWindow: (Date) -> Bool = { $0 >= start && $0 < end }

        let weekFoods = foods.filter { inWindow($0.timestamp) }
        let weekSets = sets.filter { inWindow($0.timestamp) }
        let weekWeights = weights.filter { inWindow($0.date) }.sorted { $0.date < $1.date }
        let weekSupplements = supplements.filter { inWindow($0.timestamp) }

        // Per-day nutrition, only counting days that logged anything.
        var dayCalories: [Date: Int] = [:]
        var dayProtein: [Date: Double] = [:]
        for food in weekFoods {
            let day = calendar.startOfDay(for: food.timestamp)
            dayCalories[day, default: 0] += food.calories
            dayProtein[day, default: 0] += food.proteinG
        }
        let loggedDays = dayCalories.count
        let avgCalories = loggedDays == 0 ? 0 : dayCalories.values.reduce(0, +) / loggedDays
        let avgProtein = loggedDays == 0 ? 0 : Int(dayProtein.values.reduce(0, +)) / loggedDays

        // Training: volume per muscle group, top set per exercise.
        var groupSets: [String: Int] = [:]
        var topSet: [String: String] = [:]
        var topWeight: [String: Double] = [:]
        for set in weekSets {
            guard let exercise = set.exercise else { continue }
            for group in exercise.muscleGroups { groupSets[group, default: 0] += 1 }
            if set.weightKg >= topWeight[exercise.name] ?? -1 {
                topWeight[exercise.name] = set.weightKg
                topSet[exercise.name] = "\(set.weightKg.formatted()) kg x \(set.reps)"
            }
        }

        var result: [String: Any] = [
            "days_with_food_logged": loggedDays,
            "avg_calories_on_logged_days": avgCalories,
            "avg_protein_g_on_logged_days": avgProtein,
            "total_sets": weekSets.count,
            "total_volume_kg": Int(weekSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }),
            "sets_per_muscle_group": groupSets,
            "top_set_per_exercise": topSet,
            "supplement_days": Set(weekSupplements.map { calendar.startOfDay(for: $0.timestamp) }).count
        ]
        if let first = weekWeights.first, let last = weekWeights.last {
            result["body_weight_start_kg"] = first.weightKg
            result["body_weight_end_kg"] = last.weightKg
        }
        return result
    }
}
