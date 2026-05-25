# Persistent memory systems for AI chat applications

**The most effective AI chat memory systems extract atomic facts via LLM tool calls, store them in tiered schemas with temporal metadata, and inject them using hybrid keyword-plus-semantic scoring** — not the naive "dump everything" approach that ChatGPT still uses. Across open-source projects (LibreChat, Open WebUI, MemGPT/Letta) and production systems (ChatGPT, Claude), a clear design consensus is emerging: delegate memory management decisions to the LLM itself via structured tool calls, use the Add/Update/Delete/No-op (AUDN) pattern for reconciliation, and combine multiple retrieval signals (keyword relevance, recency, semantic similarity) rather than relying on any single method. For a native macOS SwiftUI + SwiftData application, the optimal path starts with pure keyword/recency matching and progresses through Apple's on-device `NLContextualEmbedding` to a full `sqlite-vec` vector index — each tier adding capability without requiring external services.

---

## 1. How production systems extract and manage memories

### LibreChat: agent-based tool-call extraction on every turn

LibreChat (merged June 2025, PR #7760) runs a **dedicated memory agent** concurrently with every chat request. This agent is a separate LLM call — not the conversation model — configured independently in `librechat.yaml` with its own provider, model (e.g., `gpt-4.1-mini`), and temperature (typically 0.3). The agent receives a sliding window of the last **5 messages** (configurable via `messageWindowSize`) plus all existing stored memories, and is given two tools:

- **`set_memory(key, value)`** — creates or overwrites a memory entry
- **`delete_memory(key)`** — removes an outdated entry

The decision logic is entirely LLM-driven. The agent sees existing memories in context and decides autonomously whether to create, update, or delete. Default instructions guide it to store explicitly stated preferences, ongoing projects, and objective facts, while deleting outdated or contradicted information. Memory categories are constrained via `validKeys` (e.g., `user_preferences`, `conversation_context`, `learned_facts`, `personal_information`). Each entry tracks token count, and a configurable `tokenLimit` (typically **2,000–3,000 tokens**) caps total memory size per user. The key limitation: LibreChat currently uses **full injection** — all memories are dumped into every request context, with no relevance-based retrieval. This works for dozens of memories but cannot scale to hundreds.

### Open WebUI: manual-first with vector-backed semantic retrieval

Open WebUI takes the opposite approach. Its **core memory system has no automatic extraction** — users manually add memories through Settings → Personalization → Memory or via API. Memories are stored in a **dual architecture**: a relational database (SQLAlchemy, typically SQLite or PostgreSQL) for the canonical record, and **ChromaDB** (or another vector backend) for semantic retrieval. At chat time, the `chat_memory_handler` uses the user's last message as a search query against their personal vector collection, retrieving the **top 3** most semantically similar memories. These are formatted in `<memory_user_context>` XML tags with timestamps and injected into the system prompt.

The community has filled the auto-extraction gap with filter plugins. The most notable — **Auto Memory by @nokodo** and **Adaptive Memory v3** — use a separate LLM call to analyze recent messages and output structured JSON actions (`add`, `update`, `delete`), checking existing memories via vector similarity before storing. Some plugins add **LLM-based reranking** as a second pass after vector retrieval, significantly improving relevance at the cost of an additional inference call.

### ChatGPT: full-dump injection with no vector retrieval

ChatGPT's memory architecture, as reverse-engineered by multiple security researchers, is surprisingly simple. It uses a `bio` tool — invoked by the same conversation model — to persist single-sentence facts like `"- User loves dogs."` with timestamps. **96% of memories are created proactively** by the model without explicit user request. All saved memories (capped at roughly **100 blocks / ~1,200–1,400 words**) are injected into every single prompt with no semantic filtering. There is no RAG, no vector database, no selective retrieval.

Since April 2025, ChatGPT also maintains a six-layer context injection for paid users:

| Layer | Content | Update frequency |
|-------|---------|-----------------|
| Model Set Context | Saved memories (bio tool entries) | Real-time during conversation |
| Assistant Response Preferences | Style/formatting preferences | Periodic, by OpenAI backend |
| Notable Past Topics | High-level topic summaries | Periodic, by OpenAI backend |
| Helpful User Insights | Personal facts (name, job, expertise) | Periodic, by OpenAI backend |
| Recent Conversations | ~40 most recent chats (user messages only) | Continuously |
| User Interaction Metadata | Device, timezone, plan type | Per-request |

**When memory is full, no automatic eviction occurs** — users must manually delete entries. A newer auto-management feature can deprioritize less-relevant memories (shown grayed out) but does not delete them. The hidden "User Knowledge Memories" layer — dense AI-generated summaries of conversation history — is not visible in settings and not directly editable, raising transparency concerns that critics like Simon Willison and MemGPT creator Charles Packer have flagged as "context rot."

### Claude: transparent file-based memory with async consolidation

Anthropic's Claude uses a distinctive **file-based approach**. Claude Code stores memory in plain Markdown files (`CLAUDE.md`) organized hierarchically (enterprise → project → user → auto-generated), loaded fully into context each session. Claude.ai maintains a summarized memory updated in **daily synthesis cycles** with 12–24 hour propagation. A unique feature called **Auto Dream** runs asynchronous consolidation — reviewing memory entries, strengthening relevant information, removing outdated entries, and reorganizing scattered notes into indexed topic files through a four-phase Orient → Gather → Synthesize → Write process.

---

## 2. Memory schema design: what fields actually matter

### Cross-project schema comparison

Simple key/value is insufficient for production systems. Analysis across seven open-source projects reveals a clear hierarchy of schema sophistication:

| Field | Open WebUI | LibreChat | SillyTavern Lorebook | MemGPT/Letta | Mem0 | Zep |
|-------|-----------|-----------|---------------------|-------------|------|-----|
| Unique ID | UUID | ObjectId | numeric uid | UUID | UUID | UUID |
| Content text | ✅ | ✅ (key + value) | ✅ (+ keywords) | ✅ (labeled blocks) | ✅ (natural language facts) | ✅ (graph triples) |
| Timestamps | created/updated | created/updated | implicit (message order) | full message timestamps | created/updated | **valid_at / invalid_at** |
| Embedding vector | ✅ (ChromaDB) | ❌ | optional (vectors ext.) | ✅ (archival) | ✅ (core) | ✅ + graph structure |
| Categories/labels | ❌ | ✅ (validKeys) | groups, comments | block labels (human, persona) | ❌ fixed | entity/relationship types |
| Confidence score | ❌ | ❌ | probability (0–100) | ❌ | relevance scoring at retrieval | edge confidence |
| Source tracking | ❌ | ❌ | character/chat filter | agent_id, run_id | user_id, agent_id | episode source |
| Decay/expiry | ❌ | ❌ | cooldown + sticky timers | context eviction | ❌ | temporal bounds |
| Token count | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Activation keywords | ❌ | ❌ | ✅ (primary + secondary, regex) | ❌ | ❌ | ❌ |

**SillyTavern's lorebook schema is the richest**, with 30+ fields including probability-based activation, sticky/cooldown/delay timers, regex keyword matching, selective logic (AND_ANY, AND_ALL, NOT_ANY, NOT_ALL), recursive scanning controls, and character-specific filtering. This reflects its use case — narrative roleplay demanding fine-grained context injection control.

### Academic literature consensus on optimal schemas

Research papers converge on several design principles. **Zep's temporal knowledge graph** (Rasmussen et al., 2025) demonstrates that `valid_at`/`invalid_at` temporal bounds dramatically improve multi-session coherence — ChatGPT notably underperforms on temporal reasoning because it strips timestamps. **Mem0** (Chhikara et al., 2025) showed that structured fact extraction with metadata achieves **26% better accuracy** than OpenAI's approach on the LOCOMO benchmark. **A-MEM** (2025) builds autonomous "notes" with contextual descriptions, inter-memory links, and evolution tracking, outperforming fixed-workflow approaches across six foundation models. The **Memoria** framework (Sarin et al., 2025) combines session summaries with weighted knowledge graph user profiles, using recency-weighted triplet scoring.

The consensus: **tiered memory is essential** (all top-performing systems use 2–3 tiers), **temporal awareness significantly improves quality**, and **hybrid approaches combining vector similarity + structured metadata filtering + optional graph relationships dominate pure approaches**.

### Recommended memory table schema for SwiftData

```swift
import SwiftData
import Foundation

@Model
class Memory {
    // === Core Fields ===
    @Attribute(.unique) var id: UUID
    var content: String                    // The atomic fact or preference
    var category: MemoryCategory           // Enum: preference, fact, relationship, goal, context
    var createdAt: Date
    var updatedAt: Date

    // === Retrieval Optimization ===
    var keywords: [String]                 // Pre-extracted keywords for fast BM25/keyword matching
    var tokenCount: Int                    // For token budget management during injection
    var embeddingData: Data?               // Optional: 512-dim float array from NLContextualEmbedding

    // === Lifecycle Management ===
    var accessCount: Int                   // Reinforcement signal — how often retrieved
    var lastAccessedAt: Date               // For recency scoring
    var decayWeight: Double                // 0.0–1.0, decreases over time, boosted on access
    var validUntil: Date?                  // Optional temporal bound (e.g., "working on project X")

    // === Provenance ===
    var sourceConversationId: UUID?        // Which conversation produced this memory
    var extractedBy: String                // Model that extracted it (e.g., "gpt-4.1-mini")
    var isUserExplicit: Bool               // User said "remember this" vs auto-extracted

    // === Relationships ===
    var parentId: UUID?                    // For memory hierarchies (summary of summaries)
    var userId: UUID                       // Multi-user support
}

enum MemoryCategory: String, Codable {
    case preference     // "Prefers dark mode", "Likes concise answers"
    case fact           // "Works at Acme Corp", "Has a dog named Max"
    case relationship   // "Manager is Sarah", "Collaborates with design team"
    case goal           // "Learning Rust", "Building a macOS chat app"
    case context        // "Currently debugging auth module" (time-bounded)
}
```

This schema supports all three retrieval tiers (keyword, recency-weighted, and semantic), explicit lifecycle management (decay weight, access count, temporal bounds), and full provenance tracking. The `embeddingData` field is optional — the schema works without it for the lightweight tier.

---

## 3. A directly usable memory extraction prompt

Based on analysis of Mem0's AUDN pattern, LibreChat's agent instructions, and LangMem's extraction approach, here is a production-ready extraction prompt:

```
You are a memory management system. Analyze the recent conversation and
manage the user's memory store by calling the appropriate tools.

## Current Memories
{{existing_memories}}

## Rules
1. Extract ATOMIC FACTS — each memory should be a single, independent
   statement (e.g., "Prefers Python over JavaScript" not "Has various
   programming preferences").
2. Categorize each memory: preference, fact, relationship, goal, or context.
3. For each piece of new information, decide ONE action:
   - SET: New information not covered by existing memories
   - SET (update): Information that refines, corrects, or supersedes an
     existing memory — use the SAME key to overwrite it
   - DELETE: Existing memory is explicitly contradicted or outdated
   - NO ACTION: Information already adequately captured, or not worth storing
4. Only store information the USER explicitly shares or that is clearly
   implied by their statements. Never infer sensitive information.
5. Use concise, third-person statements: "User prefers..." not "You prefer..."
6. Include temporal qualifiers when relevant: "User is currently working on..."
7. When new info contradicts old info, DELETE the old memory and SET the
   corrected version.
8. Do NOT store: trivial chitchat, one-time queries, information the user
   is asking about (not stating), or sensitive health/financial details
   unless explicitly requested.

## Output
Call `set_memory` or `delete_memory` tools as needed. If no memory
operations are warranted, do nothing.
```

The key design decision this prompt encodes: **the LLM itself makes all create/update/delete decisions** rather than rule-based code. This is the approach validated by Mem0 (+26% over OpenAI on LOCOMO), LibreChat, and MemGPT/Letta. The existing memories are injected so the LLM can detect conflicts and redundancies.

---

## 4. Memory injection: from full dump to hybrid retrieval

### Three injection strategies with clear tradeoffs

**Full injection** (used by ChatGPT and LibreChat today) dumps all memories into the system prompt every time. This is deterministic, simple, and never misses relevant context — but wastes tokens at scale and cannot exceed roughly **50–100 memories** before degrading response quality through context pollution. ChatGPT formats memories as bullet points (`- User prefers Python for scripting.`); LibreChat uses key/value JSON. Both place memories after system instructions but before conversation history.

**Relevance-based retrieval** (used by Open WebUI) searches for the top-k most relevant memories using vector similarity, injecting only a subset. This scales to thousands of memories but risks missing relevant context and adds retrieval latency. Open WebUI defaults to **k=3**, formatted in XML tags with timestamps.

**Self-directed retrieval** (used by MemGPT/Letta) gives the agent explicit tools to search its own memory, deciding what to retrieve based on conversational need. This is the most flexible approach but adds inference overhead for each retrieval decision.

### Lightweight relevance matching without vector databases

For the initial implementation tier, a hybrid BM25 + recency + frequency scoring system provides surprisingly strong results with zero dependencies:

```swift
func hybridScore(query: String, memory: Memory, corpus: [Memory]) -> Double {
    // BM25 keyword relevance (k1=1.5, b=0.75)
    let keywordScore = bm25(query: tokenize(query), memory: memory, corpus: corpus)

    // Exponential recency decay (half-life ~7 days)
    let daysSinceAccess = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
    let recencyScore = exp(-0.1 * daysSinceAccess)

    // Log-scaled access frequency
    let maxAccess = corpus.map(\.accessCount).max() ?? 1
    let frequencyScore = log(1.0 + Double(memory.accessCount)) /
                         log(1.0 + Double(maxAccess))

    // Weighted combination
    return normalize(keywordScore) * 0.50
         + recencyScore              * 0.25
         + frequencyScore            * 0.15
         + (memory.isUserExplicit ? 0.10 : 0.0)  // Boost explicit memories
}
```

**SQLite FTS5**, built into every Apple platform, provides production-quality BM25 ranking out of the box via its `bm25()` function. This runs in sub-millisecond time on 10,000+ memories and requires no additional dependencies.

### Local vector solutions for the macOS/iOS stack

For semantic search, three viable options exist in the Apple ecosystem:

**Apple `NLContextualEmbedding`** (iOS 17+ / macOS 14+) provides BERT-based, context-aware **512-dimensional embeddings** on iOS and **768-dimensional on macOS**, supporting 27 languages across Latin, Cyrillic, and CJK scripts. It runs on Apple Neural Engine with no external dependencies, though it requires a one-time ~100MB model download per script family and returns per-token vectors that must be mean-pooled for sentence embeddings. The `NaturalLanguageEmbeddings` Swift package wraps this with automatic algorithm selection: brute-force cosine similarity via `vDSP` for under 100 items, optimized matrix-vector multiplication for larger collections.

**`sqlite-vec`** (by Alex Garcia, Mozilla Builders) is the recommended vector storage extension — pure C, zero dependencies, MIT/Apache-2.0 licensed, with pre-compiled `.xcframework` for iOS since v0.1.2. It uses virtual tables (`CREATE VIRTUAL TABLE vec_items USING vec0(embedding float[512])`) with KNN queries, supports float32/int8/binary vectors, and leverages SIMD acceleration (NEON on ARM). Currently brute-force only (no ANN indexing), but highly optimized for up to ~100K vectors. Note: **`sqlite-vss` is deprecated** in favor of `sqlite-vec`.

**SwiftData integration pattern**: Since SwiftData does not support loading SQLite extensions directly, maintain a **parallel SQLite database** for vector operations alongside SwiftData for relational metadata. Link records by UUID between the two stores. This is the cleanest architecture:

```swift
// SwiftData for structured memory metadata
@Model class Memory { ... }  // As defined in schema above

// Separate SQLite connection for sqlite-vec
class VectorStore {
    func upsert(id: UUID, embedding: [Float]) { /* vec0 INSERT */ }
    func search(query: [Float], limit: Int) -> [(id: UUID, distance: Float)] { /* vec0 KNN */ }
}

// Coordinator links both
class MemoryManager {
    let modelContext: ModelContext
    let vectorStore: VectorStore
    let embeddingService: NLContextualEmbedding?
}
```

---

## 5. Memory lifecycle: decay, merging, and conflict resolution

### Forgetting mechanisms that actually improve quality

Counter-intuitively, **retaining fewer memories improves performance**. MemoryBank (AAAI 2024) implements Ebbinghaus's forgetting curve: `R = e^(-t/S)`, where retention R decays exponentially over time t, with strength S incremented each time a memory is accessed. This results in retaining only ~10% of memories — matching research that humans recall roughly 10% of conversations. LUFY extends this with six psychological metrics (emotional valence, information density, etc.) rather than simple retrieval count, and outperformed both naive RAG and MemoryBank in user studies across four rounds with 17 participants.

For a SwiftData implementation, model decay as a `decayWeight` field updated on each access:

```swift
// On memory access:
memory.decayWeight = min(1.0, memory.decayWeight + 0.2)
memory.lastAccessedAt = Date()
memory.accessCount += 1

// Periodic decay (e.g., daily background task):
let daysSinceAccess = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
memory.decayWeight *= exp(-0.1 * daysSinceAccess)

// Eviction threshold:
if memory.decayWeight < 0.05 && !memory.isUserExplicit {
    // Candidate for archival or deletion
}
```

### Conflict resolution: the AUDN pattern

Mem0's Add/Update/Delete/No-op cycle is the industry best practice. For each extracted fact, the system performs semantic search against existing memories, then the LLM decides:

- **ADD**: Genuinely new information → create with new ID
- **UPDATE**: Refined or changed information about the same topic → overwrite, preserve old value for audit
- **DELETE**: Explicit contradiction → remove old memory (e.g., "Dislikes cheese pizza" contradicts "Loves cheese pizza")
- **NONE**: Already adequately captured or not worth storing

The critical insight: **this logic is LLM-delegated, not rule-based**. Brittle if/else chains cannot handle the semantic nuance of determining whether "likes cheese pizza" and "loves cheese pizza" are duplicates (NONE) or meaningful updates (UPDATE). Mem0 validates this approach with the strongest LOCOMO benchmark results among comparable systems.

### Memory consolidation and deduplication

MemGPT/Letta handles consolidation through **recursive summarization** — when the context window fills, conversation history is compacted into summary blocks, with originals remaining searchable via `conversation_search`. SillyTavern's Memory Books extension implements **multi-tier consolidation**: scene-level memories are periodically merged into higher-level chapter summaries. Claude's Auto Dream runs asynchronous four-phase consolidation during idle periods.

For deduplication, the pattern across all production systems is consistent: **vector similarity search before storage**. Each extracted fact is compared against existing memories; if cosine similarity exceeds a threshold (typically **0.75–0.85**), the LLM decides whether it's a true duplicate (skip) or an update (merge).

---

## 6. Effectiveness: summarization vs key/value vs RAG

### Benchmark data strongly favors structured extraction

On the LOCOMO benchmark (the standard evaluation for conversational memory, ACL 2024), structured approaches dominate:

| System | LOCOMO Score | Approach | Token efficiency |
|--------|-------------|----------|-----------------|
| Memori | 81.95% | Semantic triples + summaries | ~1,294 tokens/query (~5% of full context) |
| Mem0 | 66.9% | Atomic fact extraction + AUDN | 90% fewer tokens vs full-context |
| OpenAI Memory | 52.9% | Bio tool entries (full dump) | Low efficiency at scale |
| Naive RAG | Lower | Chunk retrieval | Varies |
| MemoryBank | ~Naive RAG | Retrieval-count forgetting | Moderate |

**Rolling summarization** (SillyTavern-style) suffers from compounding degradation. Community consensus is stark: "one bad generation can completely ruin the summary," and smaller models produce unreliable summaries that lose critical mid-conversation details. The alternative — per-message summarization — is more robust but expensive. **Key/value extraction** provides precise, auditable, CRUD-manageable atomic facts but can miss implicit context. **RAG/vector retrieval** handles unlimited history and scales well but retrieves chunks that may be "relevant to the query" without being "relevant to the user" — a fundamental distinction.

**Hybrid approaches consistently outperform any single method.** The practical winner combines atomic fact extraction (for user preferences and explicit facts) with episodic summaries (for conversational context) and optional vector retrieval (for long-term history). This is the architecture Mem0, LangMem, and Memori all converge on independently.

### What users actually report

ChatGPT memory draws significant criticism for "**context rot**" — the slow buildup of stale preferences, errors, and contradictions that degrades output quality. Users report memories not updating even after explicit correction, and the hidden "User Knowledge Memories" layer influencing responses in unexpected ways. SillyTavern users consistently cite **summary degradation** over long chats as the primary pain point, driving development of multiple community extensions (Message Summarize, ReMemory, Memory Books, Timeline Memory) that address specific failure modes.

---

## 7. Tiered architecture for SwiftUI + SwiftData

### Tier 1 — Lightweight (zero dependencies, ship in days)

**Storage**: SwiftData `@Model` with the schema above (excluding `embeddingData`). **Retrieval**: SQLite FTS5 with `bm25()` ranking + recency/frequency weighting in Swift. **Injection**: Full dump for ≤50 memories; BM25-scored top-20 for larger stores. **Extraction**: Single LLM call per conversation turn using the extraction prompt above, with `set_memory`/`delete_memory` tool definitions. **Lifecycle**: Simple timestamp-based recency decay; manual user deletion. **Cost**: One additional LLM call per turn (use a cheap model like `gpt-4.1-mini`). **Scales to**: ~200 memories before retrieval quality degrades.

### Tier 2 — Medium (Apple-native semantic search)

Everything in Tier 1, plus: **Embeddings**: `NLContextualEmbedding` (512-dim on iOS, 768-dim on macOS) stored as `Data` blobs in SwiftData. **Retrieval**: Hybrid BM25 + cosine similarity using `vDSP` from the Accelerate framework. **Injection**: Score-ranked top-k memories with configurable token budget (default 2,000 tokens). **Lifecycle**: Ebbinghaus-inspired decay weights, access count reinforcement, periodic low-weight eviction. **Dependencies**: NaturalLanguageEmbeddings Swift package (optional convenience wrapper). **Scales to**: ~2,000 memories with good relevance.

### Tier 3 — Heavyweight (full vector index + graph potential)

Everything in Tier 2, plus: **Vector storage**: `sqlite-vec` in a parallel SQLite database, linked to SwiftData by UUID. **Retrieval**: sqlite-vec KNN query → candidate set → BM25 reranking → optional LLM reranking. **Injection**: Token-budgeted injection with category-based prioritization (user-explicit memories always included). **Extraction**: AUDN reconciliation — vector-search existing memories before each extraction decision. **Lifecycle**: Multi-tier storage (core always-loaded + archival searchable), temporal validity bounds (`validUntil`), automated consolidation sweeps. **Dependencies**: sqlite-vec `.xcframework`, NaturalLanguageEmbeddings. **Scales to**: 100K+ memories with sub-10ms retrieval.

### Which tier to start with

**Start with Tier 1 and ship it.** ChatGPT — the world's most-used AI chat product — still uses full injection with no vector retrieval, proving that simple approaches work at meaningful scale. The extraction prompt and AUDN reconciliation logic provide the highest-leverage improvement regardless of retrieval sophistication. Add Tier 2 when users accumulate more than ~100 memories and keyword matching starts missing semantically relevant results. Add Tier 3 only if you need to support long-running agents with thousands of memory entries or complex multi-hop retrieval. Each tier is architecturally additive — the schema above supports all three without migration, and the parallel-database pattern for sqlite-vec integrates cleanly alongside SwiftData.

---

## Conclusion: practical design principles that cut across all tiers

The most important insight from this research is that **memory quality matters far more than memory quantity**. MemoryBank's finding that retaining only 10% of memories (the most important ones) actually improves performance should guide every design decision. Extract atomic facts, not narrative summaries. Delegate all create/update/delete decisions to the LLM via the AUDN pattern — it handles semantic nuance that brittle rules cannot. Always store timestamps; ChatGPT's poor temporal reasoning traces directly to stripping them. Implement user transparency and control — every user-facing memory should be viewable, editable, and deletable. Budget tokens explicitly (track `tokenCount` per memory, enforce per-user limits). And above all, start simple: the gap between "no memory" and "basic keyword-matched memory with AUDN extraction" is far larger than the gap between that and a full vector retrieval system.