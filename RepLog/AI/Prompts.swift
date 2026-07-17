import Foundation

enum Prompts {
    static func logParsing(profile: UserProfile?, exercises: [Exercise], recentFoods: [FoodEntry] = []) -> String {
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
        \(recentFoodsBlock(recentFoods))

        Respond with ONLY a JSON object, no markdown, exactly this shape:
        {"entries": [ ... ], "clarification": null}

        Entry kinds and their REQUIRED fields:
        - {"kind": "workout_set", "exercise": str, "weight_kg": num, "reps": int, "sets_count": int, "muscle_groups": [str]} — reps = repetitions in one set. "3 sets of 8 at 50" → ONE entry with reps=8, sets_count=3. "50 for 8 then 7" → two entries. Bodyweight movements → weight_kg=0. Convert lbs to kg (1 lb = 0.4536 kg). Exactly one entry per distinct set mentioned — never duplicate. muscle_groups = the exercise's primary groups from: chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core.
        - {"kind": "food", "food_description": str, "calories": int, "protein_g": num, "carbs_g": num, "fat_g": num, "fiber_g": num} — short itemized description; ESTIMATE macros realistically for the portion (assume normal portions when unspecified).
        - {"kind": "body_weight", "body_weight_kg": num}
        - {"kind": "water", "water_ml": int} — plain water/hydration. "a glass of water" → 250, "a bottle" → 500.
        - {"kind": "supplement", "supplement_name": str, "amount": str|null} — creatine, vitamins, pre-workout etc. Convert doses: one creatine scoop = 3 g, so "3 scoops of creatine" → amount "9 g". Omit amount when unstated. A protein shake with meaningful calories is kind=food instead.
        - {"kind": "note", "note": str} — anything else worth keeping (soreness, sleep, PRs, plans).

        Examples:
        Input: bench 40kg 3 reps
        Output: {"entries": [{"kind": "workout_set", "exercise": "Bench Press", "weight_kg": 40, "reps": 3, "sets_count": 1, "muscle_groups": ["chest", "triceps"]}], "clarification": null}
        Input: took 3 scoops of creatine
        Output: {"entries": [{"kind": "supplement", "supplement_name": "Creatine", "amount": "9 g"}], "clarification": null}
        Input: 3 scrambled eggs and 2 toast with butter, weighed 70.5 this morning
        Output: {"entries": [{"kind": "food", "food_description": "3 scrambled eggs, 2 toast with butter", "calories": 460, "protein_g": 24, "carbs_g": 30, "fat_g": 27, "fiber_g": 3}, {"kind": "body_weight", "body_weight_kg": 70.5}], "clarification": null}
        Input: shake with milk, one scoop protein powder and a tablespoon of peanut butter
        Output: {"entries": [{"kind": "food", "food_description": "Shake: 250ml milk, 1 scoop whey, 1 tbsp peanut butter", "calories": 370, "protein_g": 36, "carbs_g": 18, "fat_g": 16, "fiber_g": 1}], "clarification": null}
        Input: drank a glass of water
        Output: {"entries": [{"kind": "water", "water_ml": 250}], "clarification": null}

        If an image is attached, it is a photo of the user's food: identify each item and portion size from the image (plus any caption), then produce food entries with realistic macro estimates. Prefer one combined entry per plate/meal.

        An utterance may produce multiple entries of mixed kinds. If genuinely ambiguous (e.g. a number with no context), still produce best-guess entries AND set clarification to one short question. Ambiguous units: prefer kg — the user is metric.
        """
    }

    private static func recentFoodsBlock(_ foods: [FoodEntry]) -> String {
        guard !foods.isEmpty else { return "" }
        let lines = foods.map { food in
            "- \(food.foodDescription): \(food.calories) kcal, \(Int(food.proteinG))P, \(Int(food.carbsG))C, \(Int(food.fatG))F, \(Int(food.fiberG))Fb"
        }.joined(separator: "\n")
        return """

        Foods this user has logged before, with THEIR established macros. When the user mentions one of these again (any phrasing that clearly means the same item, e.g. "had a yoga bar again"), REUSE these exact macros and description instead of estimating fresh ones:
        \(lines)
        """
    }
}
