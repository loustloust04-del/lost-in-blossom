# UI Consistency Review — MemoryPalace Views

Date: 2026-07-14
Scope: 105 SwiftUI files under `MemoryPalace/Views/`
Method: static analysis (grep-based pattern counts + spot reads). No runtime inspection.

## Summary

The codebase has a real design-token system (`ThemeTokenSet` in `Models/AppTheme.swift`, exposed via the static `Theme` enum in `Utils/Theme.swift`) and it is well adopted for color: **1,659 `Theme.*` token references** across the Views tree. The main consistency gaps are (1) a long tail of hardcoded RGB/hex colors bypassing the theme system, (2) near-total reliance on fixed font sizes instead of Dynamic Type text styles, (3) an unconstrained spacing/radius scale, and (4) small shared components that exist but are unused or duplicated.

Ratings per category: Color **B**, Fonts **D**, Spacing **C**, Navigation **A-**, Component reuse **C+**.

---

## 1. Color usage

### What's good
- Semantic token system with 11 tokens (`mainBg`, `sidebarBg`, `userBubble`, `assistantBubble`, `accent`, `textPrimary`, `textSecondary`, `textMuted`, `favorite`, `danger`, `branchIndicator`), light/dark variants, user-editable themes.
- Adoption is high: 1,659 uses. Top tokens: `textMuted` (583), `branchIndicator` (316), `mainBg` (221), `textPrimary` (219), `textSecondary` (143).
- No asset-catalog color strings (`Color("...")` count: 0) — one source of truth.

### Issues
1. **Hardcoded colors bypass the theme.** 67 `Color(red:...)` and 29 `Color(hex:...)` literals across 21 files, e.g.:
   - `MemoryPanelView.swift` mixes `Theme.*` with raw literals in the same view — lines 119/132/207/471/477 hardcode `Color(hex: 0xD4A574)` (amber) and `Color(red: 0.6, green: 0.65, blue: 0.7)` (cool gray) as de-facto "hot/cold memory" semantic colors. These are theme-invisible: they will not adapt when the user edits a theme, and the amber is repeated 4+ times as a magic number.
   - `CardFlowView.swift:1504` — `Color(red: 155/255, green: 142/255, blue: 126/255)`, visually close to `textMuted` but not it.
   - Heavy offenders: `StickerView.swift`, `StickerStyleSheet.swift`, `StickerKeyboardPanel.swift`, `StickerLibraryView.swift`, `NoteStickerEditor.swift`, `DrawingBoardSheet.swift`, `ConsoleView.swift`, `CCTerminalPanelView.swift`, `GatewayConsoleView.swift`.
2. **`Theme.branchIndicator` is overloaded.** 316 uses is far too many for a token named "branch indicator" — it is being used as a general-purpose green accent (more than 3x the real `accent` token at 81 uses). The token name no longer describes its role; either rename it (e.g. `accentStrong` / `success`) or split usages.
3. **Sporadic UIKit semantic colors** (16 uses of `Color(.system...)` / `UIColor.*`) — these follow system dark mode, not the app theme, so they can disagree with a custom theme.
4. **47 uses of `.primary`/`.secondary` foreground styles** — same problem: system-scheme-driven, not theme-driven. Acceptable inside stock sheets, wrong inside themed chat surfaces.

### Recommendation
- Add the missing semantic tokens that the hardcoded colors are standing in for (`warning`/`memoryHot`, `memoryCold`), then sweep the 96 literals.
- Rename or split `branchIndicator`.
- Ban `Color(red:)`/`Color(hex:)` in Views via a lint rule (SwiftLint `custom_rules` regex), whitelisting `ThemeEditorView`/`DrawingBoardSheet` where arbitrary colors are the feature.

## 2. Font usage

This is the weakest area.

- **1,302 hardcoded `.system(size:)` calls** vs **~94 semantic text styles** (`.caption` 53, `.caption2` 27, a handful of `.headline`/`.callout`/`.title3`). Ratio ≈ 14:1.
- **25 distinct sizes** in use, including fractional oddities: `8, 8.5, 9, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15, 16, 17, 18, 19, 20, 22, 24, 26, 28, 30, 32, 48`. Sizes 11/12/13/14 dominate (~340 combined) but with inconsistent weight pairings — e.g. "section header" styling appears as `size: 11, weight: .semibold` (12x), `size: 11, weight: .medium` (14x), `size: 12, weight: .medium` (21x), `size: 12, weight: .semibold` (7x), `size: 13, .medium/.semibold` (13x) for visually equivalent roles.
- `Utils/Theme.swift` has **no font helpers at all** — the token system covers color only, so every view invents its own type scale.
- Consequence: near-zero Dynamic Type support across the app.

