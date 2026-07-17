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

        Respond with ONLY a JSON object, no markdown, exactly this shape:
        {"entries": [ ... ], "clarification": null}

        Entry kinds and their REQUIRED fields:
        - {"kind": "workout_set", "exercise": str, "weight_kg": num, "reps": int, "sets_count": int} — reps = repetitions in one set. "3 sets of 8 at 50" → ONE entry with reps=8, sets_count=3. "50 for 8 then 7" → two entries. Bodyweight movements → weight_kg=0. Convert lbs to kg (1 lb = 0.4536 kg). Exactly one entry per distinct set mentioned — never duplicate.
        - {"kind": "food", "food_description": str, "calories": int, "protein_g": num, "carbs_g": num, "fat_g": num} — short itemized description; ESTIMATE macros realistically for the portion (assume normal portions when unspecified).
        - {"kind": "body_weight", "body_weight_kg": num}
        - {"kind": "note", "note": str} — anything else worth keeping (soreness, sleep, PRs, plans).

        Examples:
        Input: bench 40kg 3 reps
        Output: {"entries": [{"kind": "workout_set", "exercise": "Bench Press", "weight_kg": 40, "reps": 3, "sets_count": 1}], "clarification": null}
        Input: 3 scrambled eggs and 2 toast with butter, weighed 70.5 this morning
        Output: {"entries": [{"kind": "food", "food_description": "3 scrambled eggs, 2 toast with butter", "calories": 460, "protein_g": 24, "carbs_g": 30, "fat_g": 27}, {"kind": "body_weight", "body_weight_kg": 70.5}], "clarification": null}

        An utterance may produce multiple entries of mixed kinds. If genuinely ambiguous (e.g. a number with no context), still produce best-guess entries AND set clarification to one short question. Ambiguous units: prefer kg — the user is metric.
        """
    }
}
