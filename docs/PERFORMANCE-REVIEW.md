# Performance Hotspot Analysis — MemoryPalace (BunnyPalace iOS)

Date: 2026-07-14
Scope: static review of `MemoryPalace/` Swift sources (~65,800 LOC). No profiling run; findings are code-level hotspots ranked by expected user-visible impact.

## Codebase size overview

Largest files (complexity proxy):

| Lines | File |
|------:|------|
| 2402 | Views/CardFlowView.swift |
| 1864 | Views/SidebarView.swift |
| 1619 | Views/PersonaSettingsTab.swift |
| 1584 | ViewModels/ConversationViewModel+Chat.swift |
| 1287 | Views/APISettingsTab.swift |
| 1148 | Views/Reading/BookReaderSheet.swift |
| 1129 | Views/GatewayConsoleView.swift |
| 1119 | MemoryPalaceApp.swift |
| 1100 | Views/Reading/PDFReaderSheet.swift |
| 1075 | Views/WorldBookPanelView.swift |

CardFlowView (the chat surface) is by far the heaviest view and also the hottest render path — most P1 findings live in or under it.

---

## P1 — Likely user-visible jank

### 1. Wallpaper decoded from disk inside SwiftUI `body`
`Views/ThemeBackgroundView.swift:131` and `:158` — both `ThemeBackgroundArtwork` and `ThemeBackgroundArtworkFlex` call `UIImage(contentsOfFile: url.path)` directly in `body`:

```swift
var body: some View {
    Group {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable()
```

Every body re-evaluation performs synchronous disk I/O + full-size image decode on the main thread. The chat background re-evaluates whenever its container invalidates (theme changes, size changes, parent re-render). A full-resolution wallpaper photo can be a 10–40 MB decode.

Fix: load once into `@State`/cache keyed by URL (an `NSCache<NSURL, UIImage>` like `StickerFileManager` already has), and downsample to screen pixel size via `CGImageSourceCreateThumbnailAtIndex` (the pattern already exists in `Services/AttachmentStore.swift:121-127`). Note the UIKit path (`Views/Paging/PagingViewController.swift:346`) already guards with `needsImageRefresh` — the SwiftUI path has no such guard.

### 2. JSON parse + image decode per body evaluation in chat bubbles
`Views/CardFlowView.swift:1357-1392` — `MultimodalUserBubble.parsed` is a computed property running `JSONSerialization.jsonObject` over the message content string, then `body` does `UIImage(data: imgData)` (full decode, no downsampling):

```swift
var body: some View {
    let block = parsed          // JSONSerialization every render
    ...
    if let imgData = block.imageData, let uiImg = UIImage(data: imgData) {
```

These bubbles live inside the chat `LazyVStack`, so scrolling re-instantiates rows and re-runs parse + decode. Image data appears to be stored inline in message content (base64 → Data), so both memory and CPU cost scale with photo size.

Fix: parse once in `init` or cache in `@State` via `.task`; decode with `UIImage.preparingThumbnail(of:)` / CGImageSource capped at display size (~200 pt frame → ≤ 600 px).

### 3. MessageSegmentsView: re-tokenization + regex per render, index-based ForEach identity
`Views/MessageSegmentsView.swift:140` (`items` computed property) rebuilds the segment list on every body evaluation, and `:207`:

```swift
ForEach(resolved.indices, id: \.self) { idx in
```

Positional identity means any segment insertion (streaming appends segments) re-diffs every row, and `itemView` re-runs `RegexEngine.apply(scripts:...)` plus `parseRichSegments` per text item per render. This sits inside every assistant bubble — it multiplies with finding 2 during streaming.

Fix: give items stable identity (hash of content + index of kind), memoize `RegexEngine.apply` output keyed by (nodeId, revision) the way `Utils/ContentCleaner.swift` already caches with `NSCache`.

### 4. BookshelfView: filesystem scan on main thread every 5 seconds
`Views/Reading/BookshelfView.swift:60`:

```swift
.onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
    BookStore.refreshEntries(profileId: profileId, context: modelContext)
}
```

`BookStore.refreshEntries` does directory enumeration + `Data(contentsOf:)` reads (`Services/BookStore.swift:157-183`) and SwiftData writes, all on the main run loop, forever, even when the bookshelf is idle or the iCloud folder hasn't changed. `.common` mode also fires during scroll tracking.

Fix: move the scan to a background task and diff by folder mtime before touching SwiftData; or drop the timer entirely and rely on the existing `.fileLibraryDidChange` notification + NSMetadataQuery for iCloud arrivals.

### 5. Search-result avatars decoded full-size in row body
`Views/Sidebar/SidebarSearchResults.swift:72` — `CharacterCardMatchRow` runs `UIImage(data: result.imageData)` in `body` for each visible row. Tavern character-card PNGs are commonly 1–5 MB; decoding at full resolution for a ~30 pt avatar, repeated per keystroke as results change, burns CPU and transient memory.

