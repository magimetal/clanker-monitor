<!--THIS IS A GENERATED FILE - DO NOT MODIFY DIRECTLY, FOR MANUAL ADJUSTMENTS UPDATE `AGENTS_CUSTOM.md`-->
# CLANKERMONITOR SOURCE NOTES

## OVERVIEW
All runtime code for SwiftPM executable target lives here: menu-bar SwiftUI shell, shared app state, provider fetchers, settings, and macOS login-item wrapper.

## STRUCTURE
```
Sources/ClankerMonitor/
├── ClankerMonitorApp.swift      # `@main`, MenuBarExtra, high-usage label
├── Providers.swift              # provider enum, normalized result, AppState
├── MenuBarView.swift            # popup shell and refresh loop
├── ProviderRowView.swift        # provider card/progress/error rendering
├── SettingsView.swift           # credentials, visibility toggles, login toggle
├── CodexFetcher.swift           # ChatGPT/Codex usage endpoint
├── CopilotFetcher.swift         # GitHub Copilot quota endpoint
├── ClaudeFetcher.swift          # Anthropic OAuth usage endpoint
├── OpenCodeFetcher.swift        # OpenCode workspace/subscription scrape
└── LaunchAtLoginManager.swift   # SMAppService adapter
```

## WHERE TO LOOK
| Change | File | Constraint |
|--------|------|------------|
| Add provider | `Providers.swift`, new `*Fetcher.swift`, `SettingsView.swift` if credentials needed | Update `Provider.allCases`, display name, SF Symbol, visibility storage. |
| Change polling | `MenuBarView.swift`, `Providers.swift` | Loop is in view `.task`; fetch orchestration is `AppState.refresh()`. |
| Change quota card | `ProviderRowView.swift` | Uses normalized current/weekly percent + reset labels only. |
| Change settings persistence | `SettingsView.swift`, `Providers.swift` | Stored via `@AppStorage`; key names are persisted user defaults. |
| Fix auth lookup | Provider fetcher file | Keep provider-specific credential structs private. |
| Login item behavior | `LaunchAtLoginManager.swift`, README | macOS may reject transient/unsigned bundle contexts. |

## CONVENTIONS
- Fetcher public surface is one top-level async function: `fetchCodex`, `fetchCopilot`, `fetchClaude`, `fetchOpenCode`.
- Fetchers convert all auth/network/parse failures into `ProviderResult(errorMessage:updatedAt:)`.
- Response DTOs and parse helpers remain `private` in owning fetcher file.
- `AppState` is `@MainActor`; mutate `results`, `isRefreshing`, and `@AppStorage` there.
- UI files should not know provider response JSON shapes, endpoint IDs, or credential file formats.
- Error copy is provider-prefixed when it appears inside shared card UI.

## PROVIDER QUIRKS
- Codex supports `OPENAI_API_KEY` and OAuth `tokens.access_token` in `~/.codex/auth.json`.
- Copilot endpoint needs VS Code/Copilot-style headers plus GitHub API version header.
- Claude credentials load Keychain service `Claude Code-credentials` before file fallback.
- Claude utilization may arrive as 0...1 fraction or percent; current code handles both.
- OpenCode requires workspace ID discovery before billing subscription fetch.
- OpenCode parser accepts JSON payloads and server-function text with regex fallback.

## ANTI-PATTERNS
- Do not expose cookies/PATs/tokens in logs, UI debug text, README examples, or generated docs.
- Do not make provider helpers non-private unless another file imports them immediately.
- Do not block main actor with synchronous network/file calls; fetch functions are async.
- Do not add provider-specific branches to `ProviderRowView`; normalize in fetcher/AppState instead.
- Do not swallow errors silently; user needs inline expired/missing credential messages.
