# Crash Resilience Review — MemoryPalace iOS

Audit date: 2026-07-14
Scope: `MemoryPalace/` (app target only; tests excluded)
Method: pattern grep (`!` force unwraps, `try!`, `as!`, `fatalError`, IUOs, unguarded indexing) followed by manual context review of every hit.

## Totals

| Pattern | Count | Notes |
|---|---|---|
| Force unwraps (`x!`, `)!`, `.first!` …) | 19 sites | see inventory below |
| `try!` | 3 | all static `NSRegularExpression` literals |
| `as!` | 0 | none in app target |
| `fatalError` | 6 | 1 reachable in production, 2 abstract-method stubs, 3 `init(coder:)` boilerplate |
| Implicitly unwrapped optionals (`var x: T!`) | 0 | none found |

Overall: the codebase is in good shape. Most force unwraps are locally guarded (checked non-empty two lines above) or provably infallible (`String.data(using: .utf8)`). One `fatalError` is a genuine production crash path; two URL unwraps and one ObjC-runtime unwrap are the only other realistic risks.

## Top 10 risks (ranked)

### 1. `MemoryPalaceApp.swift:163` — `fatalError` on ModelContainer creation — HIGH
```swift
return try ModelContainer(for: fullSchema, configurations: [config])
} catch {
    fatalError("Could not create unified ModelContainer: \(error)")
}
```
**Can it crash in production? Yes.** SwiftData container creation fails on schema migration mismatch (any model change without a migration plan), disk-full, or store corruption. Result: 100% crash-at-launch loop — the worst failure mode, and the store holds the user's chat history.
**Fix (medium effort):** on failure, back up the store file (`unifiedStoreURL` + `-wal`/`-shm`) to a rescue directory, retry once with a fresh store, and surface a recovery banner. Never fatalError over user data.

### 2. `Services/Voice/ElevenLabsClient.swift:62,64` — force-unwrapped URL build with interpolated `voiceId` — MEDIUM
```swift
var comps = URLComponents(url: Self.apiBase.appendingPathComponent("text-to-speech/\(voiceId)"), resolvingAgainstBaseURL: false)!
...
var req = URLRequest(url: comps.url!)
```
**Can it crash? Edge-case.** `voiceId` comes from profile config (user-editable). `appendingPathComponent` percent-encodes most input, but a pathological ID (or future change to string concatenation) breaks the invariant silently. This is a throwing function already.
**Fix (trivial):** `guard let comps = ..., let url = comps.url else { throw VoiceError.badVoiceId }`.

### 3. `Utils/WKWebViewNoAccessory.swift:32` — `method_getTypeEncoding($0)!` — MEDIUM
```swift
let types = method.flatMap { String(cString: method_getTypeEncoding($0)!) } ?? "@@:"
```
**Can it crash? Yes, iOS-version-dependent.** `method_getTypeEncoding` is documented to return NULL-able `UnsafePointer<CChar>?`. The `?? "@@:"` fallback only covers `method == nil`, not a NULL encoding. This runs on every WKWebView keyboard-accessory swizzle; an OS behavior change crashes all web views.
**Fix (trivial):** `method.flatMap { method_getTypeEncoding($0) }.map { String(cString: $0) } ?? "@@:"`.

### 4. `Services/ChatService.swift:53,112` — `fatalError("Subclass must implement")` — MEDIUM (latent)
**Can it crash? Only via programmer error**, but the failure is remote: adding a new provider subclass and missing one override compiles cleanly and crashes at runtime mid-conversation.
**Fix (easy):** both methods are `throws` — replace with `throw ChatServiceError.notImplemented(#function)` so a miss degrades to an error bubble instead of a crash.

### 5. `Views/CalendarPanelView.swift:313,314,320,322` — forced `Calendar` math — LOW-MEDIUM
```swift
let start = calendar.date(from: comps)!
let end = calendar.date(byAdding: .month, value: 1, to: start)!
let firstOfMonth = calendar.date(from: comps)!
let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
```
**Can it crash? Unlikely but not provably safe.** Components are derived from real dates in the same calendar, so round-trips normally succeed — but this runs on every calendar render, and non-Gregorian user calendars / TZ transitions are exactly where `Calendar` returns nil. Note line 308 in the same file already uses `?? month` for the identical operation, so the convention exists.
**Fix (trivial):** nil-coalesce to `date`/`month` like line 308 does.

