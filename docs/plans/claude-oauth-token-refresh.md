# Implementation Plan: Claude OAuth Token Refresh

## Objective
Add Claude OAuth token refresh to `ClankerMonitor` that mirrors magi-code credential behavior closely enough to avoid corrupting shared Claude Code credentials.

## Status
- Observed: `fetchClaude()` currently loads Claude credentials, calls Claude usage API, and reports 401 as expired token.
- Observed: `Providers.swift` calls `fetchClaude()` only when Claude provider visible.
- Observed: `MenuBarView.swift` refresh loop runs every 5 minutes.
- Inferred: No changes needed outside `Sources/ClankerMonitor/ClaudeFetcher.swift` because `fetchClaude()` signature and `ProviderResult` contract can stay unchanged.
- Unknown: Exact live Claude refresh response shape beyond known magi-code-compatible variants.

## Documentation Decision
- PRD: skipped. Small additive auth maintenance behavior, no new user-facing surface.
- ADR: skipped. No new dependency, storage format, public contract, or architecture boundary. Mirrors existing magi-code behavior.
- RFC: skipped. Technical approach predetermined by magi-code source of truth.

## Implementation Sequence

### 1. Extend credential model and source tracking
- What: Replace current `ClaudeCredentials` with credential model that carries refresh metadata and source.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`, private credential types near existing `ClaudeCredentials`.
- Add private types:
  - `ClaudeCredentialSource` enum: `.keychain`, `.file(URL)`.
  - `ClaudeCredentials` struct fields:
    - `accessToken: String`
    - `refreshToken: String?`
    - `expiresAt: Int64?` epoch milliseconds
    - `scopes: [Any]?` only if model retains parsed OAuth object; preferred implementation is preserve scopes from raw JSON inside writeback/snapshot helpers rather than long-lived model
    - `rateLimitTier: String?`
    - `subscriptionType: String?`
    - `source: ClaudeCredentialSource`
    - `rawData: Data` or stable snapshot payload for race comparison
  - `ClaudeAuthSnapshot` struct: comparable snapshot of source + access token + refresh token + expiresAt + normalized raw credential content needed for race guard.
- Why: Refresh decision and safe writeback require knowing refresh token, expiry, source, and snapshot used before network call.
- Acceptance criteria:
  - Keychain still tried first with service `Claude Code-credentials`.
  - File fallback still reads `~/.claude/.credentials.json`.
  - Existing root `access_token` fallback still works read-only.
- Guardrails:
  - Do not log or print token values.
  - Do not remove current `rateLimitTier` / `subscriptionType` plan labeling behavior.
  - Do not make `fetchClaude()` throw.
- Verification: `swift build`.

### 2. Parse magi-code credential shape fully
- What: Update `parseClaudeCredentials(from:)` to read magi-code OAuth fields.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`, existing `parseClaudeCredentials(from:)`.
- Behavior:
  - Preferred JSON path: `claudeAiOauth` object.
  - Required for auth: non-empty `accessToken`.
  - Optional: `refreshToken`, `expiresAt`, `scopes`, `rateLimitTier`, `subscriptionType`.
  - Preserve fallback root `access_token` as read-only credentials with no refresh token / expiry.
  - Accept `expiresAt` as epoch milliseconds number; tolerate integer/double JSON number by converting to `Int64`.
- Why: Mirrors magi-code storage shape and enables threshold refresh.
- Acceptance criteria:
  - Missing `refreshToken` does not fail credential load.
  - Missing `expiresAt` with refresh token is treated as refresh-needed later.
  - Existing credentials without refresh metadata still reach usage call.
- Guardrails:
  - Preserve `scopes` exactly enough to write back existing array unchanged.
  - Do not require `rateLimitTier` / `subscriptionType`.
- Verification: `swift build`; manual with current local Claude credentials if available.

### 3. Add refresh decision before usage API call
- What: Call refresh helper after load and before usage request.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`, top of `fetchClaude()` after `loadClaudeCredentials()` succeeds.
- Add private function:
  - `refreshClaudeTokenIfNeeded(_ credentials: ClaudeCredentials) async -> ClaudeCredentials`
- Behavior:
  - If no `refreshToken`, return original credentials.
  - Refresh when `expiresAt` missing OR `expiresAt / 1000 <= now + 300`.
  - Do not refresh if token expires later than 300-second skew.
  - On refresh failure, return original credentials so usage call behavior remains current; 401 still maps to `Claude token expired. Run 'claude login'.`.
- Why: 5-minute app loop must not refresh on every tick; it refreshes only near expiry like magi-code.
- Acceptance criteria:
  - `fetchClaude()` signature unchanged.
  - ProviderResult behavior unchanged except near-expired tokens can be refreshed before usage call.
  - No `Providers.swift` or `MenuBarView.swift` edits needed.
- Guardrails:
  - Do not add jitter unless separately requested; threshold refresh is required mitigation.
  - Do not surface refresh response payloads in UI or logs.
- Verification: `swift build`; manual menu refresh.

### 4. Implement magi-code-compatible token refresh POST with fallback endpoint
- What: Add refresh network call that posts form-urlencoded refresh request.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`.
- Add private constants/functions:
  - `private let claudeOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"`
  - `private let claudeOAuthPrimaryTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!`
  - `private let claudeOAuthFallbackTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!`
  - `postClaudeRefresh(refreshToken: String) async throws -> ClaudeRefreshResponse`
  - `postClaudeRefresh(to: URL, refreshToken: String) async throws -> ClaudeRefreshResponse`
  - `shouldTryClaudeRefreshFallback(statusCode:error:) -> Bool`
