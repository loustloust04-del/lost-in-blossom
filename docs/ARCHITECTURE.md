# BunnyPalace (MemoryPalace) — Architecture Overview

> Reference document for future development. Generated from a code audit on 2026-07-14.
> App target lives in `MemoryPalace/`; a Node.js gateway lives in `gateway/`.

## 1. High-level structure

SwiftUI + SwiftData iOS app following **MVVM with service layer**:

- **Views** (105 files, ~36.6k LOC) — SwiftUI. Chat surface (`CardFlowView`), sidebar, settings tabs, right-panel plugins, book/PDF readers, CC terminal.
- **ViewModels** (7 files, ~3.7k LOC) — one dominant `ConversationViewModel` (`@Observable`), split across extensions: `+Chat`, `+Tree`, `+Actions`, `+Group`, `+Search`.
- **Services** (103 files, ~18.6k LOC) — chat providers, prompt assembly, memory, sync, import, web search, MCP tools, TTS, health, stickers.
- **Models** (27 files, ~4.0k LOC) — SwiftData `@Model` classes + value types (`Preset`, `APIProvider`, `WorldBook`, `Memory`, ...).
- **Utils** (16 files, ~1.7k LOC) — theming, keychain, token estimation, markdown.

State management uses the **Observation framework** (`@Observable`, not `ObservableObject`) plus SwiftData persistence, `UserDefaults` for lightweight settings, and Keychain (`KeychainStore`) for API keys.

### Entry point & dependency injection

`MemoryPalaceApp` (`@main`, 1119 LOC) creates long-lived `@Observable` managers as `@State` and injects them via `.environment(...)`:

```
ThemeManager.shared, ProfileManager, ProviderManager, PresetManager,
CharacterCardManager, RightPanelToolManager, GlobalWorldBookManager,
RightPanelNavigator
```

Services are otherwise reached through **singletons** (`StyleManager.shared`, `MCPToolCache.shared`, `BreadcrumbLog.shared`) or **parameter passing** — `sendMessage(...)` carries `model, profile, preset, providerManager, context` on every call.

### Data model (SwiftData, "Route B" unified container)

Single `ModelContainer` shared by all profiles ("floors"). Every `@Model` carries a `profileId` column and **all fetches must predicate on it** (enforced by convention, with compound `#Index`es). Legacy per-profile stores are migrated by `UnifiedContainerMigration`.

Conversations are **trees**, not lists: `MessageNode` holds `parentId: String?` + `childrenIds: [String]` (string IDs, not `@Relationship`), enabling ChatGPT-style branching/regeneration. `Conversation.currentNodeId` marks the active leaf; the ViewModel materializes `currentPath: [MessageNode]` for display.

## 2. Key services

| Service | Responsibility |
|---|---|
| `ProviderRouter` | Owns 3 provider instances; routes by `APIProvider.type`; merges their streaming state; sanitizes bridge tools; strips image blocks for non-vision models. |
| `BaseChatProvider` (`ChatService.swift`) | Abstract NSObject: URLSession SSE streaming, callback plumbing (`onToken/onComplete/onError`), token-usage accumulation, error-body parsing. Subclasses: `OpenAICompatibleProvider`, `AnthropicProvider`, `CCBridgeProvider`. |
| `CCBridgeProvider` + `CCBridgeWebSocketClient` | The "CC lane": routes chat through a Claude Code session via Hub/tmux WebSocket instead of an HTTP LLM API. Physically isolated from the API lane. |
| `PromptAssembler` | Pure `struct` that assembles the system prompt from preset/persona/memories/world books/summaries; `splitLayers` divides output into stable / semi-stable / volatile layers for **prompt caching** (volatile macros like `{{time}}` are kept out of the cached prefix). |
| `MemoryService` | `MemoryStore` / `MemoryRetriever` protocols + `MemoryExtractor` (post-turn extraction with a cheap model). Supporting cast: `MemoryEmbedding`, `MemoryHygiene`, `MemorySync`, `CrossWindowMemory`, `LocalMemoryMode`. |
| `ContextSummarizer` / `ContextInheritance` | Rolling conversation summaries; deep-inherit context when spawning new conversations. |
| `MCPService` / `MCPToolCache` / `ToolCallLoop` | Fetch MCP tool descriptors from the gateway, translate to Anthropic/OpenAI tool schemas, execute tool calls. |
| `Services/Search/*` | `WebSearchService` + `WebSearchToolService` over ~14 pluggable providers (Tavily, Brave, Exa, SearXNG, ...) plus an `InternalBrowser`/`BrowseURLTool`. Search tools are injected **inside each provider**, not at the Router (double-injection previously caused duplicate-tool errors). |
| `ProviderManager` (Models/APIProvider.swift) | Provider/model registry, Keychain-backed API keys, budget accounting (`budgetGate`, `commitSpend`), favorites, CC bridge URLs. |
| Import pipeline | `ConversationImporter`, `ClaudeImporter`, `BookImporter`, `TavernCardParser`, `ImportSupport` — ChatGPT/Claude/SillyTavern data ingestion. |
| Sync | `SyncEngine`, `SyncStore`, `MemorySync` — cross-device sync. |

