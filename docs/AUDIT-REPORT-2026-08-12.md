# Code Audit Report — 2026-08-12

> Commissioned by Bunny, executed by Caelum (4x Opus 4.6 agents in parallel).
> **Read-only audit. No code was modified.**

## Summary

| Area | P0 | P1 | P2 | Report |
|------|----|----|----|----|
| Views (SwiftUI) | 8 | 7 | 13 | [audit-views.md](audit-views.md) |
| Services + ViewModels | 6 | 7 | 6 | [audit-services-viewmodels.md](audit-services-viewmodels.md) |
| Gateway (TS) | 3 | 6 | 11 | [audit-gateway.md](audit-gateway.md) |
| cc-bridge | 7 | 7 | 8 | [audit-cc-bridge.md](audit-cc-bridge.md) |
| **Total** | **24** | **27** | **38** | |

## Top 10 — Fix These First

1. **Pervasive `try? context.save()`** — 15+ call sites across 8 files silently lose CoreData writes. Most critical: HealthSyncService (drug sync duplicates) and ConversationViewModel+Chat (conversation data loss). [Services+ViewModels P0]

2. **Global uncaughtException/unhandledRejection swallowed** — cc-bridge hub catches everything, logs nothing. Debug black hole. [cc-bridge P0 #1]

3. **`/mcp` endpoint skips token auth** — hub misconfigured to non-loopback allows unauthenticated reply injection. [cc-bridge P0 #3]

4. **desire.ts `saveMemory` call signature wrong** — passes positional args but function expects object. Silently produces garbage data. [Gateway P0 #1]

5. **desire.ts vs sync.ts dual query logic** — two different query patterns for the same data, App may not see new records. [Gateway P0 #2]

6. **VitalsClient.merge() fabricates empty meds data** — when server returns no meds, creates empty array that overwrites local truth. [Services+ViewModels P0]

7. **Memory system `try?` swallows write failures** — AddMemorySheet, MemoryPanelView, MemorySettingsTab all silently fail on save. User loses memories with no feedback. [Views P0]

8. **CareView max() dual-source bandaid** — known architectural debt, food/water data from two sources reconciled with max(). [Views P0]

9. **execSync command injection surface** — hub.ts iconv uses shell template literal in execSync. Currently sanitized by safeName, but fragile. [cc-bridge P0 #2]

10. **claude-p.ts stderr swallowed** — all Claude process errors silently dropped. [Gateway P0 #3]

## Cross-Cutting Patterns

**The #1 systemic issue is silent failure.** `try?`, empty `catch {}`, `guard else return` with no logging — this pattern appears in every layer. A single fix pattern (add error logging/user feedback to all catch sites) would resolve ~60% of P0 findings.

**What's well-engineered:** GatewayCache, ToolCallLoop safety cap, WebSocket dedup, prompt caching breakpoints, hysteresis compression, CardFlowView render window optimization. These don't need touching.

## Detailed Reports

- [Views](audit-views.md) — SwiftUI performance, dead views, silent failures
- [Services + ViewModels](audit-services-viewmodels.md) — data flow, dual truth, threading
- [Gateway](audit-gateway.md) — dead code, desire.ts bugs, memory modules
- [cc-bridge](audit-cc-bridge.md) — auth, queue overflow, APNS connection reuse

## Notes

- `calendar_markers` and `persona_state` tables may not exist in Supabase — confirm before relying on related features
- `memory/` modules are all wired up (controlled by `BRAIN_ENABLED` flag), not dead as initially suspected
- No crash-risk force unwraps or infinite loops found
- ~45 utility files in Services/ not deeply audited (sticker renderers, importers, music player, etc.) — lower risk
