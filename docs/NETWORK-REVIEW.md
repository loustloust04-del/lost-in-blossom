# Network Layer Review — MemoryPalace iOS

Date: 2026-07-14
Scope: all URLSession / URLRequest / WebSocket usage under `MemoryPalace/`.

---

## 1. Architecture map

### 1.1 LLM chat providers (streaming, delegate-based)

| Component | Transport | Endpoint | Notes |
|---|---|---|---|
| `Services/ChatService.swift` — `BaseChatProvider` | `URLSessionDataTask` + delegate | — | Shared SSE plumbing: `startRequest()`, `didReceive`, `didCompleteWithError`, error-body accumulation |
| `Services/AnthropicProvider.swift` | SSE POST | `{baseURL}/messages` | Prompt-cache breakpoints, MCP beta header, client-side tool loop (`fireAnthropicRound()` re-POSTs per tool round) |
| `Services/OpenAICompatibleProvider.swift` | SSE POST | `{baseURL}/chat/completions` | Also non-streaming via `URLSession.shared` |
| `Services/CCBridgeProvider.swift` | WebSocket (via hub) | `ccBridgeHubURL` (UserDefaults) | No URLSession; 120s reply grace timer, dedup via hub `reply_id` |
| `Models/APIProvider.swift` | `URLSession.shared` | `{baseURL}/models` (20s), test connection (15s) | Auto-appends `/v1` heuristic |

### 1.2 WebSocket

`Services/CCBridgeWebSocketClient.swift` (singleton) — the only WS client.
- Multi-URL fallback (LAN + Tailscale), rotates candidate on each reconnect.
- Exponential backoff reconnect: 1s doubling to 30s cap; resets on successful connect.
- Keepalive ping every 5s (`Timer` + `sendPing`).
- `NWPathMonitor` → `reconnectIfNeeded()` on network restore (only connectivity monitoring in the app).
- Reply dedup: `seenReplyIds` persisted in UserDefaults, rolling 600 entries (hub replays last 60s + offline queue).
- Old-session race guards: `webSocketTask === self.task` checks in `didOpen` / `didClose` / `receiveLoop`.
- `maximumMessageSize = 64 MiB` (matches hub maxPayload for base64 file frames).
- Correctly calls `session?.invalidateAndCancel()` before creating a new session (startTask, disconnect).

### 1.3 Gateway REST clients (default base `https://blossom.amberrib.com`, UserDefaults `gatewayBaseURL`)

| Client | Endpoints | Timeout | Error handling |
|---|---|---|---|
| `GatewayConsoleClient` | `/health`, `/api/memories*`, `/api/mcp/tools`, `/api/admin/{memories,channels,cron,mcp}` | 8–30s | Mostly `try?` → nil/false |
| `MemorySync` | `/api/memories/sync`, `/api/memories/diff` | 15s | catch → return 0 |
| `VitalsClient` | `/api/vitals`, `/api/screentime` | 5s | `try?` → nil |
| `TodoManager` | gateway todo endpoints | 8s | `try?` → nil/false, UserDefaults cache fallback |
| `HealthBridgeClient` | `/health-data` | 10s | `try?`, fire-and-forget |
| `DesireInboxService` | `/api/memories/desires` | 10s | catch, drops |
| `AnniversaryClient` | anniversaries endpoints | 12s | `try?` → nil/false |
| `TweetsClient` | tweets endpoint | 12s | `try?` |
| `GatewayBrowseClient` | gateway browse | caller-set | throws |
| Views: `GatewayMemoryView` (12s), `MCPSettingsTab` (15s) | ad-hoc requests in views | — | — |

### 1.4 MCP bridge

`Services/MCPService.swift` (actor) — `GET /mcp/tools` (5-min in-memory cache), `POST /mcp/call`. 30s timeout, Bearer token from Keychain, typed `MCPError` (best error model in the codebase).

### 1.5 Web search providers

`Services/Search/Providers/` — Tavily, Brave, Exa, Jina, Bocha, Metaso, Zhipu, Perplexity, LinkUp, SearXNG, DuckDuckGo, Ollama, BingLocal, GatewaySearchProvider. All use `URLSession.shared` + `req.timeoutInterval = common.timeout` (user-configurable, default 5000ms in `WebSearchCommonOptions`). Jina floors at 10s, GatewaySearchProvider at 30s.

### 1.6 Misc

- `Voice/ElevenLabsClient.swift` — `https://api.elevenlabs.io/v1/text-to-speech/{voice}`, 60s timeout, typed errors mapping 401/403/402/429.
- `Search/InternalBrowser/InternalBrowser.swift` — WKWebView reader, own watchdog Task timeouts (8s read / 12s evaluate).

---

## 2. Issues

### P0 — URLSession leak per streaming request (`ChatService.swift:82-88`)

```swift
func startRequest(_ request: URLRequest) {
    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    self.urlSession = session
    ...
}
```

A fresh delegate-based `URLSession` is created for **every** chat message (and every tool-loop round via `fireAnthropicRound()`), and it is **never invalidated**:

- `cancel()` (ChatService.swift:57-62) nils `urlSession` without `invalidateAndCancel()`.
- `didCompleteWithError` (ChatService.swift:133-165) nils it without `finishTasksAndInvalidate()`.

