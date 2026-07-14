# Memory Leak & Retain Cycle Audit — MemoryPalace iOS

Date: 2026-07-14
Scope: `MemoryPalace/` (Services, ViewModels, Views). Static review of retain-cycle
patterns: strong `self` captures in escaping closures, Timer/NotificationCenter
lifecycle, delegate ownership, and handler registries on long-lived singletons.

## Summary

| Severity | Count | Finding |
|----------|-------|---------|
| Medium   | 1     | `replyAttachmentHandlers` never unregistered on success path (leak + attachment-drop bug) |
| Low      | 2     | `spawnHandlers`/`listHandlers` without timeout; WKScriptMessageHandler never removed |
| Info     | —     | Grep hits that are false positives; several deliberately correct patterns worth keeping |

No unbounded leaks of view models or view controllers were found. Timer and
NotificationCenter hygiene across the codebase is consistently good.

---

## Finding 1 (Medium): stale `replyAttachmentHandlers` entries in CCBridgeWebSocketClient

**Files:**
- `MemoryPalace/Services/CCBridgeProvider.swift` (~lines 57–115)
- `MemoryPalace/Services/CCBridgeWebSocketClient.swift` (~lines 363–367, 505–511)

**Mechanism.** On every send, `CCBridgeProvider` registers two handlers on the
`CCBridgeWebSocketClient.shared` singleton:

- `registerReplyHandler(chatId:)` — the WS client removes this atomically when the
  reply fires (`replyHandlers.removeValue(forKey: chatId)` at line 511). Clean.
- `registerReplyAttachmentHandler(chatId:)` — the WS client only *reads* this on
  dispatch (`if let attHandler = self.replyAttachmentHandlers[chatId]` at line 505)
  and never removes it. `CCBridgeProvider` unregisters it only on the 60s grace-timer
  timeout path (lines 114–115), **not** in the reply-handler success path (lines 61–99).

**Impact.**
1. *Leak (bounded):* one closure + its captured `pendingAttachment` box accumulates
   per distinct chatId that ever completed a reply, held by the singleton for app
   lifetime. Small per entry; bounded by conversation count. Not a VM leak — the
   closure `{ att in pendingAttachment = att }` captures no `self`.
2. *Correctness bug (the real cost):* after a successful reply the stale handler stays
   active for that chatId. A later **proactive CC message with a file attachment** on
   the same chatId matches the stale handler at line 505, writes the attachment into a
   dead `pendingAttachment` capture, and returns — so the
   `unhandledAttachmentHandler` fallback never fires. The attachment is silently
   dropped from the proactive message.

**Fix.** In the reply handler success path in `CCBridgeProvider.swift` (inside the
`registerReplyHandler` closure, next to `self.wsClient.unregisterStreamHandler()`),
add:

```swift
self.wsClient.unregisterReplyAttachmentHandler(chatId: chatId)
```

Alternatively (belt and braces), mirror the reply-handler semantics in the WS client:
use `removeValue(forKey: chatId)` instead of a subscript read at line 505 — but note
that changes behavior if multiple attachments per reply are ever expected.

---

## Finding 2 (Low): `spawnHandlers` / `listHandlers` have no timeout

**File:** `MemoryPalace/Services/CCBridgeWebSocketClient.swift` (lines 70–72, 292–313, 534–586)

Completion closures for `spawnSession` and `listSessions` are removed when the hub
responds (`spawn_cc_ok`/`spawn_cc_fail`, `list_sessions` reply) or when the local
`send` itself errors. If the send succeeds but the hub never responds (hub crash,
reconnect in between), the completions sit in the singleton's dictionaries forever,
retaining whatever the caller captured, and the caller's UI never resolves
(spinner hangs).

**Fix.** Add a grace timer like `CCBridgeProvider.replyTimer` (e.g. 15s) that removes
the handler and fires `.failure(.timeout)`. Also consider clearing both registries in
`handleDisconnect` — a response to a request sent on a dead socket will never arrive.

---

## Finding 3 (Low): WKScriptMessageHandler registered without removal

**Files:**
- `MemoryPalace/Views/MessageContentWebView.swift` (lines 14–15: `heightChanged`, `linkClicked`)
- `MemoryPalace/Views/Reading/BookReaderWebView.swift` (line 159: `bookReader`)

`WKUserContentController.add(_:name:)` retains its handler strongly. The classic
permanent cycle (webview → userContentController → coordinator → webview) is **avoided
today** because both coordinators declare `weak var webView: WKWebView?`
(`MessageContentWebView.swift:54`, `BookReaderWebView.swift:276`). When SwiftUI
dismantles the representable, the webview deallocs and releases the coordinator.

Residual risk:
- Coordinator lifetime is silently pinned to the webview's; any future refactor that
  adds a strong webview/parent-object reference to either coordinator creates a
  permanent cycle with no compiler warning.
