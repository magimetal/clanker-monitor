import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if showSettings {
                Divider()

                SettingsView {
                    showSettings = false
                }
                .environmentObject(appState)
            } else {
                if appState.visibleProviders.isEmpty {
                    Text("No providers are visible. Enable at least one in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(appState.visibleProviders) { provider in
                            ProviderRowView(provider: provider)
                        }
                    }
                }

                footer
            }

            Divider()

            HStack(spacing: 8) {
                Button(showSettings ? "Back" : "Settings") {
                    showSettings.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: showSettings ? 340 : 300)
        .task {
            while !Task.isCancelled {
                await appState.refresh()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            headerLogo
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clanker Monitor")
                    .font(.headline)
                Text("Live quota monitor")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if appState.isRefreshing {
                Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var headerLogo: Image {
        if let logo = loadHeaderLogoImage() {
            return Image(nsImage: logo)
        }
        return Image(systemName: "bolt.circle")
    }

    private func loadHeaderLogoImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "clanker-monitor", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }

        if let url = Bundle.main.url(forResource: "clanker-monitor", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }

        return nil
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(updatedLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Refresh Now") {
                Task { await appState.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private var updatedLabel: String {
        guard let latest = appState.results.values.compactMap({ $0.updatedAt }).max() else {
            return "Updated —"
        }
        return "Updated \(RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date()))"
    }
}
