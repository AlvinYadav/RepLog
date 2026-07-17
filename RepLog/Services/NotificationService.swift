import Foundation
import UserNotifications

/// Local water reminders: three gentle nudges a day, opt-in from Settings.
enum NotificationService {
    private static let waterIdentifiers = ["water-11", "water-15", "water-19"]

    static func enableWaterReminders() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let reminders: [(id: String, hour: Int, body: String)] = [
            ("water-11", 11, "Morning water check — a glass now sets up the day."),
            ("water-15", 15, "Halfway there? Top up your water."),
            ("water-19", 19, "Evening water check — close the gap before dinner.")
        ]
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "RepLog"
            content.body = reminder.body
            content.sound = nil
            var date = DateComponents()
            date.hour = reminder.hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            )
        }
        return true
    }

    static func disableWaterReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: waterIdentifiers)
    }
}
