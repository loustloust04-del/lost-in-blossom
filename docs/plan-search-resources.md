# Plan: 搜角色卡 / 世界书 / 记忆

## 所有决策（research 批注）

- 方案 A（`RightPanelNavigator`）✅
- 搜字段：**原来多宽现在就多宽**（卡名+全部文本字段 / WorldBook.name+entry全部可读字段 / Memory.content+keywords + MemoryNote.content）
- 类型行：先加 emoji 试试（`🎨 贴纸` `👤 角色卡` `📚 世界书` `🧠 记忆`）
- 角色卡点击：只滚动，不弹 Editor
- 高亮闪烁：要，1.5s 脉冲
- 时间/角色/排序/范围在资源类型下的行为：按表格

## 新心智模型（类型行的 5 选一）

| 类型 | 搜什么 | 结果去哪 | 点击动作 |
|---|---|---|---|
| 全部 | 对话（title/content，按范围） | 主列表/搜索结果 | 打开对话 |
| 贴纸 | placed stickers | 贴纸结果 | 跳画布位置（已有）|
| 角色卡 | CharacterCard 所有文本字段 | 新资源结果 | 打开右栏 cardLibrary + 滚到卡 + 高亮闪 |
| 世界书 | WorldBook.name + Entry 字段 | 新资源结果 | 打开右栏 worldBook + 滚到条目 + 高亮闪 |
| 记忆 | Memory.content/keywords + MemoryNote.content | 新资源结果 | 打开右栏 memory + 滚到条目 + 高亮闪 |

## Task 1 — SearchResourceKind enum + SearchFilter 替换 ⬜

**文件**：`SearchService.swift`

```swift
enum SearchResourceKind: String, CaseIterable {
    case conversation   // 「全部」（对话）
    case sticker        // 「贴纸」
    case characterCard  // 「角色卡」
    case worldBook      // 「世界书」
    case memory         // 「记忆」
}
```

**去掉** `SidebarView.swift:49` 的 `searchShowStickers: Bool`，换成 `searchResourceKind: SearchResourceKind = .conversation`。

**注意**：Caller 里所有 `searchShowStickers` 的读 / 写都要换（grep 确认大约 5-8 处）。

## Task 2 — SearchService 三个新函数 ⬜

**文件**：`SearchService.swift`

```swift
struct CharacterCardSearchResult: Identifiable {
    let id: String                  // cardId
    let cardName: String
    let imageData: Data?
    let matchedField: String        // 匹到的字段名，如"性格"/"情景"
    let preview: String             // 命中片段 ~80 chars
    let keyword: String
}

struct WorldBookEntrySearchResult: Identifiable {
    let id: String                  // "\(bookId):\(entryId)"
    let bookId: UUID
    let bookName: String
    let entryId: UUID
    let entryComment: String        // 条目 comment 作为标题
    let matchedField: String        // "关键词" / "内容" / "书名"
    let preview: String
    let keyword: String
}

struct MemorySearchResult: Identifiable {
    let id: String                  // "mem:uuid" or "note:uuid"
    let isNote: Bool
    let category: String?           // Memory.category（MemoryNote 为 nil）
    let preview: String
    let keyword: String
    // 跳转用
    var targetKind: String { isNote ? "note" : "memory" }
    var targetId: String { String(id.dropFirst(isNote ? 5 : 4)) }
}
```

**搜索函数**：

```swift
// 角色卡：manager.cards 内存过滤
static func searchCharacterCards(
    keyword: String,
    manager: CharacterCardManager
) -> [CharacterCardSearchResult]

// 世界书：fetch 所有 WorldBook(profileId=pid)，解 entries，内存过滤
static func searchWorldBookEntries(
    keyword: String,
    profileId: String,
    container: ModelContainer
) async -> [WorldBookEntrySearchResult]

// 记忆：Memory 和 MemoryNote SwiftData predicate + 拼接
static func searchMemories(
    keyword: String,
    profileId: String,
    container: ModelContainer
) async -> [MemorySearchResult]
```

**实现要点**：
- 每个搜索函数都用 `buildPreview(_:keyword:)`（已有）生成预览
- 角色卡的 `matchedField` 按优先级：name > description > personality > scenario > firstMes > mesExample > systemPrompt > postHistoryInstructions > creatorNotes
- 世界书 entry 的 `matchedField` 优先级：comment > keys > content > secondaryKeys
- 记忆：Memory 优先 content 再 keywords（keywords join成字符串匹配）

## Task 3 — RightPanelNavigator ⬜

**新文件**：`MemoryPalace/Services/RightPanelNavigator.swift`

