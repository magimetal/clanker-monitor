import SwiftUI

@main
struct ClankerMonitorApp: App {
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Text(menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: String {
        let hasHighUsage = appState.results.values.contains {
            ($0.usedPercent ?? 0) >= 90
        }
        return hasHighUsage ? "⚠️🤖" : "🤖"
    }
}
