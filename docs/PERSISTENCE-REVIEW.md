# Data Persistence Review — MemoryPalace (BunnyPalace)

Date: 2026-07-14
Scope: `MemoryPalace/` app target (259 Swift files). Static review of persistence mechanisms, migration, thread safety, backup/export, and corruption resilience.

---

## 1. Persistence mechanisms

### 1.1 SwiftData — primary store

**Architecture ("Route B"):** one unified `ModelContainer` for the entire app lifetime, all profiles ("floors") share a single SQLite store, isolated by a `profileId` string column on every profile-scoped entity.

- Store path: `Application Support/MemoryPalace/unified.store` (`ProfileManager.unifiedStoreURL`, `MemoryPalaceApp.swift`)
- Schema: 16 `@Model` classes registered in `ProfileManager.fullSchema`:
  `Conversation`, `MessageNode`, `UserCard`, `ConversationTag`, `FavoriteItem`, `ImportRecord`, `ImportConversationChange`, `MemoryNote` (legacy), `Memory`, `WorldBook`, `StickerAsset`, `PlacedSticker`, `DailyContext`, `Project`, `BookEntry` (+ tags secondary types)
- Profile scoping is enforced at **compile time only by convention**: `HasProfileId` protocol (`Services/ScopedFetch.swift`) guarantees the field exists; every `FetchDescriptor`/`@Query` must hand-write the `#Predicate { $0.profileId == pid }` (Swift macro limitation). The file itself documents grep-based review as the enforcement mechanism.
- Indexes: `#Index` on `Conversation` (`profileId`, `profileId+lastOpenedAt`, `profileId+isDeleted+lastOpenedAt`) and `MessageNode` (`profileId`, `profileId+conversationId`, `profileId+conversationId+isDeleted`). Good coverage for the hot list queries.
- Large blobs use `@Attribute(.externalStorage)`: `MessageNode.segmentsData`, `MessageNode.imageDescsData`, `Conversation.participantsData`, `BookEntry.coverData`. JSON-in-Data with computed-property codecs (`(try? decode) ?? []` fallbacks).
- Message tree is modeled with `parentId: String?` + `childrenIds: [String]`, **not** `@Relationship` — no cascade rules; referential integrity is maintained manually (e.g. `ClaudeDataWiper` cleans `FavoriteItem`/`UserCard` references explicitly).
- Soft deletes (`isDeleted`/`deletedAt`) on `Conversation`/`MessageNode`.

### 1.2 UserDefaults / @AppStorage

~350 references across 79 files. Notable structured data living in UserDefaults:

- `savedProfiles` — **entire Profile array as JSON**, including `coverImageData: Data?` (PNG cover images) and `regexScriptsData`. Binary image data in UserDefaults is an anti-pattern; a few large covers can push the plist toward the ~4 MB practical limit and slow every defaults read.
- `savedPresets` (PresetManager), `globalWorldBooks` (GlobalWorldBookManager), custom API providers — JSON blobs.
- `GlobalBudgetStore` — budget/spend counters.
- Migration flags: `hasUnifiedContainerMigrationV1`, `unifiedContainerMigrationInProgressProfileId`, `memoryMigrationV2Done`.
- Session state: `lastProfileId`, `userName`, `assistantName`, `syncEnabledProfiles`, MemorySync `lastPull` timestamp, web-search provider configs (keys excluded).

### 1.3 File-based storage

| Store | Path | Format | Atomic? |
|---|---|---|---|
| `FileLibraryStore` | App Support/MemoryPalace/fileLibrary/{profileId}/ | .md files | ✅ `.atomic` |
| `BookStore` | book library dirs | JSON index/notes/bookmarks | ✅ temp + `.atomic` helper |
| `StickerFileManager` | App Support/MemoryPalace/stickers/{profileId}/ | PNG + `_thumb.png` | ❌ plain `write(to:)` |
| `SyncStore` | iCloud Documents/sync/{profileId}/conversations + tombstones | JSON docs | ✅ `.atomic` |
| `ThemeAssetStore` | theme assets | binary | ✅ `.atomic` |
| Voice / attachments / temp exports | tmp + caches | misc | ❌ mostly `try?` |

### 1.4 Keychain

`Utils/KeychainStore.swift` — thin wrapper over generic-password items, service `com.bunny.lostinblossom.apikey`, account = provider id.

- Used for: LLM provider API keys, web-search provider keys (`websearch:<id>` prefix to avoid collisions), ElevenLabs TTS key, MCP/CC-bridge token (base URL goes to UserDefaults, token to Keychain — correct split).
- Optional iCloud Keychain sync per item (`kSecAttrSynchronizable`); `set` deletes both local+synced copies first, then writes one — consistent single-copy invariant.
- `getAll()` has a documented macOS workaround (attributes-only batch, then per-item `get`) for the `kSecMatchLimitAll + kSecReturnData` errSecParam issue. Good.
- Failures are `print`-logged and swallowed; a failed key write is invisible to the user until the next API call fails.

