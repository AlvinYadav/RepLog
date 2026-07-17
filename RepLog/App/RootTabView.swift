import SwiftUI

struct RootTabView: View {
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        TabView {
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: .constant(!didOnboard)) {
            OnboardingView()
        }
    }
}

#Preview {
    RootTabView()
}
