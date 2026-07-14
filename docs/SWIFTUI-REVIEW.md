# SwiftUI Best Practices Review — BunnyPalace (MemoryPalace)

Date: 2026-07-14
Scope: `MemoryPalace/Views/` (~36,600 lines across view files), plus state management in `Services/`.

## Summary

The codebase is on a modern SwiftUI stack: the `@Observable` macro is the dominant state pattern (10+ services), environment injection is done correctly at the app root (`MemoryPalaceApp.swift:449-451`), chat rendering uses `LazyVStack`, and there is evidence of deliberate, measured performance work (`ChatInputBar` Equatable conformance with profiling notes). The main debt is structural: several god-views with 30+ `@State` properties and multi-hundred-line bodies, boolean-driven sheet presentation dominating over item-driven, and lingering timing hacks (`DispatchQueue.main.asyncAfter`).

## File size / view body findings

Largest view files:

| Lines | File |
|---|---|
| 2402 | Views/CardFlowView.swift |
| 1864 | Views/SidebarView.swift |
| 1619 | Views/PersonaSettingsTab.swift |
| 1287 | Views/APISettingsTab.swift |
| 1148 | Views/Reading/BookReaderSheet.swift |
| 1129 | Views/GatewayConsoleView.swift |
| 1100 | Views/Reading/PDFReaderSheet.swift |
| 1075 | Views/WorldBookPanelView.swift |
| 1019 | Views/ContentView.swift |
| 889 | Views/MessageSegmentsView.swift |

Measured `body` extents (brace-matched):

- **SidebarView.body: ~758 lines** (110–867). One monolithic `VStack` containing title row, expandable search bar, filters, conversation list, favorites/trash sections. This is the worst offender. Any `@State` change (35 of them) re-evaluates the whole tree.
- **CardFlowView main body: ~350 lines** (156–505). The file also contains 14 separate `var body` declarations — it is really 14 views in one 2402-line file.
- **ContentView.body: ~138 lines** (106–243). Over the 100-line threshold but structured.
- PersonaSettingsTab.body is 3 lines — correctly delegates to computed subviews despite the 1619-line file. Good pattern to replicate.

**Recommendation:** Split SidebarView into `SidebarHeader`, `SidebarSearchBar`, `SidebarFilterRow`, `ConversationListSection`, etc. as separate structs (not just computed properties — separate structs give SwiftUI structural identity boundaries and skip unchanged subtrees). Split CardFlowView.swift into one file per view type.

## State management

**Good:**
- `@Observable` macro used consistently in Services (StyleManager, TodoManager, VoiceMessagePlayer, CCBridgeWebSocketClient, RightPanelNavigator, etc.), injected via `.environment(...)` at app root. Only 4 legacy `ObservableObject` classes remain.
- No `@State var model = SomeObservableObject()` misuse found; the three `@StateObject` uses (CCTerminalController, MiniBrowserController ×2) correctly own controller lifetime.
- `@ObservedObject private var settings = WebSearchSettings.shared` (BlockedDomainsPage, WebSearchQuickSettings, TerminalSettingsTab) is safe for global singletons, but these three should migrate to `@Observable` for consistency and finer-grained invalidation.

**Concerns:**
- `@State` property counts: GatewayConsoleView 39, CardFlowView 36, SidebarView 35, ContentView 34, WorldBookPanelView 27, BookReaderSheet 27. Above ~15 the view is doing view-model work inline. Extract per-screen `@Observable` view models, which also shrinks the bodies.
- SidebarView keeps `@State private var conversations: [Conversation]` + `totalCount` + `isLoadingMore` as a manual paging cache next to a `@Query` for tags. Intentional (paged loading), but the sync logic lives in the view; a `SidebarModel` would make invalidation auditable.
- `.onChange` density (CardFlowView 12, ContentView 11, SidebarView 8) is a symptom of the same thing — cross-state derivations living in view modifiers.

## Performance