### 6. `try!` static regexes — `BookImporter.swift:39,45`, `Voice/VoiceMessageWriter.swift:16` — LOW (latent)
**Can it crash? Only if the pattern literal is edited into invalidity**; then it crashes at first use (static lazy init), likely in the field rather than in dev if the code path is rarely exercised (book import, voice blocks).
**Fix (easy):** acceptable pattern for compile-time-constant regexes, but add a unit test that touches each regex once so a bad edit fails in CI, or convert to Swift 5.7 `Regex` literals which are compile-checked.

### 7. `Views/CreateGroupChatView.swift:80` — `UnicodeScalar(65 + idx)!` — LOW
**Can it crash?** Only if `slots.count` grows past the surrogate range (55,231 slots) — practically unreachable today, but the force unwrap encodes an invariant ("slot count is small") that lives in a different part of the file (the add-button logic).
**Fix (trivial):** `Character(UnicodeScalar(65 + min(idx, 25))!)` or precomputed letter array.

### 8. `Utils/ContentCleaner.swift:133` — `Range(match.range, in: cleaned)!` — LOW
**Can it crash?** Safe today (NSRange comes from a match over the same immutable string), but brittle: any future edit that mutates `cleaned` between match and conversion crashes. Elsewhere in the codebase (BookImporter:115) the same conversion is done with `if let`.
**Fix (trivial):** `guard let r = Range(...) else { continue }` — matches house style.

### 9. `Services/SearchService.swift:55,58,61` — `calendar.date(byAdding: .day, value: -7/-30/-90, to: now)!` — LOW
**Can it crash?** Effectively no — subtracting days from `Date()` in any calendar succeeds. Included for completeness; same one-line `?? now` fix if a lint rule banning `!` is adopted.

### 10. `init(coder:)` fatalErrors — `IOSPromptTextView.swift:108`, `Paging/PagingViewController.swift:83`, `CCTerminalPanelView.swift:173` — INFORMATIONAL
**Can it crash?** Only if these views are ever instantiated from a storyboard/XIB; the project is programmatic-UI. This is standard, accepted Swift boilerplate. No action needed.

## Verified-safe sites (no action)

- `FileLibraryStore.swift:50` — `data(using: .utf8)!`: UTF-8 encoding of a Swift String cannot fail.
- `BookImporter.swift:123,124` — `matches.first!`: guarded by `if matches.isEmpty { return ... }` at line 116.
- `Reading/BookReaderSheet.swift:969,970` — `.min()!`/`.max()!`: inside `if let survivor = overlapping.min(...)`, so `overlapping` is non-empty.
- `Services/MemorySync.swift:189` — `chars[i + 1]`: loop bound is `chars.count - 1` with a `count >= 2` guard.
- `Services/GroupChatScheduler.swift:79` — `pool[0]`: `pool` falls back to `candidates`, which has a `guard !candidates.isEmpty` at line 44.
- `Voice/VoiceMessageWriter.swift:50` — `matches[0]`: guarded by `guard !matches.isEmpty` at line 45.
- `Views/FileLibraryPanelView.swift:103` — `previews[meta.path]!`: ternary condition proves the key exists.
- `Services/PromptAssembler.swift:221` — `messages[lastUserIdx]`: index from `lastIndex(where:)` on the same array.
- `AnthropicProvider.swift:477` — `parts[0]`: guarded by `parts.count > 1`.
- Dictionary-style index writes (`providers[idx]`, `styles[idx]`, `items[idx]`, `activeBlocks[index]`) all use indices obtained from `firstIndex(where:)` on the same collection, or a dictionary keyed by Int.

## Recommended next steps

1. Fix #1 (ModelContainer recovery) before the next schema change — it is the only finding that can brick the app.
2. Apply the four trivial fixes (#2, #3, #5, #8) in one small PR; combined diff is under 15 lines.
3. Convert `ChatService` abstract stubs to thrown errors (#4).
4. Optional hygiene: enable SwiftLint `force_unwrapping` / `force_try` as warnings to keep the count at its current low level.
