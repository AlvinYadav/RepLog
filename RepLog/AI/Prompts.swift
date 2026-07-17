import Foundation

enum Prompts {
    static func logParsing(profile: UserProfile?, exercises: [Exercise]) -> String {
        let exerciseList = exercises.isEmpty
            ? "(none yet — use sensible canonical gym exercise names)"
            : exercises.map { ex in
                ex.aliases.isEmpty
                    ? "- \(ex.name)"
                    : "- \(ex.name) (aliases: \(ex.aliases.joined(separator: ", ")))"
            }.joined(separator: "\n")

        let profileLine: String
        if let profile {
            profileLine = "User: \(Int(profile.heightCm)) cm, bulking, goal \(Int(profile.goalWeightKg)) kg. Daily targets: \(profile.dailyCalories) kcal, \(profile.dailyProteinG)g protein."
        } else {
            profileLine = "User: bulking."
        }

        return """
        You convert one gym/food log utterance into structured entries. \(profileLine)

        The user's known exercises (map mentions onto these canonical names when they match):
        \(exerciseList)

        Rules:
        - kind=workout_set: ALWAYS fill exercise, weight_kg, and reps (reps = number of repetitions in one set; "40kg 3 reps" → weight_kg=40, reps=3, sets_count=1). "3 sets of 8 at 50" → ONE entry: weight_kg=50, reps=8, sets_count=3. "50 for 8 then 7 then 6" → three separate entries. Bodyweight movements → weight_kg=0. Convert lbs to kg (1 lb = 0.4536 kg). Emit exactly one entry per distinct set mentioned — never duplicate.
        - kind=food: fill food_description (short, itemized) and ESTIMATE calories, protein_g, carbs_g, fat_g realistically for the described portion. Assume normal portions when unspecified.
        - kind=body_weight: statements like "weighed 70.5 this morning" → body_weight_kg.
        - kind=note: anything else worth keeping (soreness, sleep, PRs, plans) → note.
        - An utterance may produce multiple entries of mixed kinds.
        - If genuinely ambiguous (e.g. a number with no context), still produce your best-guess entries AND set clarification to one short question.
        - Weights ≤ 300 both kg-plausible: prefer kg — the user is metric.
        """
    }
}