---

## 2. Migration strategies

### 2.1 UnifiedContainerMigration (Route A → Route B)

`Services/UnifiedContainerMigration.swift` — one-time merge of legacy per-profile stores (`{profileId}.store` + ghost-lily `default.store`) into the unified store.

Strengths:
- **Idempotent**: `clearProfileData(profileId:)` before each profile's insert pass, so a crash mid-migration reruns cleanly; `inProgressKey` records the profile being migrated.
- Legacy stores renamed `.backup-2026-04-22` and kept permanently — a real escape hatch.
- Dependency-ordered copy (Conversation before MessageNode, ImportRecord before ImportConversationChange); string-id tree relations mean 1-pass copy suffices.
- Legacy container opened with the new schema (`allowsSave: true`) to let lightweight migration backfill `profileId = ""` — deliberate and documented.
- App-level failure policy: `catch { print; continue }` — app boots (possibly empty) rather than crash-looping; backups remain for manual recovery.

Weaknesses:
- Per-profile open failure is `continue` — a floor can be silently skipped and `doneKey` still set at the end; no user-visible surfacing of partial migration.
- Completion flag lives in UserDefaults, separate from the store. If defaults are lost but the store survives, migration re-runs (harmless thanks to idempotency); if defaults survive but the store is deleted, legacy data is never re-imported.

### 2.2 Schema evolution

- **No `VersionedSchema` / `SchemaMigrationPlan` anywhere.** All schema changes so far rely on SwiftData lightweight migration with defaulted new fields (`profileId: String = ""`, optional usage-token fields, etc.). This works until the first rename/type-change/required field — at which point `makeUnifiedContainer()` will throw and the app **fatalErrors** (see §4.1). Recommend adopting versioned schemas before the next non-additive change.
- Secondary one-shot migration: `migrateMemoryNotesIfNeeded` (MemoryNote → Memory, manual notes only), flag `memoryMigrationV2Done`, `try? context.save()` — a silent save failure would mark the migration done while losing the data (flag is set unconditionally after the save).

---

## 3. Thread safety

### 3.1 What's done right

- Single container, never swapped: profile switching flips `currentProfile` and re-ids the SwiftUI subtree (`.id(currentProfile.id)`), with a synchronous `.profileWillSwitch` notification to drop stale `@Model` refs. This deliberately eliminates the container-swap race class (documented as bug_005/B19 defense-in-depth).
- Background reads follow the correct SwiftData confinement pattern: pass the (Sendable) `ModelContainer`, create a fresh `ModelContext` inside the background closure, `autosaveEnabled = false` (13 call sites: SearchService, RecallTool, importers, ConversationViewModel+Tree).
- Most background fetch paths **snapshot to value types before crossing threads**: `MatchedNode` (struct), `StickerSearchResult` (struct), `MemorySync` explicitly maps to `OutMem` "立刻映射成值类型，不把 Memory 带过 await".
- `MCPService` is an `actor`; `SyncEngine` is `@MainActor`; importers run on dedicated contexts.

### 3.2 Findings

1. **`SearchService.searchStickers` returns live `@Model` instances across threads** (`SearchService.swift:416-459`): `[StickerAsset]` fetched in a `DispatchQueue.global` block on a throwaway `ModelContext` is resumed to the caller (MainActor UI). Same for `performSearch`'s sticker branch via `searchPlacedStickers`? — no, that one snapshots; but `searchStickers` and `findStickersNearMessage` (`:537`, returns `[PlacedSticker]` from a locally created context) hand out models whose backing context is deallocated at closure exit. `PersistentModel` is not Sendable; accessing these on the main thread relies on undefined re-faulting behavior and can crash or read stale data. Fix: snapshot to a value struct like every other path in this file.
2. **No `@ModelActor` anywhere** — all write paths go through the main context (autosave) or ad-hoc background contexts. Concurrent writers (SyncEngine import pump on MainActor vs. importers on background contexts) rely on SQLite-level merging; last-writer-wins at row level with no conflict surfacing.
3. `SyncEngine` runs its 15 s export pump (fingerprint fetch + compare over conversations) on the **main actor**. Safety is fine; jank risk on large floors.
4. `GlobalBudgetStore.shared` (`@Observable`, plain class) mutates `spentUSD` from wherever `commitSpend` is called; if any call site is off-main, this is a data race. Worth an `@MainActor` annotation — it's cheap.

---

## 4. Corruption resilience

### 4.1 The big one: `fatalError` on container creation

`ProfileManager.makeUnifiedContainer()`:

```swift
do {
    return try ModelContainer(for: fullSchema, configurations: [config])
} catch {
    fatalError("Could not create unified ModelContainer: \(error)")
}
```

Every conversation, message, memory, and sticker record lives in this one SQLite file. If it is corrupted (or a future schema change isn't lightweight-compatible), the app **crash-loops at launch with no recovery path** — no rename-and-recreate, no user-facing recovery UI, no automatic fallback to the `.backup-*` stores. Given the emotional weight of this data, this is the highest-priority gap. Recommended ladder: on failure → rename `unified.store` (+ `-wal`/`-shm`) to `unified.store.corrupt-<date>` → recreate empty → flag a recovery banner.

### 4.2 Silent save failures

92 `save()` call sites; **59 are `try? ... .save()`**. A failed save (disk full, constraint violation) is invisible — no retry, no user surfacing, no breadcrumb. At minimum route failures through `BreadcrumbLog`. Notable: `migrateMemoryNotesIfNeeded` sets its done-flag even if the save failed (§2.2).

### 4.3 Blob decode fallbacks

All JSON-in-Data computed properties (`regexScripts`, `participants`, `segments`, world-book entries) degrade to `[]`/`nil` on decode failure. Graceful (no crash) but silent: a corrupt `participantsData` quietly turns a group chat into an empty-participant chat, and the next `set` overwrites the corrupt original. Consider logging decode failures.

### 4.4 File-store atomicity

- JSON stores (BookStore, FileLibraryStore, SyncStore, ThemeAssetStore) consistently use atomic writes. Good.
- `StickerFileManager.saveStickerImage` writes image and thumbnail with plain `write(to:)` — a crash between the two leaves a torn pair, and non-atomic writes can leave truncated PNGs. Low stakes, easy fix (`options: .atomic`).

### 4.5 Sync isolation (good design)

`SyncStore`/`SyncEngine` (design doc in header): file-state sync via iCloud JSON documents, merge only inserts missing nodes, `childrenIds` union, metadata LWW, tombstone directory for deletes — "同步层故障最多是没同步，弄不脏本机库" (sync failure at worst means no sync; it can't dirty the local DB). This is the right failure isolation.

### 4.6 Crash-durability details

- `Conversation.draftText`: per-keystroke write + explicit save, deliberately not relying on autosave — drafts survive process kill (B41). Durable, at the cost of write amplification on every keystroke.
- Migration in-progress marker + idempotent clears make the big migration crash-safe.

---

## 5. Backup / export capabilities

| Capability | Mechanism | Coverage |
|---|---|---|
| Legacy store backups | `.backup-2026-04-22` renames, kept permanently | Pre-migration data only |
| Cross-device sync (doubles as off-device copy) | SyncStore iCloud JSON per conversation + floor.json + tombstones | Only floors with sync enabled; conversations only |
| Conversation export | `MarkdownExporter` + `ExportOptionsSheet` (longest-path / current-path modes) | Single conversation, lossy (markdown) |
| Sticker packs | `StickerPackExporter` (manifest.json + assets, share sheet) | Stickers only |
| Memories | `MemorySync` push/pull to gateway | Explicit user memories only |
| Device backup | unified.store lives in Application Support → included in iOS iCloud/local device backups by default | Full, but implicit |
| Keychain | optional iCloud Keychain sync per key | API keys |

**Gap:** no in-app full-database export/restore (e.g. zip of `unified.store` + stickers + fileLibrary, or a JSON dump of all floors). Everything today is either partial, lossy, or implicit via device backup. Given §4.1, a one-tap "export everything" is the cheapest insurance available.

**Test coverage gap:** `MemoryPalaceTests/` contains only 2 test files (extractor/world-info); zero tests for migration, SyncStore merge, or store round-trips.

---

## 6. Prioritized recommendations

1. **P0** — Replace `fatalError` in `makeUnifiedContainer()` with rename-corrupt-store + recreate + recovery banner (§4.1).
2. **P0** — Fix `SearchService.searchStickers` / `findStickersNearMessage` returning `@Model` instances across threads; snapshot to structs (§3.2.1).
3. **P1** — Add a full-data export (store files + sticker/fileLibrary dirs zipped to share sheet) (§5).
4. **P1** — Adopt `VersionedSchema`/`SchemaMigrationPlan` before the first non-additive schema change (§2.2).
5. **P1** — Route `try? save()` failures through BreadcrumbLog; fix `migrateMemoryNotesIfNeeded` setting its done-flag on failed save (§4.2).
6. **P2** — Move `Profile.coverImageData` out of the UserDefaults `savedProfiles` blob into files (§1.2).
7. **P2** — Atomic writes in `StickerFileManager`; `@MainActor` on `GlobalBudgetStore`; log blob decode failures.
8. **P2** — Unit tests for UnifiedContainerMigration idempotency and SyncStore merge/tombstone logic.