- Request:
  - Method: `POST`.
  - Header: `Content-Type: application/x-www-form-urlencoded`.
  - Body fields: `grant_type=refresh_token`, `refresh_token=<snapshot>`, `client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`.
- Fallback:
  - Try primary endpoint first.
  - Try fallback endpoint only on request failure, 5xx, 404, or 405.
  - Do not fallback on 400/401/403 refresh rejection.
- Response parsing:
  - Accept `access_token` or `accessToken`.
  - Accept `refresh_token` or `refreshToken`; if absent, keep old refresh token.
  - Accept `expires_at` or `expiresAt` as epoch ms.
  - Accept `expires_in` seconds and convert to `nowMs + expires_in * 1000`.
- Why: Matches magi-code endpoint and response-tolerance behavior.
- Acceptance criteria:
  - No external SwiftPM dependencies.
  - `URLComponents` or equivalent percent encoding used for form body.
  - HTTP non-2xx errors do not expose response body.
- Guardrails:
  - Never include real token values in error messages.
  - Keep timeout bounded like existing usage request.
- Verification: `swift build`; optional manual expired-token simulation.

### 5. Add snapshot/resync race guard around writeback
- What: Before refresh, snapshot current creds; after network refresh, re-read source and compare; abort file write if changed.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`, inside `refreshClaudeTokenIfNeeded`.
- Add private functions:
  - `makeClaudeAuthSnapshot(_ credentials: ClaudeCredentials) -> ClaudeAuthSnapshot`
  - `reloadClaudeCredentialsSnapshot(from source: ClaudeCredentialSource) throws -> ClaudeAuthSnapshot?`
  - `snapshotsMatch(_ lhs: ClaudeAuthSnapshot, _ rhs: ClaudeAuthSnapshot) -> Bool` or `Equatable` conformance.
- Behavior:
  1. Capture snapshot from credentials used for refresh.
  2. Use snapshot refresh token for network request.
  3. Re-read same source after response.
  4. If current snapshot differs from original, abort write and return freshly reloaded credentials if valid; otherwise return original credentials.
  5. If current snapshot matches and source is file, write refreshed credentials.
  6. If source is Keychain, do not write; return refreshed credentials in memory only.
- Why: Primary safety net preventing stale clanker-monitor write after magi-code refreshes meanwhile.
- Acceptance criteria:
  - No file write happens when snapshot mismatch detected.
  - Keychain source never writes Keychain or credential file.
  - Usage call can continue with in-memory refreshed keychain credentials.
- Guardrails:
  - Do not attempt to implement magi-code Rust `CrossProcessFileLock`; clanker-monitor cannot acquire it.
  - Race guard must compare credential content, not file modification time only.
  - No secrets in debug output.
- Verification: `swift build`; optional manual test with two processes or by editing file between read and write if test hook added locally then removed.

### 6. Implement file writeback with atomic write and 0600 permissions
- What: Write refreshed file credentials only for file-sourced credentials and only after race guard passes.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`.
- Add private functions:
  - `writeClaudeCredentialsFile(credentials: ClaudeCredentials, refresh: ClaudeRefreshResponse, originalJSON: [String: Any], path: URL) throws -> ClaudeCredentials`
  - `atomicWriteWithPermissions(data: Data, to path: URL) throws`
- Writeback requirements:
  - Preserve top-level JSON object where possible.
  - Replace/write complete `claudeAiOauth` object with:
    - refreshed `accessToken`
    - refresh token from response if present, else existing token
    - refreshed `expiresAt`
    - preserved `scopes` array from existing credentials, defaulting to `[]` only if absent
    - preserved optional `rateLimitTier` / `subscriptionType` if present
  - Use `JSONSerialization.data(withJSONObject:options:)` or `JSONEncoder` with no dependencies.
  - Atomic temp file in same directory, write data, set POSIX permissions `0o600`, then replace/move into place.
  - Remove stale temp file on failed write/replace before rethrowing.
  - Ensure final file permissions are `0600`.
- Why: Mirrors magi-code file writeback and protects shared credential file from partial writes or loose permissions.
- Acceptance criteria:
  - Writeback only occurs for `.file` source.
  - `scopes` survives refresh.
  - Final `~/.claude/.credentials.json` permissions are owner read/write only.
- Guardrails:
  - Do not delete unknown top-level fields.
  - Do not write malformed partial file on failure.
  - Use `trash` only for manual cleanup; code should not shell out.
- Verification: `swift build`; optional `stat -f %Lp ~/.claude/.credentials.json` after manual refresh should show `600`.

