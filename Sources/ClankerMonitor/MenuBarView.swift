import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if showSettings {
                Divider().opacity(0.4)

                SettingsView {
                    showSettings = false
                }
                .environmentObject(appState)
            } else {
                VStack(spacing: 10) {
                    if appState.visibleProviders.isEmpty {
                        Text("No providers are visible. Enable at least one in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.06))
                            )
                    } else {
                        ForEach(appState.visibleProviders) { provider in
                            ProviderRowView(provider: provider)
                        }
                    }
                }

                footer
            }

            Divider().opacity(0.4)

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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: showSettings ? 360 : 332)
        .background(panelBackground)
        .task {
            while !Task.isCancelled {
                await appState.refresh()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            headerLogo
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Clanker Monitor")
                    .font(.headline.weight(.semibold))
                Text("Live quota monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.1))
                )
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(updatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(appState.visibleProviders.count) provider\(appState.visibleProviders.count == 1 ? "" : "s") visible")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Refresh Now") {
                Task { await appState.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var updatedLabel: String {
        guard let latest = appState.results.values.compactMap({ $0.updatedAt }).max() else {
            return "Updated —"
        }
        return "Updated \(RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date()))"
    }
}
