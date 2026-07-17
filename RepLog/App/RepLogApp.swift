import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(AppModel.container)
    }
}