**Good — keep and extend:**
- `ChatInputBar: Equatable` + `.equatable()` (CardFlowView.swift:380, 833) with an inline comment documenting a measured 17× redraw amplification (326 body evals vs 19) it prevents. This is exemplary; apply the same treatment to message bubble rows in the chat `LazyVStack`.
- Chat flow uses `LazyVStack` (CardFlowView.swift:189, 2306), with scroll-position pre-load handling.
- ThemeBackgroundView has documented GeometryReader/no-GeometryReader strategies (A/B) rather than cargo-culted GeometryReader.
- SidebarView debounces search via a stored `Task` handle (line 36) — correct structured-concurrency debounce.

**Issues:**
- `AnyView` in 13 places across ContentView, Paging/PagingContainerView, AddToChatSheet. `AnyView` erases structural identity and forces full re-diff of the subtree. Replace with `@ViewBuilder` branches or generics where feasible.
- `DispatchQueue.main.asyncAfter` ×11 in CardFlowView, ×7 in APISettingsTab (30+ total). These are non-cancellable timing hacks; when the view disappears mid-delay the closure still fires against stale state. Prefer `.task { try? await Task.sleep(...) }` which auto-cancels.
- `onAppear` (62 uses) heavily outweighs `.task` (16) + `.task(id:)` (3). Any async work in `onAppear` should move to `.task` for automatic cancellation on disappear.
- BookshelfView.swift:60 attaches `Timer.publish(every: 5).autoconnect()` via `onReceive` — ticks (and invalidates) every 5s for as long as the view exists, even when idle/off-screen. Gate it or use `TimelineView`.
- No `.id(UUID())` anti-pattern found — good.

## Navigation

- `NavigationStack` is used throughout (20+ sites) with one `navigationDestination(item:)` (PersonaSettingsComponents.swift:279). Modern and correct.
- **One legacy `NavigationView`**: `Views/Components/TextSelectSheet.swift:9`. Deprecated API; trivial swap to `NavigationStack`.
- Value-less `NavigationLink { } label: { }` closures (GatewayConsoleView, APISettingsTab, WebLoginSheet) are fine at this scale; only refactor to value-based navigation if programmatic deep-linking is needed.
- BookshelfView.swift:90 documents a real platform pitfall (partial detents + embedded NavigationStack clipping toolbars) with the workaround explained — good hygiene.

## Sheets / alerts

- **57 `.sheet(isPresented:)` vs 14 `.sheet(item:)`.** Many boolean sheets pair with a separate "selected thing" `@State` (e.g. SidebarView's `renamingConversationId` + `renameText` + `showRenameAlert`-style trios in ContentView). That pattern can present a sheet before the companion state is set (stale/blank first frame). Prefer `.sheet(item:)` with an `Identifiable` payload — already done correctly in SidebarView:856/864 (`exportingConversation`, `moveToProjectConversation`) and CardFlowView:501 (`textSelectItem`); make it the default.
- ContentView stacks 6 sheets + 1 alert on one view (lines 231–740). Consider a single `enum ActiveSheet: Identifiable` + one `.sheet(item:)` to make mutual exclusion explicit.
- CardFlowView builds alert bindings inline with `Binding(get:set:)` (lines 492, 766) to adapt optional error state. Works, but `.alert(item:)`-style presentation over an `Identifiable` error type is less fragile.

## Priority actions

1. Split `SidebarView.body` (758 lines) into child view structs. Highest leverage for both readability and redraw scope.
2. Break CardFlowView.swift (14 view types, 2402 lines) into per-view files; extract a chat-screen `@Observable` model to absorb its 36 `@State` vars.
3. Sweep `DispatchQueue.main.asyncAfter` → `.task`/`Task.sleep` (cancellation correctness, not just style).
4. Convert boolean sheets with companion selection state to `.sheet(item:)`; introduce `ActiveSheet` enum in ContentView.
5. Replace the lone `NavigationView` (TextSelectSheet.swift:9) and the 13 `AnyView` sites.
6. Migrate the last 4 `ObservableObject` classes to `@Observable`.
