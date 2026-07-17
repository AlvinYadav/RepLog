import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            UserProfile.self,
            Exercise.self,
            WorkoutSet.self,
            FoodEntry.self,
            BodyWeightEntry.self,
            SupplementEntry.self,
            WeeklyReport.self,
            RawLog.self
        ])
    }
}
