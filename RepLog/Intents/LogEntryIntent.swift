import AppIntents
import SwiftData

/// "Hey Siri, log in RepLog" → Siri asks what → utterance goes through the
/// same Gemini pipeline, and Siri reads back what was logged.
struct LogEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Log entry"
    static let description = IntentDescription(
        "Log a workout set, food, body weight, water, or supplement in RepLog."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Entry", requestValueDialog: "What do you want to log?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await LogPipeline.submitAndWait(text: text, context: AppModel.container.mainContext)
        try? AppModel.container.mainContext.save()
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

struct RepLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogEntryIntent(),
            phrases: [
                "Log in \(.applicationName)",
                "Log workout in \(.applicationName)",
                "Log food in \(.applicationName)"
            ],
            shortTitle: "Log",
            systemImageName: "mic.fill"
        )
    }
}