### 7. Preserve current usage API behavior and UI contract
- What: Keep Claude usage request and result mapping intact, using possibly refreshed credentials.
- Where: `Sources/ClankerMonitor/ClaudeFetcher.swift`, existing `fetchClaude()` usage request section.
- Behavior:
  - Authorization uses refreshed in-memory `accessToken` when refresh succeeds.
  - 401 still returns `Claude token expired. Run 'claude login'.`.
  - Other errors remain inline `ProviderResult(errorMessage:updatedAt:)`.
- Why: Maintains app contract and avoids leaking implementation details into UI.
- Acceptance criteria:
  - No throwing crosses `fetchClaude()` boundary.
  - `ProviderResult` shape unchanged.
  - Existing menu row rendering unaffected.
- Guardrails:
  - Do not modify `Providers.swift` unless compiler requires no-op import/style cleanup, which should be avoided.
  - Do not modify `MenuBarView.swift`; 5-minute loop is acceptable because refresh threshold prevents repeated refresh.
- Verification: `swift build`; `swift run ClankerMonitor` manual UI check.

## Files Expected To Change
- `Sources/ClankerMonitor/ClaudeFetcher.swift`

## Files Expected Not To Change
- `Sources/ClankerMonitor/Providers.swift` — no change expected; `fetchClaude()` signature remains unchanged.
- `Sources/ClankerMonitor/MenuBarView.swift` — no change expected; 5-minute loop remains, threshold controls refresh frequency.
- `Package.swift` — no change; no external dependencies.
- `README.md` / `build-app.sh` — no change expected because no dependency or packaging change.

## New Private Symbols Checklist
Expected additions in `ClaudeFetcher.swift`:
- `ClaudeCredentialSource`
- `ClaudeAuthSnapshot`
- Extended `ClaudeCredentials`
- `ClaudeRefreshResponse`
- `claudeOAuthClientID`
- `claudeOAuthPrimaryTokenURL`
- `claudeOAuthFallbackTokenURL`
- `refreshClaudeTokenIfNeeded(_:)`
- `isClaudeTokenRefreshNeeded(expiresAt:now:)`
- `postClaudeRefresh(refreshToken:)`
- `postClaudeRefresh(to:refreshToken:)`
- `shouldTryClaudeRefreshFallback(statusCode:error:)`
- `makeClaudeAuthSnapshot(_:)`
- `reloadClaudeCredentialsSnapshot(from:)`
- `writeClaudeCredentialsFile(...)`
- `atomicWriteWithPermissions(data:to:)`
- Small URL form-encoding helper if needed.

## Acceptance Criteria
- Claude credentials still load from Keychain service `Claude Code-credentials` first, then `~/.claude/.credentials.json`.
- File JSON shape remains magi-code-compatible: `claudeAiOauth.accessToken`, `refreshToken`, `expiresAt` epoch ms, `scopes` array.
- Refresh occurs only when `expiresAt` missing or within 300 seconds.
- Refresh POST uses magi-code client ID and endpoint fallback rules.
- Refresh response parser accepts snake_case and camelCase token fields plus `expires_in`.
- File writeback occurs only for file-sourced credentials after snapshot/resync match.
- Keychain-sourced refresh writes nowhere; refreshed access token is used in memory for current usage call.
- If snapshot mismatch detected, clanker-monitor aborts stale write.
- Missing refresh token preserves read-only current behavior.
- No external dependencies added.
- No secrets or response payloads committed or logged.

## Verification Commands
```bash
swift build
swift run ClankerMonitor
```
Optional manual check, not required for automated verification:
1. Back up `~/.claude/.credentials.json` outside repo.
2. Temporarily edit `claudeAiOauth.expiresAt` to an expired epoch-ms value.
3. Run `swift run ClankerMonitor` and trigger refresh.
4. Verify usage loads and `stat -f %Lp ~/.claude/.credentials.json` reports `600`.
5. Restore backup if needed.

## Risks / Unknowns
- Residual race: clanker-monitor cannot acquire magi-code's Rust `CrossProcessFileLock`. Snapshot/resync guard is load-bearing mitigation.
- Residual race: if clanker-monitor and magi-code both refresh simultaneously and both pass snapshot checks before either commits, last writer can still win. Guard reduces but does not eliminate this.
- Refresh overlap: 5-minute app loop can overlap magi-code on-demand refresh. Matching 300-second threshold prevents refresh on every loop tick and limits overlap window.
- Fallback behavior: fallback endpoint must only be tried on request failure, 5xx, 404, or 405; broad fallback on auth failures could hide real credential rejection.
- Keychain behavior: keychain-sourced tokens are refreshed in memory only. Next app refresh may need refresh again if Keychain remains expired, matching magi-code no-writeback behavior.

## Code-Writing Handoff
Implement only `Sources/ClankerMonitor/ClaudeFetcher.swift`. Keep `fetchClaude()` API stable. Add refresh-before-usage path. Preserve read-only fallback for credentials without refresh token. Run `swift build`; optionally run app manually. Do not print or commit credential material.
