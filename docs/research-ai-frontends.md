# AI Chat Frontend Research

Research date: 2026-03-26. Covers 15+ projects across web, desktop, and native platforms.

---

## Landscape Overview

| App | Stars | Platform | Stack | Provider Count | Memory/RAG | License |
|-----|-------|----------|-------|---------------|------------|---------|
| **Open WebUI** | ~129k | Web (self-hosted) | Svelte + Python/FastAPI | Many | RAG (9 vector DBs) + auto-memory | MIT |
| **NextChat** | ~87.6k | Web/Desktop/Mobile | Next.js + Tauri | 12+ | None | MIT |
| **LobeChat** | ~74k | Web/PWA/Desktop | Next.js + Zustand + Drizzle | 42+ | RAG knowledge base | MIT |
| **Jan** | ~41k | Desktop | React + Tauri + llama.cpp | Local + cloud | None | AGPL |
| **ChatBox** | ~39k | Desktop/Mobile/Web | React + Electron | Multi | None | GPLv3 |
| **LibreChat** | ~35k | Web (self-hosted) | React/TS + Node.js + MongoDB | 20+ | Agent-based key/value memory | MIT |
| **SillyTavern** | ~24.9k | Web (self-hosted) | jQuery SPA + Express | 30+ | Summarize + Vector RAG + Lorebooks | AGPL |
| **BetterChatGPT** | ~8.4k | Web/Desktop | React + Electron | OpenAI-compat | None | MIT |
| **Enchanted** | ~5.9k | iOS/macOS/visionOS | Swift/SwiftUI | Ollama only | Local history | Apache 2.0 |
| **RikkaHub** | ~3.7k | Android + Web UI | Kotlin/Compose + React | OpenAI/Claude/Gemini | ChatGPT-style memory | AGPL/Commercial |
| **macai** | ~843 | macOS | Swift/SwiftUI + AppKit | 8+ | iCloud Sync | Apache 2.0 |
| **TypingMind** | ~828 | Web/PWA | Static JS | Multi | Plugins-based | Commercial |
| **Warden** | ~225 | macOS | Swift/SwiftUI (100%) | 8+ | None | Apache 2.0 |
| **BoltAI** | N/A | macOS/iOS | SwiftUI + AppKit | 7+ | None | Commercial |
| **Msty** | N/A | Desktop/Web | Electron | Local + cloud | Knowledge Stacks (RAG) | Commercial |

---

## Detailed Analysis: Key Projects

### RikkaHub

**Positioning:** Best native Android multi-provider AI chat client. Solo developer project (re-ovo, Hangzhou), 2273 commits, 140 releases. Very actively maintained.

**Tech stack:**
- Android: Kotlin (80%) + Jetpack Compose + Material You
- Architecture: MVVM + Clean Architecture
- DI: Koin / DB: Room (v13, 5 DAOs) / Network: OkHttp + kotlinx.serialization
- Web UI module: React 19 + Vite 7 + Zustand + Radix UI + Tailwind 4

**Architecture patterns:**
- `ChatService` singleton with `Map<UUID, StateFlow<ConversationState>>` for multi-conversation
- `GenerationHandler` core engine: applies transformers, executes tools, streams responses
- `ProviderManager` factory pattern instantiates providers from `ProviderSetting` configs
- `MessageNode` entities support conversation branching (tree structure, not linear)
- Room DB schema: Conversation, MessageNode, Memory, ManagedFile, GenMedia

**Unique features:**
- MCP support on mobile (rare)
- SillyTavern character card compatibility
- QR code import/export for provider configs
- Message branching (explore alternative response paths)
- Agent system with prompt variables

**Relevance to MemoryPalace:** Closest architectural analog in terms of native app + multi-provider + memory. The Room DB schema with separate Memory DAO is a good reference for SwiftData/Core Data modeling. The `ChatService` + `GenerationHandler` separation is a clean pattern.

---

### SillyTavern (酒馆)

**Positioning:** The dominant open-source AI chat frontend. 24.9k stars, 319 contributors, 11.5k commits. The ecosystem standard for character-based AI chat.

**Tech stack:**
- Backend: Node.js + Express
- Frontend: Vanilla JS + jQuery SPA (no modern framework)
- Storage: Flat files (JSONL for chats, PNG+JSON for characters, JSON for settings)
- No database at all

**Architecture patterns:**
- Client constructs prompts, server proxies to APIs
- Per-backend parameter allowlists strip unsupported fields
- JSONL chat storage: one message per line, first line = metadata (efficient append)
- Character cards: PNG images with JSON embedded in `tEXt` chunk (TavernCard V2 spec)

**Memory/Context (three complementary systems):**
1. **Chat Summarization** — periodically condenses history when exceeding context window
2. **Smart Context (Vector/RAG)** — ChromaDB vectorizes chat history, retrieves by semantic similarity
3. **World Info / Lorebooks** — keyword-triggered lore injection from structured knowledge bases

**Character system:**
- TavernCard V2: `name`, `description`, `personality`, `scenario`, `first_mes`, `mes_example`, `alternate_greetings`, `creator_notes`, `character_book`, `extensions`
- PNG with embedded JSON is portable (avatar + metadata bundled)
- Became an ecosystem standard (Chub.ai, CharacterHub, etc.)

