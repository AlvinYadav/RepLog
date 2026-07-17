import Foundation
import SwiftData

/// Takes a raw utterance, sends it to Gemini, and materializes the parsed
/// entries as SwiftData records. Failures never lose input: the RawLog row
/// stays in the stream with an error badge and can be retried.
@MainActor
enum LogPipeline {
    static func submit(text: String, context: ModelContext) {
        let raw = RawLog(input: text, status: .pending)
        context.insert(raw)
        Task { await process(raw, context: context) }
    }

    static func retry(_ raw: RawLog, context: ModelContext) {
        raw.status = .pending
        raw.errorMessage = nil
        Task { await process(raw, context: context) }
    }

    private static func process(_ raw: RawLog, context: ModelContext) async {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        do {
            let client = GeminiClient(model: GeminiClient.defaultParseModel)
            let json = try await client.generate(
                system: Prompts.logParsing(profile: profile, exercises: exercises),
                user: raw.input,
                jsonOutput: true
            )
            raw.parsedJSON = json // stored before parsing so diagnostics always shows the raw reply
            let result = try EntryParser.parse(json)
            materialize(result, at: raw.timestamp, context: context, exercises: exercises)
            raw.clarification = result.clarification
            raw.status = .parsed
        } catch {
            raw.status = .failed
            raw.errorMessage = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, _): return "Decode: missing key '\(key.stringValue)'"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "Decode at '\(path)': \(ctx.debugDescription)"
        @unknown default: return decodingError.localizedDescription
        }
    }

    private static func materialize(
        _ result: ParseResult,
        at timestamp: Date,
        context: ModelContext,
        exercises: [Exercise]
    ) {
        var known = exercises
        for entry in result.entries {
            switch entry.kind {
            case .workoutSet:
                guard let name = entry.exercise else { continue }
                let exercise = findOrCreateExercise(named: name, in: &known, context: context)
                let count = max(entry.setsCount ?? 1, 1)
                for _ in 0..<count {
                    context.insert(WorkoutSet(
                        exercise: exercise,
                        weightKg: entry.weightKg ?? 0,
                        reps: entry.reps ?? 0,
                        timestamp: timestamp
                    ))
                }
            case .food:
                context.insert(FoodEntry(
                    timestamp: timestamp,
                    foodDescription: entry.foodDescription ?? "Food",
                    calories: entry.calories ?? 0,
                    proteinG: entry.proteinG ?? 0,
                    carbsG: entry.carbsG ?? 0,
                    fatG: entry.fatG ?? 0,
                    source: .text
                ))
            case .bodyWeight:
                if let kg = entry.bodyWeightKg {
                    context.insert(BodyWeightEntry(date: timestamp, weightKg: kg))
                }
            case .note:
                if let note = entry.note, !note.isEmpty {
                    context.insert(RawLog(timestamp: timestamp, input: note, status: .note))
                }
            }
        }
    }

    private static func findOrCreateExercise(
        named name: String,
        in known: inout [Exercise],
        context: ModelContext
    ) -> Exercise {
        let target = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let match = known.first(where: { ex in
            ex.name.lowercased() == target || ex.aliases.contains { $0.lowercased() == target }
        }) {
            return match
        }
        let created = Exercise(name: name)
        context.insert(created)
        known.append(created)
        return created
    }
}