```swift
import Foundation

@Observable
final class RightPanelNavigator {
    /// 待滚动目标，非 nil = 面板应该滚到这条 + 高亮
    var pendingTarget: Target? = nil

    struct Target: Equatable {
        let tool: String        // "memory" / "worldBook" / "cardLibrary"
        let id: String          // 面板内目标条目 id（面板负责匹配）
        let subId: String?      // 可选子 id（如 worldBook 的 entryId）
    }
}
```

在 `MemoryPalaceApp.swift` 或 `ContentView` 里 `@State var rightPanelNavigator = RightPanelNavigator()` 并 `.environment(rightPanelNavigator)`。

## Task 4 — 三个右栏面板加 scroll + 高亮 ⬜

**文件**：`MemoryPanelView.swift` / `WorldBookPanelView.swift` / `CardLibraryPanelView.swift`

每个面板加：

```swift
@Environment(RightPanelNavigator.self) private var navigator: RightPanelNavigator?
@State private var highlightedId: String? = nil

ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(...) {
            ForEach(items) { item in
                rowView(item)
                    .id(item.id)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(highlightedId == item.id ? Theme.accent.opacity(0.5) : Color.clear)
                            .animation(.easeInOut(duration: 0.4), value: highlightedId)
                    )
            }
        }
    }
    .onChange(of: navigator?.pendingTarget) { _, target in
        guard let t = target, t.tool == "memory" else { return }   // 本面板 id 匹配
        let scrollId = t.subId ?? t.id
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(scrollId, anchor: .center) }
        highlightedId = scrollId
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if highlightedId == scrollId { highlightedId = nil }
        }
        navigator?.pendingTarget = nil   // 消费后清零
    }
}
```

**重要**：`item.id` 必须和 `scrollId` 格式对齐。每个面板自己负责。

## Task 5 — 「类型」行扩展为 5 选一 ⬜

**文件**：`SidebarView.swift` AdvancedSearchPanel

```swift
// 类型
HStack(alignment: .firstTextBaseline, spacing: 18) {
    categoryLabel("类型")
    typeChip("全部", kind: .conversation)
    typeChip("🎨 贴纸", kind: .sticker)
    typeChip("👤 角色卡", kind: .characterCard)
    typeChip("📚 世界书", kind: .worldBook)
    typeChip("🧠 记忆", kind: .memory)
}
```

`typeChip` 签名改为 `(String, SearchResourceKind)`。  
字段由 `@Binding var showStickers: Bool` 改为 `@Binding var resourceKind: SearchResourceKind`。

## Task 6 — triggerSearch 按 kind 分发 ⬜

**文件**：`SidebarView.swift:1154` `triggerSearch()`

逻辑：

```swift
switch searchFilter.resourceKind {   // 把 kind 放进 filter 更方便
case .conversation:
    // 现有的 performSearch + searchPlacedStickers
case .sticker:
    // 只跑 searchPlacedStickers
case .characterCard:
    // searchCharacterCards → characterCardResults
case .worldBook:
    // searchWorldBookEntries → worldBookEntryResults
case .memory:
    // searchMemories → memoryResults
}
```

**实际**：把 resourceKind 放进 `SearchFilter`（和 scope 一起）最干净。

## Task 7 — 搜索结果视图：3 个新 branch ⬜

**文件**：`SidebarView.swift:188-333` 搜索结果 ScrollView

现在是 `if searchShowStickers { ... 贴纸结果 ... } else { ... 对话结果 ... }`。

改成 switch kind：

```swift
switch searchFilter.resourceKind {
case .conversation:  // 原 else 分支
case .sticker:       // 原 if 分支
case .characterCard: // 新：ForEach(characterCardResults) { row in CharacterCardMatchRow(row) }
case .worldBook:     // 新
case .memory:        // 新
}
```

## Task 8 — 三种新 MatchRow View ⬜

**文件**：`SidebarView.swift`（跟 `StickerMatchRow` 放一起）

```swift
struct CharacterCardMatchRow: View {
    let result: CharacterCardSearchResult
    // 头像(imageData)圆形 + cardName高亮 + matchedField 小标签 + preview 高亮
}

struct WorldBookEntryMatchRow: View {
    let result: WorldBookEntrySearchResult
    // 📚 bookName > comment(高亮) + matchedField 标签 + preview 高亮
}

struct MemoryMatchRow: View {
    let result: MemorySearchResult
    // 🧠/📝 icon + category 标签 + content高亮 preview
}
```

所有 row 点击调 `navigateTo<Resource>Result(result)`。

## Task 9 — 三个导航函数 ⬜

