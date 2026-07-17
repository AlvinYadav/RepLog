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
        // Unknown kind → keep the entry as a note rather than failing the parse.
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .note
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
    /// Decodes the model's reply, tolerating markdown fences, stray prose
    /// around the JSON object, and truncated output (unclosed braces).
    static func parse(_ jsonText: String) throws -> ParseResult {
        let candidate: String
        if let start = jsonText.firstIndex(of: "{") {
            candidate = String(jsonText[start...])
        } else {
            candidate = jsonText
        }
        do {
            return try JSONDecoder().decode(ParseResult.self, from: Data(candidate.utf8))
        } catch {
            let repaired = repairTruncation(candidate)
            guard repaired != candidate else { throw error }
            return try JSONDecoder().decode(ParseResult.self, from: Data(repaired.utf8))
        }
    }

    /// Closes any string/array/object left open by a cut-off reply.
    private static func repairTruncation(_ text: String) -> String {
        // Trim trailing junk after the JSON (e.g. closing markdown fence).
        var s = text
        if let lastBrace = s.lastIndex(where: { $0 == "}" || $0 == "]" || $0 == "\"" }) {
            let tail = s[s.index(after: lastBrace)...]
            if !tail.contains("{") { s = String(s[...lastBrace]) }
        }

        var stack: [Character] = []
        var inString = false
        var escaped = false
        for ch in s {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            switch ch {
            case "{", "[": stack.append(ch)
            case "}": if stack.last == "{" { stack.removeLast() }
            case "]": if stack.last == "[" { stack.removeLast() }
            default: break
            }
        }

        guard inString || !stack.isEmpty else { return s }
        var repaired = s
        if inString { repaired.append("\"") }
        while let last = repaired.last, last == " " || last == "\n" || last == "\t" {
            repaired.removeLast()
        }
        // Make the dangling tail a complete member: `"key":` → null value,
        // trailing comma → dropped, bare `"key"` → given a null value.
        if repaired.hasSuffix(":") {
            repaired.append(" null")
        } else if repaired.hasSuffix(",") {
            repaired.removeLast()
        } else if repaired.hasSuffix("\""), stack.last == "{", isDanglingKey(repaired) {
            repaired.append(": null")
        }
        for opener in stack.reversed() {
            repaired.append(opener == "{" ? "}" : "]")
        }
        return repaired
    }

    /// True when the string's trailing quoted token is an object key (preceded
    /// by `{` or `,`) rather than a value (preceded by `:`).
    private static func isDanglingKey(_ s: String) -> Bool {
        guard s.hasSuffix("\"") else { return false }
        var index = s.index(before: s.endIndex)
        // Find the matching opening quote (no escape handling needed for keys).
        while index > s.startIndex {
            index = s.index(before: index)
            if s[index] == "\"" { break }
        }
        while index > s.startIndex {
            index = s.index(before: index)
            let ch = s[index]
            if ch == " " || ch == "\n" || ch == "\t" { continue }
            return ch == "{" || ch == ","
        }
        return false
    }
}
