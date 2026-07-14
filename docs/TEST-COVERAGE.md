# Test Coverage Analysis — BunnyPalace (Lost in Blossom iOS)

Date: 2026-07-14
Scope: `MemoryPalace/` app target, `MemoryPalaceTests/`, `StickerProbeUITests/`

## 1. Current test file inventory

| File | Lines | Kind | Status |
|---|---|---|---|
| `MemoryPalaceTests/ExtractorQuoteTests.swift` | 235 | XCTest unit (MemoryExtractor quote validation, supersede soft-invalidate, pin protection) | **ORPHANED — not in any target** |
| `MemoryPalaceTests/WorldInfoSlotTests.swift` | 173 | XCTest unit (B27 worldInfoBefore/After prompt slots) | **ORPHANED — not in any target** |
| `StickerProbeUITests/StickerProbeUITests.swift` | 46 | XCUITest (sticker edit-mode gesture probe) | In `StickerProbeUITests` target; diagnostic probe, not a regression test |

Note: `MemoryPalace/Views/HapticTestView.swift` matches the `*Test*.swift` glob but is a debug view, not a test.

### Critical configuration findings

1. **No unit test target exists.** `project.yml` (XcodeGen) defines only `MemoryPalaceIOS` (application) and `StickerProbeUITests` (bundle.ui-testing). The `MemoryPalaceTests/` directory is never compiled — the two unit test files cannot run at all.
2. **Stale module import.** Both unit test files use `@testable import 记忆宫殿`, but the current module is `MemoryPalaceIOS` (product name "Lost in Blossom"). Even after adding a test target, the import must be fixed or the files will not build.
3. **Only test scheme is UI-probe.** The `StickerProbeUITests` scheme's test action runs only the gesture probe. There is no scheme that runs unit tests.
4. No `Package.swift`; the project is generated from `project.yml` via XcodeGen.

## 2. Tested vs untested modules

Nominal coverage (if the orphaned tests were revived): `MemoryExtractor` quote paths and `PromptAssembler` world-info slot handling. Effective coverage today: **0 unit tests running.**

Untested surface:

| Area | Files | Approx. lines | Coverage |
|---|---|---|---|
| `Services/` (incl. Search/, Tools/, Voice/) | 74+ | ~15,800+ | None running |
| `ViewModels/` | 7 (ConversationViewModel + 5 extensions, StickerViewModel) | large | None |
| `Models/` | 27 | — | None |
| `Utils/` | 16 | — | None |

## 3. Untested critical modules (Services/ and ViewModels/)

Highest-risk untested code, by size and blast radius:

- `Services/SearchService.swift` (858) — search across conversations/memories; regressions are silent.
- `Services/ClaudeImporter.swift` (850) — data import; a parsing bug corrupts or drops user history. Has pure, directly testable statics (`extractSegments`, `encodeAnyJSON`).
- `Services/MemoryService.swift` (785) + `MemoryEmbedding` / `MemoryHygiene` / `MemorySync` — core memory pipeline; the orphaned ExtractorQuoteTests only touch a slice.
- `Services/CCBridgeWebSocketClient.swift` (717) — bridge transport; reconnect/framing logic untested.
- `Services/ConversationImporter.swift` (615) + `ImportSupport` (385) — second import path.
- `Services/PromptAssembler.swift` (409) + `PromptPostProcessor.swift` (414) — every outgoing request flows through these; slot order bugs directly change model behavior.
- `Services/ProviderRouter.swift`, `AnthropicProvider` (525), `OpenAICompatibleProvider` (504) — request building/stream parsing.
- `Services/SyncEngine` / `SyncStore` (555) / `UnifiedContainerMigration` (407) — migration bugs are unrecoverable for users.
- `ViewModels/ConversationViewModel*` — branching/tree logic (`+Tree`), send pipeline (`+Chat`), group scheduling (`+Group`) all untested.
- `Utils/BudgetCalculator` + `TokenEstimator` — budget math; `HeuristicEstimator.estimate` is a pure function, trivially testable.

## 4. Recommended priority

**P0 — restore test infrastructure (prereq for everything):**
1. Add a `MemoryPalaceTests` unit-test target (`bundle.unit-test`) to `project.yml` with `TEST_HOST` on `MemoryPalaceIOS`, add it to a scheme's test action.
2. Fix `@testable import 记忆宫殿` → `@testable import MemoryPalaceIOS` in both existing test files; get them green. That instantly revives 408 lines of real tests.

**P1 — pure logic, no mocking needed:**
- `PromptAssembler.splitLayers` / `assemble` slot ordering
- `MacroExpander.expand` variants
- `TokenEstimator` (`HeuristicEstimator`, CJK path) + `BudgetCalculator`
- `ClaudeImporter.extractSegments` / `encodeAnyJSON`
- `ContentCleaner`, `PromptPostProcessor`

**P2 — persistence with in-memory SwiftData (pattern already exists in ExtractorQuoteTests):**
- `MemoryService`, `SyncStore`, `ConversationListStore`, `UnifiedContainerMigration`

**P3 — protocol-mocked integration:**
- `ProviderRouter` + provider request/stream parsing against fixture payloads
- `CCBridgeWebSocketClient` reconnect state machine
- `ConversationViewModel+Tree` branch operations

## 5. Example test suggestions — top 3 untested services

### 5.1 PromptAssembler
```swift
@testable import MemoryPalaceIOS
import XCTest

final class PromptAssemblerOrderTests: XCTestCase {
    func testSplitLayersSeparatesStableFromSemi() {
        let parts = [(tag: "persona", content: "P"), (tag: "daily", content: "D")]
        let layers = PromptAssembler.splitLayers(parts)
        XCTAssertTrue(layers.stable.contains("P"))
        XCTAssertTrue(layers.semi.contains("D"))
    }

    func testDisabledSlotIsExcludedFromAssembly() {
        // Build a Preset whose worldInfoBefore slot has isEnabled=false,
        // assemble, and assert the world book text is absent — the inverse
        // of WorldInfoSlotTests, guarding the enable/disable toggle.
    }
}
```

### 5.2 ClaudeImporter (pure statics first)
```swift
final class ClaudeImporterSegmentTests: XCTestCase {
    func testExtractSegmentsPreservesToolUseBlocks() throws {
        let raw = try JSONDecoder().decode(ClaudeRawMessage.self,
            from: Fixtures.claudeMessageWithToolUse) // checked-in JSON fixture
        let segments = ClaudeImporter.extractSegments(from: raw)
        XCTAssertEqual(segments.map(\.kind), [.text, .toolCall, .text])
    }

    func testEncodeAnyJSONRoundTripsNestedObjects() {
        // encodeAnyJSON(nil) == "" / nested dict order-stable output
    }
}
```

### 5.3 SearchService
```swift
final class SearchServiceTests: XCTestCase {
    // Use ModelConfiguration(isStoredInMemoryOnly: true) like ExtractorQuoteTests.
    func testQueryMatchesCJKSubstringAcrossMessages() async throws {
        // Seed 3 conversations, search "杭州", assert only the seeded hit returns
        // and result offsets point at the right message.
    }

    func testEmptyQueryReturnsNoResultsNotAll() async throws { }
}
```

## 6. Summary

Effective unit test coverage is zero: the only real tests (408 lines, covering memory extraction and prompt slots) are orphaned by a missing test target and a stale module name. The single wired-up test target is a manual UI gesture probe. Priority one is a `project.yml` change plus a two-line import fix; after that, the codebase has an unusually large amount of pure, fixture-friendly logic (prompt assembly, importers, token budgeting) that can be covered cheaply before tackling SwiftData-backed and network-facing services.
