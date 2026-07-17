import Foundation
import SwiftData

/// What a weekly report renders from: locally computed stat tiles plus
/// AI-written sections. Serialized as JSON into `WeeklyReport.text`
/// (older reports that fail to decode render as plain text).
struct ReportContent: Codable {
    struct Tile: Codable, Hashable {
        let label: String
        let value: String
    }
    let tiles: [Tile]
    let summary: String
    let onTrack: [String]
    let focus: [String]
    let actions: [String]

    enum CodingKeys: String, CodingKey {
        case tiles, summary
        case onTrack = "on_track"
        case focus, actions
    }
}

/// Builds compact weekly stats locally, asks Gemini for the narrative
/// sections, and caches the combined result per week.
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

        let thisWeek = stats(from: weekStart, sets: sets, foods: foods, weights: weights, supplements: supplements, profile: profile)
        let lastWeek = stats(from: previousStart, sets: sets, foods: foods, weights: weights, supplements: supplements, profile: profile)

        // Apple Health enrichment (silently absent when not authorized).
        let steps = await HealthService.shared.averageDailySteps(from: weekStart, days: 7)
        let activeEnergy = await HealthService.shared.averageDailyActiveEnergy(from: weekStart, days: 7)

        var payload: [String: Any] = ["this_week": thisWeek.json, "last_week": lastWeek.json]
        if let steps { payload["avg_daily_steps"] = steps }
        if let activeEnergy { payload["avg_daily_active_energy_kcal"] = activeEnergy }
        let json = String(
            data: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            encoding: .utf8
        ) ?? "{}"

        let profileLine = profile.map {
            "User: 170 cm, bulking, goal \(Int($0.goalWeightKg)) kg. Daily targets: \($0.dailyCalories) kcal, \($0.dailyProteinG)g protein, \($0.dailyFiberG)g fiber."
        } ?? "User is bulking."

        let system = """
        You are a concise, no-nonsense strength coach reviewing a week of training and nutrition logs. \(profileLine)

        You receive JSON stats for this week and last week (averages cover only days with food logged; days_with_food_logged shows tracking completeness). Reply ONLY with JSON, exactly this shape:
        {"summary": "2-3 sentences on what actually happened", "on_track": ["short bullet", ...], "focus": ["the 1-2 most important gaps", ...], "actions": ["specific small action for next week", ...]}
        2-3 items per list, each under 12 words. Be direct and specific to the data, never generic.
        """

        let reply = try await Self.generateWithFallback(system: system, user: json)

        let sections = try decodeSections(reply)
        let content = ReportContent(
            tiles: tiles(thisWeek: thisWeek, lastWeek: lastWeek, steps: steps),
            summary: sections.summary,
            onTrack: sections.onTrack,
            focus: sections.focus,
            actions: sections.actions
        )
        let stored = String(data: try JSONEncoder().encode(content), encoding: .utf8) ?? sections.summary

        if let existing = ((try? context.fetch(FetchDescriptor<WeeklyReport>())) ?? [])
            .first(where: { calendar.isDate($0.weekStart, inSameDayAs: weekStart) }) {
            existing.text = stored
            existing.createdAt = .now
            return existing
        }
        let report = WeeklyReport(weekStart: weekStart, text: stored)
        context.insert(report)
        return report
    }

    /// The report model, falling back to the logging model when the report
    /// model is overloaded (503) or out of quota (429) — billing doesn't
    /// exempt anyone from server-side "high demand".
    static func generateWithFallback(system: String, user: String) async throws -> String {
        do {
            return try await GeminiClient(model: GeminiClient.defaultReportModel)
                .generate(system: system, user: user, jsonOutput: true)
        } catch GeminiError.badResponse(let code, _) where code == 503 || code == 429 {
            guard GeminiClient.defaultReportModel != GeminiClient.defaultParseModel else { throw GeminiError.badResponse(code, "") }
            return try await GeminiClient(model: GeminiClient.defaultParseModel)
                .generate(system: system, user: user, jsonOutput: true)
        }
    }

    private struct Sections: Decodable {
        let summary: String
        let onTrack: [String]
        let focus: [String]
        let actions: [String]

        enum CodingKeys: String, CodingKey {
            case summary
            case onTrack = "on_track"
            case focus, actions
        }
    }

    private static func decodeSections(_ reply: String) throws -> Sections {
        let trimmed: String
        if let start = reply.firstIndex(of: "{") {
            trimmed = String(reply[start...])
        } else {
            trimmed = reply
        }
        return try JSONDecoder().decode(Sections.self, from: Data(trimmed.utf8))
    }

    // MARK: - Local stats

    struct WeekStats {
        var daysLogged = 0
        var avgCalories = 0
        var avgProtein = 0
        var proteinGoalDays = 0
        var totalSets = 0
        var totalVolume = 0
        var groupSets: [String: Int] = [:]
        var topSets: [String: String] = [:]
        var weightStart: Double?
        var weightEnd: Double?
        var supplementDays = 0

        var json: [String: Any] {
            var result: [String: Any] = [
                "days_with_food_logged": daysLogged,
                "avg_calories_on_logged_days": avgCalories,
                "avg_protein_g_on_logged_days": avgProtein,
                "days_protein_target_hit": proteinGoalDays,
                "total_sets": totalSets,
                "total_volume_kg": totalVolume,
                "sets_per_muscle_group": groupSets,
                "top_set_per_exercise": topSets,
                "supplement_days": supplementDays
            ]
            if let weightStart { result["body_weight_start_kg"] = weightStart }
            if let weightEnd { result["body_weight_end_kg"] = weightEnd }
            return result
        }
    }

    private static func stats(
        from start: Date,
        sets: [WorkoutSet],
        foods: [FoodEntry],
        weights: [BodyWeightEntry],
        supplements: [SupplementEntry],
        profile: UserProfile?
    ) -> WeekStats {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let inWindow: (Date) -> Bool = { $0 >= start && $0 < end }

        var s = WeekStats()

        var dayCalories: [Date: Int] = [:]
        var dayProtein: [Date: Double] = [:]
        for food in foods where inWindow(food.timestamp) {
            let day = calendar.startOfDay(for: food.timestamp)
            dayCalories[day, default: 0] += food.calories
            dayProtein[day, default: 0] += food.proteinG
        }
        s.daysLogged = dayCalories.count
        if s.daysLogged > 0 {
            s.avgCalories = dayCalories.values.reduce(0, +) / s.daysLogged
            s.avgProtein = Int(dayProtein.values.reduce(0, +)) / s.daysLogged
        }
        let proteinTarget = Double(profile?.dailyProteinG ?? 150)
        s.proteinGoalDays = dayProtein.values.filter { $0 >= proteinTarget }.count

        var topWeight: [String: Double] = [:]
        for set in sets where inWindow(set.timestamp) {
            s.totalSets += 1
            s.totalVolume += Int(set.weightKg * Double(set.reps))
            guard let exercise = set.exercise else { continue }
            for group in exercise.muscleGroups { s.groupSets[group, default: 0] += 1 }
            if set.weightKg >= topWeight[exercise.name] ?? -1 {
                topWeight[exercise.name] = set.weightKg
                s.topSets[exercise.name] = "\(set.weightKg.formatted()) kg x \(set.reps)"
            }
        }

        let weekWeights = weights.filter { inWindow($0.date) }.sorted { $0.date < $1.date }
        s.weightStart = weekWeights.first?.weightKg
        s.weightEnd = weekWeights.last?.weightKg

        s.supplementDays = Set(
            supplements.filter { inWindow($0.timestamp) }.map { calendar.startOfDay(for: $0.timestamp) }
        ).count

        return s
    }

    private static func tiles(thisWeek: WeekStats, lastWeek: WeekStats, steps: Int?) -> [ReportContent.Tile] {
        var tiles: [ReportContent.Tile] = [
            .init(label: "Protein target hit", value: "\(thisWeek.proteinGoalDays)/7 days"),
            .init(label: "Food logged", value: "\(thisWeek.daysLogged)/7 days"),
            .init(label: "Training volume", value: volumeValue(thisWeek: thisWeek, lastWeek: lastWeek))
        ]
        if let start = thisWeek.weightStart, let end = thisWeek.weightEnd, start != end {
            tiles.append(.init(label: "Body weight", value: String(format: "%+.1f kg", end - start)))
        } else if let end = thisWeek.weightEnd {
            tiles.append(.init(label: "Body weight", value: String(format: "%.1f kg", end)))
        }
        if let steps {
            tiles.append(.init(label: "Steps", value: "\((Double(steps) / 1000).formatted(.number.precision(.fractionLength(1))))k/day"))
        }
        return tiles
    }

    private static func volumeValue(thisWeek: WeekStats, lastWeek: WeekStats) -> String {
        let current = "\(thisWeek.totalVolume.formatted()) kg"
        guard lastWeek.totalVolume > 0 else { return current }
        let change = Int((Double(thisWeek.totalVolume - lastWeek.totalVolume) / Double(lastWeek.totalVolume)) * 100)
        return "\(current) (\(change >= 0 ? "+" : "")\(change)%)"
    }
}