- `CardFlowView.swift:1766` creates one `MessageContentWebView` per message bubble, so
  this pattern is instantiated at high volume — hygiene matters here.

**Fix.** Add to both representables:

```swift
static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
    uiView.configuration.userContentController.removeAllScriptMessageHandlers()
    uiView.navigationDelegate = nil
}
```

---

## False positives from the `{ self.` grep (no action)

| Site | Why it is safe |
|------|----------------|
| `MemoryEmbedding.swift:56,62,65,67` | `AppleMemoryEmbedder` is a `static let shared` singleton; app-lifetime object, one-shot `DispatchQueue.async` blocks. Temporary retention only, no cycle. |
| `CCBridgeWebSocketClient.swift:220,278–367,394,636` | Singleton; `handlersQueue.async { self... }` blocks are one-shot and drain immediately. The queue does not store `self` durably. |
| `StickerFileManager.swift:20`, `PhotoStripPanel.swift:264`, `StickerGestureOverlay.swift:153`, `MessageContentWebView.swift:56` | These are `init` bodies (`init(...) { self.x = x }`), not escaping closures. Grep artifact. |
| `MessageContentWebView.swift:91,97` | Inside `WKNavigationDelegate` callbacks; `DispatchQueue.main.async` one-shot. Coordinator holds the parent *struct* (value type) — no cycle. |
| `ConversationViewModel+Chat.swift:633,1191` | Inside `Task { [weak self] in guard let self ... }`; the flagged brace is an `if let` body after the weak-strong dance. |
| `ConversationViewModel+Chat.swift:819` | Strong `self` in a one-shot `Task { @MainActor in ... }` (drainPendingSends). Extends VM lifetime by milliseconds; a Task is not retained by the VM, so no cycle. Intentional: the queued send must not be dropped mid-flight. |
| `ConversationViewModel+Chat.swift:873` | Plain `if let providerManager { ... }` assignment, not a closure. |
| `BookshelfView.swift:60` | `Timer.publish(...).autoconnect()` via `.onReceive` — Combine subscription is owned and torn down by SwiftUI. |

---

## Verified-clean patterns (keep these)

- **Timers:** every `Timer.scheduledTimer` uses `[weak self]` and has a matching
  `invalidate()` — `SyncEngine` (43/54/56/112), `CCBridgeWebSocketClient`
  (reconnect/ping, 644–652/697–700, both invalidated in disconnect at 206–208),
  `CCBridgeProvider.replyTimer` (51/112/213), `VoiceMessagePlayer` (weak self +
  `Task { @MainActor [weak self] }`, invalidated in `stop()`; the class is a singleton
  so the no-owner edge case is moot).
- **Block-based NotificationCenter observers:** `ConversationViewModel` (125–166) and
  `StickerViewModel` (74–95) store the token, capture `[weak self]`, and remove the
  token in `deinit` — including the correct comment that `removeObserver(self)` does
  not work for block-based observers. `PDFReaderSheet` coordinator (915–1008) collects
  tokens into `observers` and removes them all in `deinit`, with `[weak self]`.
- **Selector-based observers:** `PagingViewController` removes in `deinit` (158);
  `CCTerminalPanelView` balances add/remove via `didMoveToWindow` window nil-check
  (keyboard observers) — no leak across attach/detach cycles.
- **Delegates:** no custom `var ...delegate` properties lacking `weak` exist in the
  target. `AVAudioPlayer.delegate` and `webView.navigationDelegate` assignments rely
  on the frameworks' own weak/assign semantics.
- **WebSocket receive loop:** `receiveLoop()` recursion captures `[weak self]` and
  guards `self.task === currentTask`, preventing both a self-retain loop and ghost
  reconnects from a superseded task (447–464).
- **Persistent fallback handlers on the singleton:**
  `unhandledReplyHandler`/`unhandledAttachmentHandler` are installed from
  `ConversationViewModel+Chat` (875/895) with `[weak self]` — the singleton does not
  pin the view model.
- **Terminal streaming:** `attachTerminal` callbacks capture `[weak self]`;
  `detach()` is wired to `.onDisappear` (CCTerminalPanelView:450) and removes both the
  handler struct and the `activeTerminalSessions` entry (400–402).

## Suggested follow-ups

1. Apply Finding 1's one-line fix in `CCBridgeProvider` (also fixes the proactive-
   attachment drop). Worth a regression test: reply completes → proactive cc_reply
   with file on same chatId → fallback handler must receive it.
2. Add timeouts for spawn/list handler registries (Finding 2).
3. Add `dismantleUIView` to both WKWebView representables (Finding 3).
4. Optional: run the app under Instruments' Leaks/Allocations while opening and
   closing conversations, the book reader, and the terminal panel to confirm no
   dynamic-only cycles (this audit is static).
