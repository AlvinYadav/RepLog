import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            LogView()
                .tabItem { Label("Log", systemImage: "mic.fill") }
            TodayView()
                .tabItem { Label("Today", systemImage: "chart.pie.fill") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    RootTabView()
}
