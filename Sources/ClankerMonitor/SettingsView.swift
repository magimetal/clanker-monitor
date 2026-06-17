import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var openAtLogin = LaunchAtLoginManager.isEnabled
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline)
                Text("Credentials and provider visibility")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            credentialSection
            visibilitySection
            launchSection

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Save & Refresh") {
                    onSave()
                    Task { await appState.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerVisibilityBinding(for provider: Provider) -> Binding<Bool> {
        Binding(
            get: { appState.isProviderVisible(provider) },
            set: { appState.setProviderVisibility(provider, isVisible: $0) })
    }

    private var credentialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credentials")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("GitHub Copilot")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                SecureField("GitHub PAT", text: $appState.copilotPAT)
                    .textFieldStyle(.roundedBorder)

                Text("Generate at github.com/settings/tokens (read:user + copilot scope)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenCode Zen")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    if appState.opencodeCookie.isEmpty {
                        Text("Paste Cookie header value from browser DevTools")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }

                    TextEditor(text: $appState.opencodeCookie)
                        .font(.caption)
                        .frame(height: 90)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("z.ai API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                SecureField("Paste z.ai API token", text: $appState.zaiAPIKey)
                    .textFieldStyle(.roundedBorder)

                Text("Get from z.ai console. Stored locally.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Providers")
                .font(.subheadline.weight(.semibold))

            ForEach(Provider.allCases) { provider in
                Toggle(provider.displayName, isOn: providerVisibilityBinding(for: provider))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, isEnabled in
                    LaunchAtLoginManager.setEnabled(isEnabled)
                    openAtLogin = LaunchAtLoginManager.isEnabled
                }

            Text("Automatically launch Clanker Monitor when you sign in.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }
}
