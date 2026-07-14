# API Key Security Audit — BunnyPalace (Lost in Blossom iOS)

Date: 2026-07-14
Scope: `MemoryPalace/` iOS app source (259 Swift files), Info plists, entitlements,
build config, plus repo-hygiene checks on server-side directories (`gateway/`, `cc-bridge/`).
All key/token values in this report are redacted.

## Summary

Key management in the app is largely done right: all long-lived API keys live in the
iOS Keychain behind a single wrapper (`MemoryPalace/Utils/KeychainStore.swift`), no
credentials are hardcoded in Swift source or plists, and key entry fields use
`SecureField`. The significant gaps are: (1) the gateway auth token is stored in
plaintext `UserDefaults` and used by ~12 clients, (2) App Transport Security is fully
disabled (`NSAllowsArbitraryLoads = true`), and (3) the CC Bridge hub token is placed
in the WebSocket URL as a query parameter and that full URL is printed to the console.

## 1. Hardcoded keys / secrets

**Result: clean in app source.**

- Pattern scan for `sk-*`, `sk-ant-*`, `ghp_*`, `AIza*`, `eyJ*` (JWT), `tvly-*`,
  `pplx-*`, `xai-*`, `jina_*` etc. across `MemoryPalace/`, `MemoryPalaceTests/`,
  `scripts/`, `gateway/`, `cc-bridge/src`, `vps-mcp/`, `mcp-bridge/`: no hardcoded
  keys in Swift source, `project.yml`, entitlements, or plists.
- Long-string-literal scan of Swift files: only UI/font/identifier strings, no secrets.
- `Info-iOS.plist`, `MemoryPalaceIOS.entitlements`, `PrivacyInfo.xcprivacy`: no keys.
- One live key exists on disk server-side: `gateway/data/config-overrides.json`
  contains an `sk-…` (redacted) API key. It is **git-ignored** (`gateway/.gitignore:8`)
  and not tracked, so it is a server config file, not a leak into the repo — but see
  §5 file-permission note.

## 2. Key storage / management

**Mechanism: Keychain via `KeychainStore` (`MemoryPalace/Utils/KeychainStore.swift`)**
- Generic-password items, service `com.bunny.lostinblossom.apikey`, account = provider id.
- Optional iCloud Keychain sync (`kSecAttrSynchronizable`), toggled by the
  `apiKeyCloudSync` setting; `reencryptAllKeys(sync:)` rewrites all items on toggle.

Stored in Keychain (good):
- LLM provider keys — `APIProviderManager` (`MemoryPalace/Models/APIProvider.swift`,
  `apiKey(for:)` / `setApiKey`), with in-memory cache.
- Web search provider keys — account `websearch:<id>`
  (`MemoryPalace/Services/Search/WebSearchSettings.swift`).
- ElevenLabs key — account `elevenlabs` (`MemoryPalace/Views/VoiceSettingsSection.swift`).
- MCP tool-bridge token — account `mcpBridgeToken`; comment explicitly says
  "token 不进 UserDefaults" (`MemoryPalace/Services/MCPService.swift`).
- CC Bridge hub token — saved through `setApiKey(_:for: "cc-bridge")`
  (`MemoryPalace/Views/APISettingsTab.swift` ~line 460).

Legacy migration (good): `migrateLegacyKeysIfNeeded()` in `APIProvider.swift` moves
old `apikey-*` UserDefaults entries into Keychain and deletes the plaintext copies.

UI (good): all key entry fields are `SecureField` (`APISettingsTab`,
`ProviderManageView`, `VoiceSettingsSection`, `GatewayConsoleView`).

### Findings

**F1 — HIGH: `gatewayAuthToken` stored in plaintext UserDefaults.**
The gateway bearer token is read from `UserDefaults.standard.string(forKey: "gatewayAuthToken")`
by at least 12 call sites: `GatewayConsoleClient`, `VitalsClient`, `MemorySync`,
`TodoManager`, `DesireInboxService`, `HealthBridgeClient`, `AnniversaryClient`,
`TweetsClient`, `GatewaySearchProvider`, `GatewayBrowseClient`, `GatewayMemoryView`,
`WebSearchServiceOptions`. It is written in `GatewayConsoleClient.swift:24` and
`GatewayConsoleView.swift:762`. UserDefaults is an unencrypted plist included in
backups and readable by anything with container access.
*Recommendation:* store it via `KeychainStore` (mirror the `MCPBridgeConfig` pattern:
URL in UserDefaults, token in Keychain), with a one-time migration like
`migrateLegacyKeysIfNeeded()`.

**F2 — MEDIUM: second plaintext path for the CC Bridge hub token.**
`CCBridgeProvider.swift:125` falls back to `UserDefaults "ccBridgeHubToken"`. The
settings UI saves the hub token to Keychain, so this UserDefaults read looks legacy —
but if anything populates it, the token sits in plaintext. No writer was found in the
app; remove the fallback or migrate it to Keychain on first read.

**F3 — LOW: Keychain items don't set `kSecAttrAccessible`.**
`KeychainStore.set` omits the accessibility class, so items default to
`kSecAttrAccessibleWhenUnlocked`. Set it explicitly — e.g.
`kSecAttrAccessibleAfterFirstUnlock` (needed if background tasks read keys) or
`...ThisDeviceOnly` for non-synced items.