## 3. Data flow: user input → API → display

```
ChatInputBar (CardFlowView)
  │  sendMessage(text, model, profile, preset, providerManager, context)
  ▼
ConversationViewModel+Chat.sendMessage
  ├─ lane gating: group round? CC lane? API turn in flight? → pendingSends queue
  ├─ insert user MessageNode into SwiftData tree (currentPath updated)
  ├─ assemblePrompt:
  │    memoryStore.listHot + WorldBook fetch + ContextSummarizer.load
  │    + Project instructions + CrossWindowMemory (first turn)
  │    + StyleManager + VoicePromptInjector
  │    → PromptAssembler.assemble → splitLayers (stable/semi/volatile)
  ├─ preCheckBudget (BudgetCalculator + ProviderManager.budgetGate)
  ▼
ProviderRouter.sendStreaming
  ├─ type .openaiCompatible → OpenAICompatibleProvider ┐
  ├─ type .anthropic        → AnthropicProvider        ├─ SSE over URLSession
  └─ type .ccBridge         → CCBridgeProvider ── WebSocket → Hub/tmux (Claude Code)
  ▼
onToken → provider.streamingContent (@Observable) → MessageSegmentsView re-renders live
onComplete → finalize assistant MessageNode → commitBudgetSpend
           → extractMemoriesIfNeeded (cheap model) → triggerContextSummaryIfNeeded
           → finishAssistantTurn → drainPendingSends → notifyIfBackground
```

**Turn serialization:** `assistantTurnInFlight` (API lane) and `ccTurnConversationId` (CC lane) gate concurrent sends; anything sent mid-turn lands in `pendingSends` and is replayed when the turn ends. The two lanes never block each other. Group chats (`kind == "group"`) run a serial member round (`runGroupRound`) with interjection support.

**Streaming state is global-single-value** (`streamingContent`, one task per provider instance); UI leakage across conversations is prevented by id checks (`streamingNodeId`, `streamingConversationId`, `isCurrentConvResponding`).

## 4. Module relationship diagram

