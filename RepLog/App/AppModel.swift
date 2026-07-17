import Foundation
import SwiftData

/// Single shared ModelContainer used by the app UI and App Intents (Siri).
@MainActor
enum AppModel {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: UserProfile.self, Exercise.self, WorkoutSet.self, FoodEntry.self,
                BodyWeightEntry.self, SupplementEntry.self, WaterEntry.self,
                WeeklyReport.self, RawLog.self
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
