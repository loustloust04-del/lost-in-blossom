# Accessibility Audit — MemoryPalace (BunnyPalace iOS)

Date: 2026-07-14
Scope: `MemoryPalace/` (259 Swift files), SwiftUI app.

## Summary

The codebase currently ships with **zero accessibility support**. There are no
`accessibilityLabel` / `accessibilityHint` / `accessibilityValue` modifiers, no
`accessibilityElement` / `accessibilityHidden` / trait usage, no Dynamic Type
adoption, and no reduce-motion/transparency handling anywhere in the target or
its tests.

| Signal | Count |
|---|---|
| `accessibilityLabel` / `Hint` / `Value` | **0** |
| Any `accessibility*` modifier (incl. tests) | **0** |
| `Image(` total | 485 |
| `Image(systemName:` (SF Symbol icons) | 379 |
| `Button(` | 441 |
| `onTapGesture` | 47 |
| Fixed-size fonts `.font(.system(size:))` | 1320 |
| Semantic fonts (`.body`, `.headline`, …) | 95 |
| `dynamicTypeSize` / `sizeCategory` / `relativeTo:` | 0 |
| `reduceMotion` / `reduceTransparency` checks | 0 |
| `Image(decorative:)` | 0 |
| `labelsHidden()` on inputs | 20 |
| `TextField(` / `TextEditor(` | 108 |

## 1. VoiceOver

### 1.1 Icon-only buttons (highest impact)

Hundreds of buttons whose only label is an SF Symbol. VoiceOver falls back to
the symbol name (often nonsensical, always English) or reads nothing useful.
Representative examples:

- `MemoryPalace/Views/ScrollToBottomButton.swift:15` — bare `chevron.down` button, no label.
- `MemoryPalace/Views/CardFlowView.swift:611,618` — in-conversation search prev/next: `chevron.up` / `chevron.down` at 11pt, `.buttonStyle(.plain)`, no label, no frame (touch target well under 44pt).
- `MemoryPalace/Views/AppearanceSettingsTab.swift:94,104` (repeated at 377,387) — font-scale stepper buttons `textformat.size.smaller/larger`, no label, no value announcement for the adjacent `Slider`.
- `MemoryPalace/Views/StickerToolbar.swift:104`, `StickerKeyboardPanel.swift:34,153`, `StickerLibraryView.swift:174` — sticker UI is fully icon-driven.
- `MemoryPalace/Views/APISettingsTab.swift:690,1105`, `AppearanceSettingsTab.swift:615` — clear-search and delete (destructive!) buttons with icon-only content.

Files with highest density of unlabeled interactive elements (icons + buttons + taps):