```
                    ┌────────────────────────────────────────────┐
                    │           MemoryPalaceApp (@main)          │
                    │  ProfileManager · ProviderManager · Preset │
                    │  Theme/Card/WorldBook/RightPanel managers  │
                    └──────────────────┬─────────────────────────┘
                                       │ .environment(...)
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
┌───────────────┐            ┌──────────────────┐          ┌──────────────────┐
│  SidebarView  │◄──────────►│  CardFlowView    │          │  Right panels /  │
│  ContentView  │            │  MessageSegments │          │  Settings tabs   │
└───────┬───────┘            └────────┬─────────┘          └────────┬─────────┘
        │                             │                             │
        └───────────────┬─────────────┘                             │
                        ▼                                           │
        ┌────────────────────────────────┐                          │
        │     ConversationViewModel      │◄─────────────────────────┘
        │  (+Chat +Tree +Actions +Group  │
        │   +Search)  · pendingSends     │
        └──┬─────────┬──────────┬────────┘
           │         │          │
           ▼         ▼          ▼
   ┌──────────┐ ┌──────────┐ ┌─────────────────┐
   │ Prompt   │ │ Memory   │ │ ProviderRouter  │
   │ Assembler│ │ Service  │ ├─ OpenAICompat.  │──► HTTP SSE
   │ (+World  │ │ (+Embed, │ ├─ Anthropic      │──► HTTP SSE
   │  Books,  │ │  Hygiene,│ └─ CCBridge ──────│──► WebSocket → gateway/Hub
   │  Summary)│ │  Sync)   │      │            │
   └────┬─────┘ └────┬─────┘      ▼            │
        │            │      ToolCallLoop ◄── MCPService/MCPToolCache
        │            │      WebSearchService (14 providers)
        ▼            ▼
   ┌─────────────────────────────────────┐
   │  SwiftData unified ModelContainer   │
   │  Conversation · MessageNode (tree)  │
   │  Memory · WorldBook · Project ...   │
   │  (all partitioned by profileId)     │
   └─────────────────────────────────────┘
```

## 5. Tight coupling & refactoring candidates

1. **`ConversationViewModel` is a god object** (~3.1k LOC over 6 files). It orchestrates lane gating, tree mutation, prompt assembly, budget checks, memory extraction, notifications, group rounds, and CC follow-up handling. Prompt assembly (`assemblePrompt`, ~180 lines) and turn/queue management could each be extracted into standalone services (`TurnCoordinator`, `PromptContextBuilder`).
2. **Callback-based streaming.** `BaseChatProvider` is an NSObject with `fatalError` abstract methods and 3 closure callbacks. Migrating to `AsyncThrowingStream` would eliminate the shared mutable state (`buffer`, `receivedDone`, accumulated usage) and the `resetState` reentrancy hazards that forced the pendingSends queue.
3. **Global single-value streaming state.** One `streamingContent` per provider instance means at most one in-flight stream per lane; per-conversation isolation is patched via id fields (`streamingNodeId`, `streamingConversationId`, `isCurrentConvLoading` comments call out the leak). A per-turn stream object would remove the whole class of leaks.
4. **Parameter-drilling DI.** `model/profile/preset/providerManager/context` ride along every chat call and are even captured in `PendingSend` (including `ModelContext`). An injected environment/session object would slim signatures.
5. **Singletons sprinkled through services** (`StyleManager.shared`, `MCPToolCache.shared`, `ThemeManager.shared`, `BreadcrumbLog.shared`) make unit testing the prompt pipeline hard.
6. **Tool injection split across layers.** Search tools are injected inside each provider while MCP bridge tools are sanitized at the Router (`sanitizedBridgeTools`); the comment history shows this already caused a duplicate-tool bug. A single tool-registry pass before dispatch would be safer.
7. **Convention-enforced profile isolation.** Every fetch must remember the `profileId` predicate; a forgotten predicate silently leaks data across profiles. A scoped fetch helper (`ScopedFetch` exists but is not universally used) should be mandatory.
8. **View-layer size.** `CardFlowView` (2402 LOC), `SidebarView` (1864), `PersonaSettingsTab` (1619) are candidates for decomposition.

## 6. Statistics

| Area | Files | LOC |
|---|---|---|
| Views | 105 | 36,625 |
| Services | 103 | 18,555 |
| Models | 27 | 3,997 |
| ViewModels | 7 | 3,749 |
| Utils | 16 | 1,735 |
| App entry (`MemoryPalaceApp.swift`) | 1 | 1,119 |
| **Total** | **259** | **65,780** |

Largest files: `CardFlowView` 2402 · `SidebarView` 1864 · `PersonaSettingsTab` 1619 · `ConversationViewModel+Chat` 1584 · `APISettingsTab` 1287 · `BookReaderSheet` 1148 · `GatewayConsoleView` 1129 · `MemoryPalaceApp` 1119.
