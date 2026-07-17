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

    // Models are inconsistent with JSON number types (3 vs 3.0 vs "3"),
    // so numeric fields are decoded leniently instead of trusting the schema.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        exercise = try? c.decodeIfPresent(String.self, forKey: .exercise)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        foodDescription = try? c.decodeIfPresent(String.self, forKey: .foodDescription)
        weightKg = Self.flexibleDouble(c, .weightKg)
        reps = Self.flexibleInt(c, .reps)
        setsCount = Self.flexibleInt(c, .setsCount)
        calories = Self.flexibleInt(c, .calories)
        proteinG = Self.flexibleDouble(c, .proteinG)
        carbsG = Self.flexibleDouble(c, .carbsG)
        fatG = Self.flexibleDouble(c, .fatG)
        bodyWeightKg = Self.flexibleDouble(c, .bodyWeightKg)
    }

    private static func flexibleDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    private static func flexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0.rounded()) } }
        return nil
    }
}

struct ParseResult: Decodable {
    let entries: [ParsedEntry]
    let clarification: String?
}

enum EntryParser {
    /// Decodes the model's reply, tolerating markdown fences or stray prose
    /// around the JSON object.
    static func parse(_ jsonText: String) throws -> ParseResult {
        let trimmed: Substring
        if let start = jsonText.firstIndex(of: "{"), let end = jsonText.lastIndex(of: "}"), start < end {
            trimmed = jsonText[start...end]
        } else {
            trimmed = Substring(jsonText)
        }
        return try JSONDecoder().decode(ParseResult.self, from: Data(trimmed.utf8))
    }
}