URLSession retains its delegate strongly until invalidated, so every request leaks a session object *and* pins the provider in a retain cycle (provider → session → delegate=provider). Long chat sessions accumulate sockets/FDs and memory. `CCBridgeWebSocketClient.startTask()` does this correctly (line 435) — apply the same pattern: call `session.finishTasksAndInvalidate()` in `didCompleteWithError` and `invalidateAndCancel()` in `cancel()`.

### P1 — No retry logic anywhere for HTTP

`grep -riE 'retry|backoff|attempt'` over app sources: zero hits. Every HTTP call is single-shot:

- A transient failure mid-chat (cell handoff, 429, 5xx) surfaces straight to the UI as a failed message.
- `MemorySync` returns 0 and silently skips a sync window.
- Search providers fail the whole tool call on one 5s timeout.

The only resilience in the app is the WS reconnect + hub replay. Recommend a small shared helper (2–3 attempts, jittered backoff, retry only on timeout/connection-lost/429/5xx, never on 4xx) for the idempotent GET clients and `sendNonStreaming`.

### P1 — Silent error swallowing in gateway clients

`GatewayConsoleClient` (lines 34, 152, 233, 328, 345), `TodoManager`, `AnniversaryClient`, `HealthBridgeClient`, `VitalsClient` all use `try? await URLSession.shared.data(for:)` and collapse *every* failure (DNS, timeout, 401, 500, decode) into `nil` / `false` / `[]`. The UI cannot distinguish "offline" from "empty list" from "bad token". `MCPService` / `ElevenLabsClient` show the right pattern (typed errors). At minimum, admin mutations (`sendOK` for delete/pin/cron/channel-key) should report failure reasons — today a failed DELETE looks identical to success unless the caller re-fetches.

### P2 — No timeout on streaming chat requests

`AnthropicProvider.sendStreaming` / `OpenAICompatibleProvider` never set `timeoutInterval` and use `URLSessionConfiguration.default` unchanged:

- Per-request idle timeout: default 60s (acceptable for SSE).
- `timeoutIntervalForResource`: default **7 days**. A stalled-but-dripping stream can hang a message indefinitely with no watchdog. `CCBridgeProvider` has a 120s grace timer; the HTTP providers have nothing equivalent.

Also `AnthropicProvider.sendNonStreaming` (line 234) and `OpenAICompatibleProvider.sendNonStreaming` (line 276) set no `timeoutInterval` — background memory-agent calls default to 60s idle but unbounded resource time.

### P2 — CCBridgeProvider constant/message mismatch (`CCBridgeProvider.swift:14-16, 112-119`)

`replyGracePeriod = 120` but the comments and the user-facing failure message both say 60s (`"CC 60 秒内没回…"`). Either the timeout or the copy is wrong; fix one.

### P2 — No global offline handling

`NWPathMonitor` exists only inside `CCBridgeWebSocketClient` for WS reconnect. HTTP clients have no connectivity awareness: no `waitsForConnectivity`, no offline queue (except TodoManager's read cache and the hub-side replay for CC chat). Sends attempted offline fail after full timeout instead of failing fast or queueing. Consider a shared `NetworkMonitor` and `waitsForConnectivity = true` for the background/sync sessions.

### P3 — Timeout inconsistency

Timeouts are scattered per-call-site: 5s (Vitals), 8s (Todo/console), 10s, 12s, 15s, 20s, 30s, 60s. Search default of 5s is aggressive on cellular. No central constants; drift is already visible (Jina/Gateway providers hand-patch floors with `max(...)`).

### P3 — WS `send()` failures mostly ignored

Nearly all call sites pass `{ _ in }` to `send(...)` (register_device, set_cc_config, terminal_input/resize/attach). For chat this is intentional (grace timer + hub replay), but terminal keystrokes and config pushes are silently droppable with no user feedback.

### P3 — Minor

- `request.httpBody = try? JSONSerialization.data(...)` in all providers — a serialization failure sends an empty-body POST instead of erroring locally.
- `CCBridgeWebSocketClient` ping/reconnect use `Timer.scheduledTimer` — safe only while called on main; `scheduleReconnect()` is main-hopped via `handleDisconnect`, but `reconnectIfNeeded()` relies on callers being on main.
- 64 MiB `maximumMessageSize` means a single hub frame can allocate ~64MB+ (base64 decode doubles peak) on device.
- `disconnect()` uses `DispatchQueue.main.sync` when off-main — deadlock risk if ever called from a queue the main thread is waiting on (currently UI-only callers, so latent).

---

## 3. What's done well

- WS client: URL rotation, backoff with cap+reset, ping keepalive, stale-task guards, persisted reply dedup, proper session invalidation.
- Prompt-cache-aware request shaping (stable body ordering, `metadata.user_id` node pinning).
- `MCPService` actor: typed errors, Keychain token, TTL cache.
- ElevenLabs client status-code mapping.
- Search timeout is user-configurable in settings rather than hardcoded.

## 4. Recommended fix order

1. Invalidate URLSessions in `BaseChatProvider` (P0, ~4 lines).
2. Add watchdog/resource timeout to streaming providers (P2, pairs with #1).
3. Shared retry helper for idempotent gateway GETs + `sendNonStreaming` (P1).
4. Replace `try?` with typed errors in `GatewayConsoleClient` admin mutations (P1).
5. Fix `replyGracePeriod` vs message copy (P2, 1 line).
6. Centralize timeout constants (P3).