**Extension architecture:**
- UI extensions: browser-side, hook into event system, full DOM access
- Server plugins: Node.js side, create new API endpoints
- Low barrier to entry (basic JS/jQuery knowledge sufficient)

**Group chat:**
- Reply strategies: Natural Order (name-mention extraction), List Order, Random, Talkativeness (per-character slider)
- Auto-mode with configurable delay

**Prompt construction order:**
1. Main Prompt (System) → 2. World Info (before) → 3. Persona → 4. Character Description → 5. Personality → 6. Scenario → 7. Enhance Definitions → 8. Auxiliary Prompt → 9. Chat Examples → 10. World Info (after) → 11. Chat History → 12. Post-History Instructions

**Relevance to MemoryPalace:** The three-layer memory system (summarize + RAG + lorebooks) is the most sophisticated approach found. The character card format could be adopted for persona import/export. The prompt construction order is a good reference for configurable prompt assembly. The flat-file storage design shows that a database isn't strictly necessary, but SwiftData would be more appropriate for a native app.

---

### Open WebUI

**Positioning:** Largest community (129k stars), most enterprise-ready self-hosted option. The only major project using Svelte.

**Tech stack:**
- Frontend: Svelte + TypeScript + Vite + Tailwind
- Backend: Python / FastAPI (async-native)
- DB: SQLite (default) or PostgreSQL
- Vector DB: 9 options (ChromaDB, PGVector, Qdrant, Milvus, Elasticsearch, Pinecone, etc.)

**Notable features:**
- Auto-memory: secondary model extracts/creates/updates/deletes user memories asynchronously
- 9 vector DB backends for RAG
- Python Function Calling with built-in code editor
- Enterprise: SSO, RBAC, LDAP/AD, SCIM 2.0, audit logs
- Web search via 15+ providers

**Relevance to MemoryPalace:** The auto-memory pattern (LLM-based memory extraction) is highly transferable. Could implement this in Swift: after each conversation turn, optionally call a secondary model to extract key facts, store in SwiftData.

---

### LibreChat

**Positioning:** Closest to a ChatGPT-like experience with Artifacts, Code Interpreter, and Agents. 35k stars.

**Tech stack:** React + TypeScript full-stack, MongoDB + Redis.

**Memory system (most sophisticated structured approach):**
- Memory agent runs at start of each request, injecting stored context
- Post-completion memory extraction from conversation
- Structured key/value storage (not raw conversation dumps)
- Configurable `messageWindowSize` for memory analysis window
- Users can manually add/edit/remove memories
- 2026 roadmap: intelligent context compression

**Relevance to MemoryPalace:** The key/value memory system is the most relevant pattern. It avoids the complexity of vector databases by using LLM intelligence to decide what to remember. Implementation: `MemoryEntry(key: String, value: String, source: ConversationID, createdAt: Date)` in SwiftData.

---

### LobeChat

**Positioning:** Most polished UI/UX in open-source space. 74k stars. Massive plugin ecosystem (10k+ MCP plugins).

**Tech stack:** Next.js + Zustand + tRPC + Drizzle (modern "best practices" TypeScript).

**Architecture patterns:**
- Hybrid routing: Next.js App Router for static + React Router DOM for SPA
- 5-step feature dev: Routing → Data Structure → Zustand Store → Page Display → Function Binding
- Plugin architecture: declares `url`, `name`, `description`, `parameters` (JSON Schema) → sent as Function Call
- EdgeRuntime API layer between frontend and AI providers

**Unique features:**
- Branch conversations (fork from any message)
- Agent Market + Plugin Market
- Multi-agent collaboration
- Knowledge Base with RAG

**Relevance to MemoryPalace:** Branch conversations require tree-based message storage (not linear). The plugin architecture using JSON Schema is a clean extensibility model. The Zustand-like state management translates well to SwiftUI's `@Observable` pattern.

---

## Native macOS/iOS Apps (Closest References)

### Enchanted (5.9k stars)
- **100% Swift/SwiftUI**, Apache 2.0
- Covers iOS, macOS, visionOS, watchOS (most complete Apple ecosystem coverage)
- Ollama-only (limits provider reach)
- macOS Spotlight integration
- Best reference for multi-platform Apple app architecture

### macai (843 stars)
- **Swift (99.7%) + SwiftUI + AppKit**, Apache 2.0, macOS only
- 8+ providers (OpenAI, Anthropic, Gemini, xAI, Perplexity, Ollama, OpenRouter)
- **iCloud Sync** across devices (native Apple advantage)
- Apple Keychain for API key security
- Optimized local search across thousands of chats
- Best reference for multi-provider SwiftUI architecture

### Warden (225 stars)
- **100% SwiftUI** (no AppKit fallbacks), Apache 2.0, macOS only
- 8+ providers, multi-model comparison (up to 3 simultaneously)
- MCP agent integration
- Liquid Glass support (macOS 26)
- <150MB RAM, instant launch
- Purest SwiftUI reference implementation, newest entrant (March 2026)

