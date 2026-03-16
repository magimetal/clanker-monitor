# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