### Recommendation
Add a `Theme.Font` (or `Font` extension) layer with ~6 roles (`pageTitle`, `sectionHeader`, `body`, `label`, `caption`, `micro`), ideally built on `.system(_:design:)` relative styles or `UIFontMetrics` scaling, and migrate the 11–14pt cluster first (that's ~65% of all hardcoded sizes).

## 3. Spacing, padding, corner radius

- 822 numeric `.padding(...)` calls, only 3 bare `.padding()`. Values span `0–40` with **20+ distinct values**, including off-scale ones: 1, 2, 3, 5, 7, 9, 11, 14, 18, 30. The 4-pt grid (4/8/12/16/20) accounts for ~55%; the rest is ad hoc.
- `spacing:` shows the same spread (6 and 8 are both "default-ish" at 128 vs 120 uses; 3 appears 42 times).
- Corner radius: 15 distinct values (1, 1.5, 2, 3, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 30). 6/8/10/12 all compete for "standard card" duty; 22 (14 uses) appears to be the capsule-ish control radius.
- No spacing/radius constants exist anywhere in `Utils/Theme.swift`.

### Recommendation
Define `Theme.Spacing` (xs=4, s=8, m=12, l=16, xl=20) and `Theme.Radius` (control=8, card=12, capsule=22). Don't mass-migrate; adopt in new code and when touching files, but do collapse the 6-vs-8 and 8-vs-10 ambiguity in the highest-traffic views (`CardFlowView`, `SettingsView`, panels).

## 4. Navigation patterns

Largely consistent — the best category.

- `NavigationStack` used in 31 files; exactly **one** legacy `NavigationView` remains: `Components/TextSelectSheet.swift:9`. Trivial fix.
- Modals: 71 `.sheet` vs 4 `.fullScreenCover`, appropriate split.
- Dismissal is uniform: 46 `@Environment(\.dismiss)`, zero legacy `presentationMode`.
- Titles: 63 `.navigationTitle` with 62 `.navigationBarTitleDisplayMode(.inline)` — effectively a house rule, consistently applied.

### Recommendation
Replace the one `NavigationView`; consider a `.inlineNavigationTitle(_:)` convenience modifier since title+inline always travel together.

## 5. Component reuse vs duplication

### Good
- Only 2 duplicate struct names across 105 files (`TerminalRepresentable`, `PlatformBookReaderWebView` — both platform-conditional pairs, likely intentional).
- `.buttonStyle(.plain)` (292 uses) is the clear house style.
- `FlowLayout`, `ToastCenter`/`GlobalToastOverlay` are genuinely shared.

### Issues
1. **Dead component:** `Views/GlassBackButton.swift` is referenced by zero other files. Either adopt it or delete it.
2. **Single-consumer "shared" component:** `ScrollToBottomButton` is only used by `CardFlowView` — fine, but it lives at Views root implying general reuse.
3. **Duplicated `Color(hex: String)` initializers**, in three places with *different semantics*:
   - `Utils/Theme.swift:69` — `init(hexString:)` (canonical)
   - `CreateGroupChatView.swift:278` — failable `init?(hex: String)`
   - `AnniversaryView.swift:217` — non-failable, silently black on bad input; the comment "如果项目里还没有" ("in case the project doesn't have one") confirms it was added blind. Consolidate on the `Utils/Theme.swift` version.
4. **No shared section-header / settings-row component** despite 13 settings tab/view files re-implementing visually identical headers (see the font-weight scatter in §2). One `SettingsSectionHeader` view would eliminate ~50 inline stylings.
5. `Views/Components/` contains only 3 files (all UIKit bridges); actual reusable SwiftUI pieces (`FlowLayout`, `ToastCenter`, `ScrollToBottomButton`, `GlassBackButton`, `ThemeBackgroundView`) sit loose at Views root. Move them under `Components/` for discoverability.

---

## Prioritized action list

1. **P1** — Delete or adopt `GlassBackButton`; replace the lone `NavigationView` (`TextSelectSheet.swift`). Trivial, zero-risk.
2. **P1** — Consolidate the three `Color(hex: String)` initializers onto `Utils/Theme.swift`.
3. **P2** — Add `memoryHot`/`memoryCold`/`warning` tokens; sweep the 96 hardcoded color literals (start with `MemoryPanelView`, sticker suite, console views).
4. **P2** — Introduce `Theme.Font` roles; migrate the 11–14pt cluster.
5. **P3** — `Theme.Spacing`/`Theme.Radius` constants; adopt incrementally.
6. **P3** — Extract `SettingsSectionHeader`; reorganize loose components into `Views/Components/`.
7. **P3** — Rename/split `Theme.branchIndicator` (requires product decision on the green accent's role).