**文件**：`SidebarView.swift`

```swift
private func navigateToCardResult(_ r: CharacterCardSearchResult) {
    // 1. 打开右栏
    // 2. selectedToolId = "cardLibrary"
    // 3. navigator.pendingTarget = Target(tool: "cardLibrary", id: r.id, subId: nil)
}

private func navigateToWorldBookResult(_ r: WorldBookEntrySearchResult) {
    // tool: "worldBook", id: bookId, subId: entryId
}

private func navigateToMemoryResult(_ r: MemorySearchResult) {
    // tool: "memory", id: targetId, subId: nil
    // 面板里要区分 Memory / MemoryNote — 用 id prefix 或额外字段
}
```

这里需要 `@Environment(RightPanelNavigator.self)` 和通向 ContentView 的 `isRightPanelVisible` + `selectedToolId` 绑定。

**问题**：`SidebarView` 现在能不能访问 `isRightPanelVisible` / `selectedToolId`？
看 ContentView.swift:25 — 这俩是 ContentView 内部 @State，SidebarView 目前不访问。

**解决方案**：把这俩通过 `@Binding` 传给 SidebarView，或者用一个共享 `@Observable` 放 environment。

**倾向 Binding**（最小改动）：给 `SidebarView` 加 `@Binding var isRightPanelVisible: Bool` 和 `@Binding var selectedToolId: String`。

## Task 10 — 筛选在资源类型下的行为调整 ⬜

**文件**：`AdvancedSearchPanel`

资源类型（`.characterCard` / `.worldBook` / `.memory`）下：
- **范围** chip：灰掉（已有 isContentSearchActive 类似机制，加一层 `isResourceSearch`）
- **角色** chip：灰掉
- **时间**：沿用（资源有 createdAt，在 search 函数里按 filter.dateRange 过滤）
- **排序**：沿用（.recent/.oldest/.titleAZ/.titleZA 都能用，各 search 函数接收 sortOrder 自排）

需要往 `AdvancedSearchPanel` 再传一个 `isResourceSearch: Bool`，roleChip/scopeChip 用 `&&` 加这个条件灰掉。

## Task 11 — 底部 "清除搜索" footer 适配 ⬜

**文件**：`SidebarView.swift:590-591`

```swift
Text("\(searchResults.count) 个对话，\(totalMatches) 条结果")
```

资源模式下文字改：`"\(characterCardResults.count) 张角色卡"` / `"\(worldBookEntryResults.count) 条世界书"` / `"\(memoryResults.count) 条记忆"`。

switch kind 分发。

## Task 12 — Build 验证 ⬜

```bash
xcodegen generate && xcodebuild -scheme MemoryPalace build
```

## Task 13 — 手测清单 ⬜

1. 类型切到「角色卡」→ 输入关键词 → 按 ➡️ → 角色卡匹到，row 显示头像+名+字段标签+preview
2. 点角色卡 row → 右栏打开 cardLibrary，滚到目标卡 row，背景高亮 1.5s ✅
3. 类型切到「世界书」→ 搜 → 点 row → 右栏打开 worldBook + 滚到 entry + 高亮 ✅
4. 类型切到「记忆」→ 搜 → 点 row → 右栏打开 memory + 滚到 Memory 或 MemoryNote + 高亮 ✅
5. 类型=角色卡时，「角色」「范围」灰掉 ✅
6. 类型=角色卡时，「时间」能按 createdAt 过滤 ✅
7. 类型=角色卡 + Z→A → 按 name 倒排 ✅
8. 类型=全部 / 贴纸 → 和之前行为完全一致（回归测试）✅
9. 右栏已经打开 + 切 tool + 滚动：流畅不闪 ✅

## Task 14 — commit + push ⬜

```
feat: 搜索加角色卡/世界书/记忆三类资源 + 右栏跳转高亮
```

---

## 风险与备选

- **ScrollViewReader 滚动失败**：如果 LazyVStack 里目标还没渲染，`scrollTo` 可能不生效。建议滚动前 `proxy.scrollTo(id, anchor: .top)` 两次（间隔 50ms）或用 `DispatchQueue.main.asyncAfter`
- **世界书面板内部有多个 WorldBook 切换** — 需要先切到对的 book 再滚到 entry。我还没细看 `WorldBookPanelView`，Task 4 实施时要补细节
- **Memory 面板也是 Memory+MemoryNote 混合列表** — 需要看 `MemoryPanelView` 的 item 结构再决定 id 格式

这两个风险在 Task 4 开始时先 spike 一下相关面板再实现，避免返工。

---

## 粟粟批注区

<!-- 有问题写这里 -->
