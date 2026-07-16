import Foundation

/// One structured entry extracted from a user utterance.
/// A single utterance can yield several ("bench 50 for 8 then 7, and a protein shake").
struct ParsedEntry: Decodable {
    enum Kind: String, Decodable {
        case workoutSet = "workout_set"
        case food
        case bodyWeight = "body_weight"
        case note
    }

    let kind: Kind
    let exercise: String?
    let weightKg: Double?
    let reps: Int?
    let setsCount: Int?
    let foodDescription: String?
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let bodyWeightKg: Double?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case kind, exercise, reps, note, calories
        case weightKg = "weight_kg"
        case setsCount = "sets_count"
        case foodDescription = "food_description"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case bodyWeightKg = "body_weight_kg"
    }
}

struct ParseResult: Decodable {
    let entries: [ParsedEntry]
    let clarification: String?
}

enum EntryParser {
    /// Gemini responseSchema (OpenAPI subset) matching ParseResult.
    static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "entries": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "kind": ["type": "STRING", "enum": ["workout_set", "food", "body_weight", "note"]],
                        "exercise": ["type": "STRING", "nullable": true],
                        "weight_kg": ["type": "NUMBER", "nullable": true],
                        "reps": ["type": "INTEGER", "nullable": true],
                        "sets_count": ["type": "INTEGER", "nullable": true],
                        "food_description": ["type": "STRING", "nullable": true],
                        "calories": ["type": "INTEGER", "nullable": true],
                        "protein_g": ["type": "NUMBER", "nullable": true],
                        "carbs_g": ["type": "NUMBER", "nullable": true],
                        "fat_g": ["type": "NUMBER", "nullable": true],
                        "body_weight_kg": ["type": "NUMBER", "nullable": true],
                        "note": ["type": "STRING", "nullable": true]
                    ] as [String: Any],
                    "required": ["kind"]
                ] as [String: Any]
            ] as [String: Any],
            "clarification": ["type": "STRING", "nullable": true]
        ] as [String: Any],
        "required": ["entries"]
    ]

    static func parse(_ jsonText: String) throws -> ParseResult {
        try JSONDecoder().decode(ParseResult.self, from: Data(jsonText.utf8))
    }
}
