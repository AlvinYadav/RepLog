import Foundation
import SwiftData

/// Takes a raw utterance, sends it to Gemini, and materializes the parsed
/// entries as SwiftData records. Failures never lose input: the RawLog row
/// stays in the stream with an error badge and can be retried.
@MainActor
enum LogPipeline {
    /// Submits an utterance, timestamped `at` the given moment (defaults to now,
    /// so entries logged while viewing a past day land on that day).
    static func submit(text: String, at timestamp: Date = .now, context: ModelContext) {
        let raw = RawLog(timestamp: timestamp, input: text, status: .pending)
        context.insert(raw)
        Task { await process(raw, context: context) }
    }

    /// Submits a meal photo (with optional caption) through the same pipeline.
    static func submitPhoto(_ jpeg: Data, caption: String?, at timestamp: Date = .now, context: ModelContext) {
        let label = (caption?.isEmpty == false) ? "Meal photo — \(caption!)" : "Meal photo"
        let raw = RawLog(timestamp: timestamp, input: label, status: .pending)
        raw.photoData = jpeg
        context.insert(raw)
        Task { await process(raw, context: context) }
    }

    static func retry(_ raw: RawLog, context: ModelContext) {
        raw.status = .pending
        raw.errorMessage = nil
        Task { await process(raw, context: context) }
    }

    /// Synchronous variant for Siri: waits for the parse and describes the result.
    static func submitAndWait(text: String, context: ModelContext) async -> String {
        let raw = RawLog(input: text, status: .pending)
        context.insert(raw)
        let summaries = await process(raw, context: context)
        switch raw.status {
        case .parsed where !summaries.isEmpty:
            return "Logged: " + summaries.joined(separator: ", ")
        case .parsed:
            return "Logged."
        default:
            return "Saved — I'll parse it when you open RepLog."
        }
    }

    @discardableResult
    private static func process(_ raw: RawLog, context: ModelContext) async -> [String] {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        do {
            // Flash handles vision well and is free-tier; Pro models have no free quota.
            let client = GeminiClient(model: GeminiClient.defaultParseModel)
            let json = try await client.generate(
                system: Prompts.logParsing(profile: profile, exercises: exercises),
                user: raw.input,
                image: raw.photoData.map { .init(mimeType: "image/jpeg", data: $0) },
                jsonOutput: true
            )
            raw.parsedJSON = json // stored before parsing so diagnostics always shows the raw reply
            let result = try EntryParser.parse(json)
            let summaries = materialize(result, at: raw.timestamp, context: context, exercises: exercises, photo: raw.photoData)
            raw.clarification = result.clarification
            raw.status = .parsed
            return summaries
        } catch {
            raw.status = .failed
            raw.errorMessage = Self.describe(error)
            return []
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

    @discardableResult
    private static func materialize(
        _ result: ParseResult,
        at timestamp: Date,
        context: ModelContext,
        exercises: [Exercise],
        photo: Data? = nil
    ) -> [String] {
        var known = exercises
        var photoToAttach = photo
        var summaries: [String] = []
        for entry in result.entries {
            switch entry.kind {
            case .workoutSet:
                guard let name = entry.exercise else { continue }
                let exercise = findOrCreateExercise(named: name, in: &known, context: context)
                if exercise.muscleGroups.isEmpty, let groups = entry.muscleGroups, !groups.isEmpty {
                    exercise.muscleGroups = groups.map { $0.lowercased() }
                }
                let count = max(entry.setsCount ?? 1, 1)
                for _ in 0..<count {
                    context.insert(WorkoutSet(
                        exercise: exercise,
                        weightKg: entry.weightKg ?? 0,
                        reps: entry.reps ?? 0,
                        timestamp: timestamp
                    ))
                }
                let sets = count > 1 ? "\(count)×" : ""
                summaries.append("\(exercise.name) \(sets)\((entry.weightKg ?? 0).formatted()) kg × \(entry.reps ?? 0)")
            case .food:
                context.insert(FoodEntry(
                    timestamp: timestamp,
                    foodDescription: entry.foodDescription ?? "Food",
                    calories: entry.calories ?? 0,
                    proteinG: entry.proteinG ?? 0,
                    carbsG: entry.carbsG ?? 0,
                    fatG: entry.fatG ?? 0,
                    fiberG: entry.fiberG ?? 0,
                    source: photoToAttach == nil ? .text : .photo,
                    photoData: photoToAttach // first food entry keeps the photo
                ))
                photoToAttach = nil
                summaries.append("\(entry.foodDescription ?? "food"), \(entry.calories ?? 0) calories")
            case .bodyWeight:
                if let kg = entry.bodyWeightKg {
                    context.insert(BodyWeightEntry(date: timestamp, weightKg: kg))
                    summaries.append("weight \(kg.formatted()) kg")
                }
            case .supplement:
                if let name = entry.supplementName, !name.isEmpty {
                    context.insert(SupplementEntry(name: name, amount: entry.supplementAmount, timestamp: timestamp))
                    summaries.append(name.lowercased())
                }
            case .water:
                let ml = entry.waterMl ?? 250
                context.insert(WaterEntry(timestamp: timestamp, milliliters: ml))
                summaries.append("\(ml) ml water")
            case .note:
                if let note = entry.note, !note.isEmpty {
                    context.insert(RawLog(timestamp: timestamp, input: note, status: .note))
                    summaries.append("note")
                }
            }
        }
        return summaries
    }

    /// Backfills muscle groups for exercises that were created without them
    /// (e.g. typed during onboarding). Fires one silent background call.
    private static var classifyAttempted = false
    static func classifyExercisesIfNeeded(context: ModelContext) {
        guard !classifyAttempted else { return }
        let unclassified = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? [])
            .filter { $0.muscleGroups.isEmpty }
        guard !unclassified.isEmpty else { return }
        classifyAttempted = true
        Task {
            do {
                let client = GeminiClient(model: GeminiClient.defaultParseModel)
                let json = try await client.generate(
                    system: """
                    Map each gym exercise to its primary muscle groups, chosen from:
                    chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core.
                    Reply ONLY JSON, e.g. {"Bench Press": ["chest", "triceps"]}
                    """,
                    user: unclassified.map(\.name).joined(separator: ", "),
                    jsonOutput: true
                )
                let start = json.firstIndex(of: "{").map { String(json[$0...]) } ?? json
                let mapping = try JSONDecoder().decode([String: [String]].self, from: Data(start.utf8))
                for exercise in unclassified {
                    if let groups = mapping.first(where: { $0.key.lowercased() == exercise.name.lowercased() })?.value {
                        exercise.muscleGroups = groups.map { $0.lowercased() }
                    }
                }
            } catch {
                classifyAttempted = false // retry on next launch
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