**F4 — INFO: iCloud sync of raw API keys.**
`apiKeyCloudSync` syncs raw provider keys through iCloud Keychain. This is a standard,
end-to-end-encrypted mechanism, but it widens exposure to every device on the Apple ID.
Acceptable; worth documenting for the user.

## 3. Keys logged to console

**F5 — MEDIUM/HIGH: CC Bridge token printed inside WebSocket URLs.**
`CCBridgeWebSocketClient.connect(urls:token:)` appends the hub token as a
`token=` query item (lines ~183–190), and the client then prints full URLs:
- line 181: `print("[CCBridge] connect called, urls=\(inputURLs)…")`
- line 236: `print("[CCBridge] forceReconnect called, url=\(url)")`
- line 241: `print("[CCBridge] connecting to \(url)")`
- line 434: `print("[CCBridge] startTask: \(url)")` — logs the **final URL including `token=`**.

Console output lands in the unified log and sysdiagnose captures.
*Recommendation:* redact query strings before logging (log `url.host` + path only),
and preferably move the token out of the URL entirely (e.g. first WS frame or a
`Sec-WebSocket-Protocol`/header-based scheme the hub validates).

Otherwise clean: no `print`/log of `apiKey`/`Authorization` header values anywhere.
`PushNotifications.swift:31` logs only a 16-char prefix of the APNs device token
(low sensitivity, acceptable).

## 4. Keys in plist files

**Result: clean.** `Info-iOS.plist`, `PrivacyInfo.xcprivacy`, entitlements, and
`project.yml` contain no credentials. (`PrivacyInfo` correctly declares UserDefaults
API use, reason CA92.1.)

## 5. Network security

**F6 — HIGH: ATS globally disabled.**
`Info-iOS.plist` sets `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`.
This permits plaintext HTTP to any host for every URLSession in the app, so a
user-entered `http://` base URL would silently send `Authorization: Bearer …` and
`x-api-key` headers in cleartext.
*Recommendation:* replace with `NSAllowsLocalNetworking = true` (covers the intended
LAN/loopback cc-bridge and Ollama cases) plus, if needed, narrow per-domain
exceptions. Keep default ATS for the internet at large.

**F7 — MEDIUM: cc-bridge WebSocket is plaintext `ws://` with token in query.**
Defaults/placeholders: `ws://127.0.0.1:7890/ws` (built-in), UI suggests
`ws://192.168.1.5:7890/ws` (LAN) and `ws://xxx.ts.net:7890/ws` (Tailscale).
Loopback and Tailscale are fine (Tailscale encrypts underneath); raw LAN Wi-Fi is
sniffable — the hub token and full chat traffic cross the network unencrypted.
*Recommendation:* document Tailscale as the recommended off-loopback transport, or
add `wss://` support on the hub.

**HTTPS posture (good):**
- Gateway default base URL is `https://blossom.amberrib.com`
  (`GatewayConsoleClient.swift:9`).
- All cloud providers (Anthropic, OpenAI-compatible, ElevenLabs, search providers)
  default to `https://` endpoints; the only `http://` defaults are loopback
  (`http://localhost:11434/v1` for Ollama, `http://127.0.0.1:3100/mcp` placeholder).

**F8 — INFO: no certificate pinning.**
No `URLAuthenticationChallenge`/`SecTrust` handling anywhere; all TLS uses system
trust. Given endpoints are user-configurable and the gateway cert is a normal
public CA cert, pinning is optional. If desired, pin only `blossom.amberrib.com`
via `NSPinnedDomains` in ATS (iOS 14+), keeping user-defined endpoints unpinned.

## 6. Repo / VPS hygiene (out-of-app observations)

- `gateway/.env`, `gateway/.env.save`, `cc-bridge/chatroom/.env` exist on disk and are
  git-ignored (not tracked — verified via `git ls-files`). Good.
- **F9 — MEDIUM (VPS):** secrets files are world-readable (`-rw-r--r--`):
  `gateway/.env`, `gateway/data/config-overrides.json` (contains a live `sk-…` key),
  `cc-bridge/chatroom/.env`. Run `chmod 600` on them.
- **F10 — MEDIUM (VPS):** git remotes embed GitHub PATs directly in the remote URLs
  (`git remote -v` shows `github_pat_…` / `ghp_…`, redacted). These live in plaintext
  in `.git/config` and appear in any process listing during fetch/push. Prefer a
  credential helper (`gh auth setup-git`) or SSH remotes, and rotate the exposed PATs.

## Priority fix list

1. F1 — move `gatewayAuthToken` to Keychain (HIGH)
2. F6 — scope ATS to local networking instead of `NSAllowsArbitraryLoads` (HIGH)
3. F5 — stop logging WS URLs containing `token=` (MEDIUM/HIGH)
4. F9/F10 — `chmod 600` server secret files; rotate + de-embed git PATs (MEDIUM, VPS)
5. F2 — remove `ccBridgeHubToken` UserDefaults fallback (MEDIUM)
6. F7 — prefer Tailscale/`wss://` off-loopback (MEDIUM)
7. F3 — set explicit `kSecAttrAccessible` (LOW)
