# TODO/FIXME Audit — MemoryPalace (Swift)

Date: 2026-07-14
Scope: `grep -rn "TODO|FIXME|HACK|XXX|WORKAROUND|TEMP|TEMPORARY" --include="*.swift" MemoryPalace/`

## Summary

| Severity | Count |
|----------|-------|
| P0 (crash / data loss) | 0 |
| P1 (affects functionality) | 3 |
| P2 (technical debt) | 1 |
| P3 (nice to have) | 1 |
| **Total** | **5** |

No P0 findings. All five markers are `TODO`s; no `FIXME`/`HACK`/`XXX` markers exist in the Swift sources.

## Top 5 Most Urgent

1. **[P1] ImportView.swift:106** — Conflict count hardcoded to `0`; import summary under-reports skipped data to the user.
2. **[P1] CCBridgeProvider.swift:103** — Chat streaming disabled; replies appear only after full completion (up to 60s grace timer).
3. **[P1] HealthService.swift:57** — Local mode does not suppress health-data injection (gate commented out pending X5).
4. **[P2] ConversationListStore.swift:143** — Full-table conversation scan in `ccSessionOwners`; predicate not fully pushed down.
5. **[P3] GlassEffectCompat.swift:8** — `.ultraThinMaterial` fallback in place of native `glassEffect` until Xcode 18 GA.

## Findings

### 1. MemoryPalace/Views/ImportView.swift:106 — P1
> `/// 跨楼层冲突跳过数（TODO: importer 接入后替换为实际值）`

`currentConflictCount` (and the adjacent `currentCopiedCount`) are hardcoded to `0`. The import-complete summary therefore always reports zero cross-floor conflicts and zero copied items, even when the importer actually skipped or duplicated conversations. Users can finish an import believing nothing was skipped when data was silently omitted from the result — the closest thing to a data-integrity issue in this audit (the data is not lost by this code, but its omission is hidden).
**Recommendation:** Wire these two properties to real counters on both importers (`claudeImporter` / `importer`), mirroring the existing `skippedConversationCount` pattern. Until then, hide the stat rows instead of showing a false `0`.

### 2. MemoryPalace/Services/CCBridgeProvider.swift:103 — P1
> `// TODO: 后续用 MCP 工具的 streaming 回调做正确的聊天流式，再打开这里。`

The `cc_stream` handler registration is commented out because tmux `capture-pane` output mixes reply text with terminal noise (tool calls, progress bars). Replies arrive only via the one-shot `replyHandler`, guarded by a 60-second grace timer, so the chat UI shows nothing while CC thinks and fails hard at 60s. Functional degradation, not a crash.
**Recommendation:** Implement streaming via an MCP callback channel (clean token stream, no pane scraping), then re-enable the commented `registerStreamHandler` block. Keep the grace timer as the fallback path.

### 3. MemoryPalace/Services/HealthService.swift:57 — P1
> `// && !LocalMode.shared.isOn   // TODO(X5): 本地模式下不注入健康`

`shouldInject` gates the `{{health}}` macro only on availability + user toggle. The planned local-mode gate is commented out because X5 (local mode) has not landed. Once local mode ships, HealthKit data (steps, heart rate, energy) would still be injected into prompts sent off-device — a privacy expectation violation for a mode whose whole point is locality.
**Recommendation:** Track this TODO inside the X5 work item as a hard acceptance criterion, so local mode cannot ship without the `!LocalMode.shared.isOn` conjunct. No action possible before X5 exists.

### 4. MemoryPalace/Services/ConversationListStore.swift:143 — P2
> `/// TODO: 谓词可下推（ccBridgeSessionName != nil && isDeleted == false），对话多时这里是全表扫`

`ccSessionOwners` fetches all non-deleted conversations and filters `ccBridgeSessionName` in memory. The predicate already excludes deleted rows, but the session-name filter runs client-side, so cost grows linearly with total conversation count every time `CCSessionPickerSheet` opens. Performance-only; correct results.
**Recommendation:** Push `ccBridgeSessionName != nil` into the `#Predicate` and add `propertiesToFetch` for `id`/`title`/`ccBridgeSessionName`. Low risk, small win; do opportunistically.

### 5. MemoryPalace/Utils/GlassEffectCompat.swift:8 — P3
> `// TODO: 等 Xcode 18 GA 后用 #if compiler(>=6.2) 加回原生 glassEffect。`

Deliberate compatibility shim: CI is on Xcode 16.4 whose SDK lacks the `glassEffect` symbol, so all call sites use an `.ultraThinMaterial` fallback via `glassEffectCompat`. Purely cosmetic; well-documented and centralized.
**Recommendation:** Leave as is. When CI moves to Xcode 18 GA, wrap the native call in `#if compiler(>=6.2)` inside this one file — call sites need no changes.
