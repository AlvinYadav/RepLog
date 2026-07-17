import Foundation

/// Pure local math: per-day totals and rule-based recommendations.
/// No AI calls — instant and offline.
struct DayMetrics {
    var calories = 0
    var proteinG = 0.0
    var carbsG = 0.0
    var fatG = 0.0
    var setCount = 0
    var volumeKg = 0.0
    var weightKg: Double?
    var supplements: [String] = []
}

enum PlanEngine {
    static func metrics(
        on date: Date,
        foods: [FoodEntry],
        sets: [WorkoutSet],
        weights: [BodyWeightEntry],
        supplements: [SupplementEntry]
    ) -> DayMetrics {
        let cal = Calendar.current
        var m = DayMetrics()
        for food in foods where cal.isDate(food.timestamp, inSameDayAs: date) {
            m.calories += food.calories
            m.proteinG += food.proteinG
            m.carbsG += food.carbsG
            m.fatG += food.fatG
        }
        for set in sets where cal.isDate(set.timestamp, inSameDayAs: date) {
            m.setCount += 1
            m.volumeKg += set.weightKg * Double(set.reps)
        }
        m.weightKg = weights
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .max(by: { $0.date < $1.date })?.weightKg
        m.supplements = supplements
            .filter { cal.isDate($0.timestamp, inSameDayAs: date) }
            .map(\.name)
        return m
    }

    /// Today's coaching lines, most important first.
    static func recommendations(
        profile: UserProfile?,
        exercises: [Exercise],
        allSets: [WorkoutSet],
        allSupplements: [SupplementEntry],
        today: DayMetrics,
        now: Date = .now
    ) -> [String] {
        var recs: [String] = []
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)

        // Muscle groups covered by the user's exercises but untrained for days.
        var groupExercise: [String: String] = [:]
        for exercise in exercises {
            for group in exercise.muscleGroups.map({ $0.lowercased() }) where groupExercise[group] == nil {
                groupExercise[group] = exercise.name
            }
        }
        var groupLastTrained: [String: Date] = [:]
        for set in allSets {
            guard let exercise = set.exercise else { continue }
            for group in exercise.muscleGroups.map({ $0.lowercased() }) {
                if set.timestamp > (groupLastTrained[group] ?? .distantPast) {
                    groupLastTrained[group] = set.timestamp
                }
            }
        }
        let gaps: [(group: String, days: Int)] = groupExercise.keys.compactMap { group in
            guard let last = groupLastTrained[group] else { return nil } // no data yet
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day ?? 0
            return days >= 4 ? (group, days) : nil
        }
        for gap in gaps.sorted(by: { $0.days > $1.days }).prefix(2) {
            let suggestion = groupExercise[gap.group].map { " — \($0)?" } ?? ""
            recs.append("\(gap.group.capitalized) last trained \(gap.days) days ago\(suggestion)")
        }

        // Macro shortfalls, only once the day is far enough along to matter.
        if let profile {
            let proteinLeft = Double(profile.dailyProteinG) - today.proteinG
            if hour >= 15, proteinLeft > 25 {
                recs.append("\(Int(proteinLeft))g protein still to go")
            }
            let caloriesLeft = profile.dailyCalories - today.calories
            if hour >= 18, caloriesLeft > 400 {
                recs.append("\(caloriesLeft) kcal below target — keep the surplus")
            }
        }

        // Supplement habit: only nag about things the user actually takes.
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let habitualSupplements = Set(
            allSupplements
                .filter { $0.timestamp > twoWeeksAgo }
                .map { $0.name.lowercased() }
                .reduce(into: [:]) { counts, name in counts[name, default: 0] += 1 }
                .filter { $0.value >= 3 }
                .keys
        )
        let takenToday = Set(today.supplements.map { $0.lowercased() })
        for supplement in habitualSupplements.subtracting(takenToday).sorted() {
            recs.append("\(supplement.capitalized) not logged today")
        }

        return recs
    }
}
