# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.5.0] - 2026-07-07

### Added
- Claude OAuth token auto-refresh in `ClaudeFetcher`: refreshes near-expiry credentials using the same client ID, endpoints, and response parsing as magi-code, so shared `~/.claude/.credentials.json` (or Keychain `Claude Code-credentials`) stays valid without manual `claude login`.
- Snapshot/re-read race guard around file writeback: aborts the write when another process (magi-code) refreshed concurrently, avoiding stale-token clobbers.
- Atomic credential file writeback with `0600` permissions, preserving existing `scopes`, `rateLimitTier`, and `subscriptionType`.

### Changed
- `fetchClaude()` now parses the full `claudeAiOauth` object (`accessToken`, `refreshToken`, `expiresAt` epoch-ms, `scopes`) instead of only the access token; root `access_token` fallback remains read-only.
- Refresh threshold mirrors magi-code: refresh iff `expiresAt` missing or within 300s of expiry, so the 5-minute UI loop does not refresh on every tick.

## [0.4.0] - 2026-06-17

### Added
- z.ai coding plan usage provider: polls `https://api.z.ai/api/monitor/usage/quota/limit` with a pasted API key (Settings), surfaced as a new provider card (hidden by default). Supports weekly + current token quota slots, plan label, and reset timing.
- z.ai API key field (SecureField) in Settings; visibility toggle in Settings.

### Changed
- `Package.swift` now excludes `Sources/ClankerMonitor/AGENTS.md` from the SwiftPM target to silence the unhandled-file warning while keeping the doc in tree.

## [0.3.1] - 2026-04-25

### Added
- Generated repository agent guidance at the root and ClankerMonitor source tree to document project structure, conventions, commands, and guardrails for coding agents.

### Fixed
- Codex weekly reset label now uses the weekly quota window reset timestamp with weekday and time instead of a time-only daily-style label.
- Copilot quota refresh now bypasses cached responses and displays exact used/entitlement counts so usage changes are visible immediately.

### Changed
- Copilot usage percent now derives from `remaining` and `entitlement`, with more tolerant quota decoding and the stable GitHub API version header.

## [0.3.0] - 2026-04-16

### Added
- Copilot weekly pace indicator: computes burn-rate vs proportional weekly allowance from monthly quota data.
- Copilot reset date display ("resets May 1") from `quota_reset_date_utc` API field.
- Copilot rate-limit (HTTP 429) detection with retry-after hint.
- Copilot unlimited quota handling — shows "(Unlimited)" label when `chat.unlimited` is true.
- Copilot overage count display when `overage_count > 0`.

### Changed
- Copilot fetcher now decodes full `quota_snapshots` payload (`remaining`, `entitlement`, `overage_count`, `overage_permitted`, `unlimited`, `quota_reset_date_utc`) instead of only `percent_remaining`.

## [0.2.0] - 2026-03-16

### Added
- Weekly usage limit tracking for Codex and OpenCode, including reset timing in provider cards.

### Changed
- Refined menu-bar UI with modern glass-style cards, improved hierarchy/spacing, and polished status/error presentation.

## [0.1.0] - 2026-03-09

### Added
- Initial Clanker Monitor release as a macOS menu-bar app for monitoring AI provider usage in one view.
- Provider integrations for OpenAI Codex, GitHub Copilot, Claude, and OpenCode with inline credential/error handling.
- Menu-bar UI with usage progress bars, manual refresh, periodic auto-refresh, provider visibility toggles, and launch-at-login option.
- `build-app.sh` packaging flow that builds, bundles, and signs `ClankerMonitor.app`.
