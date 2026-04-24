<!--THIS IS A GENERATED FILE - DO NOT MODIFY DIRECTLY, FOR MANUAL ADJUSTMENTS UPDATE `AGENTS_CUSTOM.md`-->
# PROJECT KNOWLEDGE BASE

**Generated:** 2026-04-24
**Commit:** 9895293
**Branch:** main

## OVERVIEW
Clanker Monitor is macOS 14+ menu-bar SwiftUI app for live AI quota/status monitoring. Single SwiftPM executable target, no package dependencies, app bundle built by shell script.

## STRUCTURE
```
./
├── Package.swift                  # SwiftPM executable target: ClankerMonitor
├── Sources/ClankerMonitor/        # SwiftUI app, provider fetchers, settings, login item glue
├── build-app.sh                   # release build + .app bundle + ad-hoc signing
├── ClankerMonitor.app/            # generated app bundle; ignored by git pattern *.app/
├── clanker-monitor.icns           # bundle icon copied into app resources
├── clanker-monitor.png            # README/runtime fallback logo
├── README.md                      # user-facing setup, provider auth, release flow
└── CHANGELOG.md                   # manual release notes source
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| App entry/menu-bar label | `Sources/ClankerMonitor/ClankerMonitorApp.swift` | `MenuBarExtra`; label flips to `⚠️🤖` at >=90% usage. |
| Shared provider state | `Sources/ClankerMonitor/Providers.swift` | `@MainActor AppState.shared`; refresh fan-out lives here. |
| Popup layout/refresh loop | `Sources/ClankerMonitor/MenuBarView.swift` | 5-minute `.task` loop; inline Settings toggle. |
| Provider row UI | `Sources/ClankerMonitor/ProviderRowView.swift` | Cards, progress bars, error callouts, weekly section. |
| Settings | `Sources/ClankerMonitor/SettingsView.swift` | Copilot PAT, OpenCode cookie, provider visibility, login toggle. |
| Codex quota | `Sources/ClankerMonitor/CodexFetcher.swift` | Reads `~/.codex/auth.json`; calls ChatGPT usage endpoint. |
| Copilot quota | `Sources/ClankerMonitor/CopilotFetcher.swift` | GitHub PAT; calls internal Copilot user endpoint. |
| Claude quota | `Sources/ClankerMonitor/ClaudeFetcher.swift` | Keychain first, then `~/.claude/.credentials.json`. |
| OpenCode quota | `Sources/ClankerMonitor/OpenCodeFetcher.swift` | Cookie-based `_server` fetch + resilient text/JSON parsing. |
| Launch at login | `Sources/ClankerMonitor/LaunchAtLoginManager.swift` | `SMAppService.mainApp`; failures logged only. |
| App packaging | `build-app.sh` | Generates `Info.plist`, copies icon, signs bundle. |

## CODE MAP
| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `ClankerMonitorApp` | `App` | `ClankerMonitorApp.swift` | Menu-bar scene root. |
| `AppState` | `ObservableObject` | `Providers.swift` | Provider results, credentials storage, refresh orchestration. |
| `Provider` | `enum` | `Providers.swift` | Provider identity/display metadata. |
| `ProviderResult` | `struct` | `Providers.swift` | Normalized quota/error payload for UI. |
| `MenuBarView` | `View` | `MenuBarView.swift` | Header, provider list/settings switcher, footer. |
| `ProviderRowView` | `View` | `ProviderRowView.swift` | Provider card rendering. |
| `SettingsView` | `View` | `SettingsView.swift` | Credential and visibility controls. |
| `fetchCodex` | `async func` | `CodexFetcher.swift` | Codex auth file + usage fetch. |
| `fetchCopilot` | `async func` | `CopilotFetcher.swift` | Copilot PAT + quota fetch. |
| `fetchClaude` | `async func` | `ClaudeFetcher.swift` | Claude credentials + OAuth usage fetch. |
| `fetchOpenCode` | `async func` | `OpenCodeFetcher.swift` | OpenCode workspace/subscription scrape. |
| `LaunchAtLoginManager` | `struct` | `LaunchAtLoginManager.swift` | Login item registration wrapper. |

## CONVENTIONS
- One executable target only: `Package.swift` target path is `Sources/ClankerMonitor`.
- Provider fetchers expose one top-level `fetchX()` async function returning `ProviderResult`; helpers stay `private` in same file.
- UI consumes only normalized `ProviderResult`; provider-specific response structs stay inside fetcher files.
- Credentials: Codex/Claude read local tool auth; Copilot/OpenCode stored through `@AppStorage` from Settings.
- User-facing provider failures return inline `ProviderResult(errorMessage:updatedAt:)`; no throwing across UI boundary.
- Percent values entering UI are clamped/rendered by `ProviderRowView`; fetchers still sanitize obvious API shape variance.
- Generated artifacts `.build/`, `.swiftpm/`, `*.app/`, `*.xcodeproj/`, release zips stay out of git.

## ANTI-PATTERNS (THIS PROJECT)
- Do not commit secrets, PATs, cookies, auth JSON, Keychain dumps, or provider response payloads.
- Do not move provider credentials into source constants or sample defaults.
- Do not overwrite `ClankerMonitor.app` assumptions without updating `build-app.sh` and README install notes.
- Do not add external dependencies unless `Package.swift`, README requirements, and release flow are updated together.
- Do not fetch hidden providers from UI loops; `AppState.refresh()` currently skips Claude when hidden but always fetches Codex/Copilot/OpenCode.
- Do not treat OpenCode `_server` IDs as stable public API; parsing/network errors must surface inline.

## COMMANDS
```bash
swift run ClankerMonitor
swift build
./build-app.sh
open ClankerMonitor.app
zip -r "ClankerMonitor-vX.Y.Z-macos.zip" "ClankerMonitor.app"
gh release create "vX.Y.Z" "ClankerMonitor-vX.Y.Z-macos.zip" --title "vX.Y.Z" --notes-file CHANGELOG.md
```

## NOTES
- macOS 14 minimum comes from both README and `Package.swift` platform setting.
- `LSUIElement` is produced by `build-app.sh`; source run and bundled app may differ in login-item behavior.
- Runtime logo lookup tries bundled `.icns`, then bundled `.png`; keep asset filenames or update `MenuBarView` plus packaging.
- No test target exists. Verification today is `swift build` or manual app run.
- README is authoritative for provider auth paths, launch-at-login caveats, and manual release sequence.
