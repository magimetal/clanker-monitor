# Clanker Monitor

![Clanker Monitor](./clanker-monitor.png)

Clanker Monitor is a lightweight macOS menu-bar app that shows live usage/quota status for multiple AI tools in one place.

- **Platform:** macOS 14+
- **Stack:** SwiftUI + Swift Package Manager
- **App style:** menu-bar only (`LSUIElement`)

---

## What it does

Clanker Monitor polls provider APIs and shows:

- current usage percentage
- plan label (when available)
- reset timing (when available)
- clear inline errors when credentials are missing/expired

Current providers:

- OpenAI Codex
- GitHub Copilot
- Claude
- OpenCode

---

## Feature overview

- Menu-bar popup with compact provider cards and progress bars
- Dynamic menu-bar label: `🤖` normally, `⚠️🤖` when any provider reaches `>= 90%`
- Manual **Refresh Now** button
- Automatic refresh loop (every 5 minutes from the menu-bar scene task)
- “Updated … ago” status timestamp
- Provider visibility toggles (hide/show each provider)
- Inline settings UI (no separate settings window)
- Custom app icon and bundled resources for `.app` packaging
- Launch-at-login toggle (with macOS login items caveats; see below)

---

## Provider auth and data sources

| Provider | How auth works | Notes |
|---|---|---|
| **Codex** | Reads `~/.codex/auth.json` | Supports API-key and OAuth token shapes. If invalid/expired, app prompts to run `codex` login again. |
| **Copilot** | Manual GitHub PAT in Settings (`Authorization: token <PAT>`) | Quota is fetched from `https://api.github.com/copilot_internal/user`; missing/expired PAT is surfaced inline. |
| **Claude** | **Keychain-first**, file fallback | First tries macOS Keychain item (`Claude Code-credentials`), then falls back to `~/.claude/.credentials.json`. |
| **OpenCode** | Manual cookie header in Settings | Cookie can expire; refresh by re-copying from browser DevTools and saving again. |

---

## Requirements

- macOS 14 or newer
- Swift 5.9+ toolchain (`swift` CLI available)

---

## Build and run

### Run from source

```bash
swift run ClankerMonitor
```

### Build only

```bash
swift build
```

### Build `.app` bundle

```bash
./build-app.sh
open ClankerMonitor.app
```

`build-app.sh` does the following:

- builds release binary
- creates `ClankerMonitor.app` bundle structure
- writes `Info.plist` (`LSUIElement`, minimum macOS version, bundle metadata)
- copies `clanker-monitor.icns` into app resources
- ad-hoc signs the app bundle

---

## Install and use

1. Build the app bundle (`./build-app.sh`).
2. Open it once (`open ClankerMonitor.app`).
3. Click the menu-bar icon to open the panel (`🤖` normally, `⚠️🤖` when any provider is at or above 90% usage).
4. Open **Settings** and configure credentials:
   - Copilot PAT
   - OpenCode cookie header
5. Toggle provider visibility as needed.
6. Click **Save & Refresh**.

Tip: Moving the app bundle to `/Applications` is recommended for normal macOS behavior and launch-at-login registration.

---

## Settings and options

Inside the inline Settings panel:

- **Credentials**
  - Copilot PAT (`SecureField`)
  - OpenCode cookie (`TextEditor`)
- **Visible Providers**
  - Per-provider toggles for Codex, Copilot, Claude, OpenCode
- **Open at Login**
  - Uses `SMAppService.mainApp` registration

### Open at Login caveat

Launch-at-login can fail silently if macOS rejects registration context (for example, unsigned/transient locations or first-run permission state). If it does not stick:

- move app to `/Applications`
- relaunch app and toggle again
- check macOS Login Items settings

---

## App icon and assets

- README image: `clanker-monitor.png` (this file)
- App bundle icon: `clanker-monitor.icns`
- Runtime header logo lookup: tries bundled `.icns`, then bundled `.png`

If you replace branding assets, keep the same filenames or update references in build/runtime code.

---

## Troubleshooting

### Claude credentials not found

What happens: Claude row shows credential/login error.

Where it reads from:
1. Keychain generic password service: `Claude Code-credentials`
2. Fallback file: `~/.claude/.credentials.json`

Fix:

- run `claude login`
- relaunch and refresh

### OpenCode keeps failing / signed out

What happens: OpenCode row shows invalid/expired cookie or parse errors.

Fix:

- sign into OpenCode in browser
- copy a fresh `Cookie` header value from DevTools
- paste into Settings and **Save & Refresh**

### Copilot token invalid or missing

What happens: Copilot row shows token error.

Fix:

- create/update GitHub PAT with required scopes
- paste into Settings and refresh

### Codex auth.json error

What happens: Codex row shows auth file invalid/missing.

Fix:

- re-authenticate via `codex`
- verify `~/.codex/auth.json` exists and is valid JSON

---

## Current limitations / notes

- No automatic token/cookie renewal flows (manual re-auth is required when expired)
- OpenCode relies on pasted browser cookie, so session expiry is expected
- Launch-at-login behavior depends on macOS login-item rules and app install location
- Network/API errors are surfaced in-provider instead of hidden

---

## Development notes

- Single executable SwiftPM package (`Package.swift`)
- Source layout under `Sources/ClankerMonitor` (10 Swift source files):
  - `ClankerMonitorApp.swift`
  - `MenuBarView.swift`
  - `ProviderRowView.swift`
  - `Providers.swift`
  - `CodexFetcher.swift`
  - `CopilotFetcher.swift`
  - `ClaudeFetcher.swift`
  - `OpenCodeFetcher.swift`
  - `SettingsView.swift`
  - `LaunchAtLoginManager.swift`
- No external package dependencies