| File | Image(systemName) | Button( | onTapGesture |
|---|---|---|---|
| Views/CardFlowView.swift | 35 | 42 | 2 |
| Views/SidebarView.swift | 23 | 29 | 12 |
| Views/WorldBookPanelView.swift | 18 | 24 | 2 |
| Views/GatewayConsoleView.swift | 15 | 21 | 3 |
| Views/APISettingsTab.swift | 11 | 23 | 1 |
| Views/SettingsView.swift | 2 | 25 | 0 |
| Views/PersonaSettingsTab.swift | 17 | 8 | 0 |
| Views/Reading/BookReaderSheet.swift | 13 | 9 | 0 |
| Views/ProjectsView.swift | 12 | 5 | 5 |

### 1.2 `onTapGesture` instead of `Button` (47 sites)

Views made tappable via `.onTapGesture` are **invisible to VoiceOver as
controls** — no button trait, no activation via double-tap unless the element
happens to be focusable. Examples:

- `Views/VoiceCapsuleView.swift:45` — voice message play/pause is a capsule + tap gesture; a VoiceOver user cannot play voice messages.
- `Views/CalendarPanelView.swift:142,205` — date cell selection.
- `Views/GroupMembersSheet.swift:71`, `CreateGroupChatView.swift:168` — color swatch pickers (also color-only information, see 3.2).
- `Views/ArtifactCanvasView.swift:207`, `Reading/BookshelfView.swift:167`, `GatewayConsoleView.swift:298,420,499`.

Note: `VoiceCapsuleView.swift` documents the tap gesture as a deliberate
workaround ("横向滚动区 Button 会被手势吞"). Where `Button` can't be used, add
`.accessibilityAddTraits(.isButton)` + `.accessibilityAction`.

### 1.3 Unlabeled images

379 SF Symbol images and ~100 asset images; none marked `Image(decorative:)`
and none labeled, so VoiceOver will read raw symbol/asset names
("anthropicons-chats") or clutter the focus order with decoration.

### 1.4 Inputs

108 `TextField`/`TextEditor` instances; 20 use `.labelsHidden()`. Hidden-label
inputs need `accessibilityLabel` — currently none have one, so they announce
only placeholder text (or nothing).

## 2. Dynamic Type

- **1320 fixed-size fonts vs 95 semantic fonts.** `.font(.system(size: N))` does not scale with the user's system text size. Distribution is heavily skewed small: 335 uses at ≤12pt, incl. 9pt (34), 10pt (87), 11pt (105) — tiny even at default size, ignoring the user's setting entirely.
- **No `relativeTo:`** on any custom/fixed font, no `@Environment(\.dynamicTypeSize)`, no `@ScaledMetric` — layout metrics won't scale either.
- The app implements its **own `fontScale` setting** (0.5–2.0, `AppearanceSettingsTab.swift`) which mitigates chat-content readability, but (a) it appears to apply to message content, not chrome, and (b) it does not honor the system-wide accessibility text size the user already configured.
- 19 `Font.custom` uses without `relativeTo:` — custom fonts frozen at fixed sizes.

## 3. Other VoiceOver / accessibility considerations

1. **Touch targets**: 74 interactive elements framed at 20–39pt width (< 44×44pt HIG minimum), e.g. the 11pt chevron search-nav buttons in `CardFlowView.swift`.
2. **Color-only information**: member color pickers (`GroupMembersSheet`, `CreateGroupChatView`) convey selection state purely by color swatch.
3. **Motion/transparency**: heavy use of springs, glass/blur effects (`glassEffect`, `glassButtonStyleCompat`) with zero `accessibilityReduceMotion` / `reduceTransparency` checks.
4. **Grouping**: no `accessibilityElement(children:)` anywhere — composite rows (chat cards, sidebar rows) will read as many fragmented elements in arbitrary order.
5. **State announcement**: toggling states (play/pause, expanded/collapsed, selected day) never update an `accessibilityValue`, so VoiceOver users get no feedback.

## 4. Recommendations (prioritized)

1. **P0 — Label every icon-only `Button`** in the top-9 files above (~200 buttons). Mechanical fix: `.accessibilityLabel(Text("发送"))` etc. Start with destructive actions (delete buttons) and primary chat flow (`CardFlowView`, `SidebarView`).
2. **P0 — Make `onTapGesture` controls real controls**: convert to `Button` where possible; otherwise add `.isButton` trait + label + `accessibilityAction`. `VoiceCapsuleView` (voice playback) first — it is currently unusable with VoiceOver.
3. **P1 — Dynamic Type**: replace `.system(size:)` with semantic styles, or at minimum `Font.system(size:, relativeTo:)` / `@ScaledMetric`. Wire the existing in-app `fontScale` to default from the system content size category.
4. **P1 — Mark decorative images** with `Image(decorative:)` or `.accessibilityHidden(true)`.
5. **P2 — Touch targets**: pad small chevrons/steppers to 44×44 via `.frame` + `.contentShape`.
6. **P2 — Reduce Motion/Transparency**: gate springs and glass effects on `@Environment(\.accessibilityReduceMotion)` / `\.accessibilityReduceTransparency`.
7. **P2 — Group composite rows** with `.accessibilityElement(children: .combine)` and add `accessibilityValue` for stateful controls.
8. **Process**: add an Xcode Accessibility Inspector pass and a UI-test smoke check (`XCUIApplication` label assertions) to CI so regressions don't reaccumulate.

## Method

Static grep audit on 2026-07-14 (`main`, after pull from `caelum-origin`).
Counts via `grep -rn ... --include="*.swift" MemoryPalace/`. No runtime
VoiceOver session was performed; counts are upper/lower bounds, not exact UX
measurements.
