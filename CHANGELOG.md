# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