### BoltAI (Commercial)
- SwiftUI + AppKit, macOS (+ iOS in progress)
- AI Commands: Template + Agent + Post-process + Preview Layout
- Global shortcut for instant access from any app
- Most polished commercial native macOS AI app
- Best reference for "professional tool" UX beyond chat window

---

## Cross-Cutting Patterns

### Memory/Context Management Approaches

| Approach | Used By | Complexity | Effectiveness |
|----------|---------|------------|---------------|
| **LLM-extracted key/value** | LibreChat, Open WebUI | Medium | High — structured, queryable |
| **Summarization** | SillyTavern | Low | Medium — lossy compression |
| **Vector RAG** | Open WebUI, LobeChat, Msty | High | High — semantic retrieval |
| **Keyword-triggered lore** | SillyTavern (World Info) | Low | Medium — manual but predictable |
| **Conversation branching** | RikkaHub, LobeChat, Msty | Medium | N/A — different problem (exploration, not memory) |

**Recommendation for MemoryPalace:** Start with LLM-extracted key/value (LibreChat pattern) — simplest to implement in SwiftData, no vector DB needed. Add summarization as second layer. Consider RAG later if needed.

### Multi-Provider Abstraction Patterns

Three approaches found in the wild:

1. **OpenAI-format normalization** — All calls normalized to OpenAI chat completion format. Simple but lossy (provider-specific features lost). Used by: NextChat, ChatBox, BetterChatGPT.

2. **Provider-specific adapters with unified protocol** — Each provider has a dedicated adapter handling its API format, auth, and streaming. A unified interface sits above. Used by: LibreChat, LobeChat, Open WebUI, RikkaHub.

3. **External gateway delegation** — Use LiteLLM or OpenRouter as a single endpoint. Simplest but adds dependency. Used as option by: several projects.

**Recommendation for MemoryPalace:** Approach #2. Define a Swift protocol:
```swift
protocol AIProvider {
    func complete(_ messages: [Message], config: ModelConfig) async throws -> Response
    func stream(_ messages: [Message], config: ModelConfig) -> AsyncThrowingStream<StreamChunk, Error>
    func listModels() async throws -> [Model]
}
```
Implement per-provider conformances (OpenAI, Anthropic, Google, Ollama, etc.).

### Chat UI Patterns (2026 State of the Art)

| Pattern | Standard Solution | SwiftUI Approach |
|---------|-------------------|-----------------|
| Streaming render | Token-by-token with buffer | `AsyncStream` + `@State` buffer + debounced render |
| Markdown | react-markdown / remark-gfm | cmark-gfm or AttributedString |
| Code blocks | Shiki syntax highlighting | Splash or custom AttributedString |
| LaTeX | KaTeX / MathJax | MathJax via WKWebView or LaTeXSwiftUI |
| Mermaid diagrams | mermaid.js | WKWebView with mermaid.js |
| Message branching | Tree-based storage | SwiftData with parent-child MessageNode |
| Streaming markdown (hard problem) | Streamdown (Vercel) | Buffer incomplete blocks, render complete ones |

### Desktop Framework Comparison

| Framework | Bundle Size | RAM | Native Feel | Examples |
|-----------|-------------|-----|-------------|----------|
| **Electron** | 100-200MB | 200-500MB | Low | ChatBox, Msty |
| **Tauri** | 5-15MB | 50-150MB | Medium | NextChat, Jan |
| **Native SwiftUI** | 5-30MB | <150MB | Highest | macai, Warden, Enchanted |

Native SwiftUI advantages unavailable to web/Electron:
- iCloud Sync
- Apple Keychain
- Spotlight integration
- Shortcuts automation
- ShareSheet
- Menu bar presence
- Liquid Glass (macOS 26)
- On-device Foundation Models (macOS 26)
- Apple Silicon optimization
- visionOS / watchOS expansion

---

## Key Takeaways for MemoryPalace

1. **Closest architectural references:** macai (multi-provider SwiftUI), Warden (pure SwiftUI + MCP), Enchanted (Apple ecosystem breadth)

2. **Memory system:** Start with LibreChat's LLM-extracted key/value pattern. After each turn, optionally call a model to extract facts → store as `MemoryEntry` in SwiftData → inject relevant memories into system prompt. No vector DB needed initially.

3. **Provider abstraction:** Swift protocol-based adapters per provider. RikkaHub's `ProviderManager` factory pattern is a good reference.

4. **Chat storage:** Tree-based `MessageNode` model (like RikkaHub's Room schema) to support branching. JSONL export for interoperability.

5. **Character/persona import:** Support TavernCard V2 format (PNG with embedded JSON) for SillyTavern ecosystem compatibility.

6. **Native advantages to exploit:** iCloud Sync, Keychain, Spotlight, Shortcuts, ShareSheet, Foundation Models, Liquid Glass — these are moats no web/Electron competitor can replicate.

7. **Hardest SwiftUI problems to solve:** Streaming markdown rendering without flicker, and code block syntax highlighting. Consider a hybrid approach: AttributedString for simple markdown, WKWebView for complex blocks (code, LaTeX, Mermaid).