Fix: decode once per result off-main into a small thumbnail (CGImageSource, max ~120 px) and store it on the result model.

---

## P2 — Worth fixing, lower blast radius

### 6. `DispatchQueue.main.sync` from WebSocket callback
`Services/CCBridgeWebSocketClient.swift:220`:

```swift
DispatchQueue.main.sync { self.isConnected = false }
```

Blocks the URLSession delegate queue on the main thread; deadlocks outright if that code path is ever entered on main. Use `DispatchQueue.main.async` or `await MainActor.run`.

### 7. Synchronous embedding with lazy model load
`Services/MemoryEmbedding.swift:79` — `embed()` is `queue.sync`, and the first call pays `model.load()` inside that sync block. Callers (`Services/MemoryService.swift:340, 591`) sit in the memory-recall path of message sending; if reached from the main actor, the first embed of a session stalls the UI for the model-load duration. Make `embed` async or pre-warm the model off-main at startup.

### 8. Per-bubble GeometryReader + `.task(id: midY)` churn
`Views/CardFlowView.swift:194-199` — every chat bubble carries a `GeometryReader` background whose `.task(id: frame.midY)` cancels and respawns a Task on every scroll frame, per visible bubble. `bubblePositions` is wisely `@ObservationIgnored` (`ViewModels/StickerViewModel.swift:24`), so no invalidation storm, but the Task create/cancel churn during fast scroll is pure overhead. Prefer a `PreferenceKey` reduction or `onGeometryChange` (iOS 16+/18 API) writing straight to the dictionary.

### 9. Sync `Data(contentsOf:)` on interactive paths
Acceptable in importers (which use `.mappedIfSafe`), questionable in UI flows:
- `Views/AddToChatSheet.swift:226` — reads file (≤10 MB) synchronously during attach.
- `Views/PersonaSettingsTab.swift:272`, `Views/WorldBookPanelView.swift:892`, `Views/Web/MiniBrowserView.swift:29`, `MemoryPalaceApp.swift:478`.
Wrap in `Task.detached` / async file APIs where user taps trigger them.

### 10. `repeatForever` animations in the chat surface
`Views/CardFlowView.swift:1274, 1319` and `Views/MemoryPanelView.swift:606`. Forever-repeating animations keep Core Animation committing while visible; verify they are removed when their condition ends (streaming finished) — a `repeatForever` bound to a stale `value` keeps the display link busy at 60/120 Hz. Gate them with `.animation(..., value:)` on a state that goes inert, or use `PhaseAnimator`.

### 11. O(pages × notes) filtering in PDF annotation list
`Views/Reading/PDFReaderSheet.swift:465-467` — `topLevel.filter { $0.chapter == page }` inside `ForEach(pages)`. Precompute `Dictionary(grouping:)` once per render. Minor until a book has hundreds of notes.

### 12. Non-lazy `ScrollView { VStack }` in unbounded-content views
`Views/GatewayConsoleView.swift:29` builds eight cards eagerly (fixed count — fine), but `Views/CalendarPanelView.swift:197`, `Views/PersonaSettingsTab.swift:872/999`, `Views/APISettingsTab.swift:712` render collection-driven content in plain `ScrollView` without `LazyVStack`. Cost is proportional to item count; APISettingsTab groups all providers/models eagerly. Convert to `LazyVStack` where item counts are user-growable.

---

## Things already done right (keep these)

- Chat list uses `LazyVStack` + stable `ForEach(viewModel.currentPath, id: \.id)` (`CardFlowView.swift:189-190`) and native `defaultScrollAnchor(.bottom)` pinning.
- Streaming was already optimized: per-token SwiftData writes cut (`ConversationViewModel+Chat.swift:637` comment), `streamingText` read in a leaf view to avoid whole-surface re-render (`CardFlowView.swift:819, 1450`).
- `ContentCleaner` caches regex output in `NSCache` with a PUA fast path.
- `StickerFileManager` has a global `NSCache` for sticker image data.
- `AttachmentStore` downsamples via `CGImageSourceCreateThumbnailAtIndex` (max 2048 px).
- Importers read with `.mappedIfSafe`; `SearchService` fans out to `DispatchQueue.global(qos: .userInitiated)`.

## Suggested order of attack

1. ThemeBackgroundView caching + downsampling (#1) — cheapest fix, broadest visual surface.
2. MultimodalUserBubble parse/decode memoization (#2) and MessageSegmentsView identity/memoization (#3) — direct scroll and streaming smoothness.
3. BookshelfView timer scan off-main (#4) and CCBridge `main.sync` (#6) — correctness-adjacent.
4. The rest opportunistically, verified with Instruments (Time Profiler + SwiftUI template) on-device before/after.
