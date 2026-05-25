# Research: 搜角色卡 / 世界书 / 记忆

## 粟粟需求

1. 「类型」行加三个单选选项：角色卡 / 世界书 / 记忆（和现有「全部」「🎨贴纸」并列）
2. 搜索 → 关键词高亮 → 点击 → **跳转到右栏对应面板的条目位置**
3. 三个一起做

## 现有基础：右栏架构

`MemoryPalace/Models/RightPanelPlugin.swift:104-111`

| toolId | 面板 View | 对应类型 |
|---|---|---|
| `memory` | `MemoryPanelView` | Memory (+ MemoryNote) |
| `worldBook` | `WorldBookPanelView` | WorldBook → WorldBookEntry[] |
| `cardLibrary` | `CardLibraryPanelView` | CharacterCard |
| `sticker` | (贴纸相关，已接) | — |

跳转 = `isRightPanelVisible = true` + `selectedToolId = "xxx"` + 某种方式让面板滚到目标。

**目前这三个面板都没有 `ScrollViewReader`**（grep 确认）— 需要新加机制。

## 数据结构梳理

### CharacterCard（`Models/CharacterCard.swift`）
- 存储：`UserDefaults`（`savedCharacterCards` key）、**不是 SwiftData**
- 由 `CharacterCardManager` (final class @Observable) 管理
- 可搜字段候选：
  - `name` ✅ 必搜
  - `description` ✅
  - `personality` ✅
  - `scenario` ✅
  - `firstMes` / `mesExample`
  - `systemPrompt` / `postHistoryInstructions`
  - `creatorNotes`
  - 内嵌世界书 `characterBookEntriesData`（JSON 格式 [[String:Any]]，搜起来麻烦，**先不搜**）

### WorldBook（`Models/WorldBook.swift`）
- 存储：SwiftData @Model
- `WorldBook.entries` 是 computed，decode `entriesData` 得到 `[WorldBookEntry]`
- 可搜字段：
  - `WorldBook.name` ✅
  - `WorldBookEntry.keys` (数组) ✅
  - `WorldBookEntry.secondaryKeys`
  - `WorldBookEntry.content` ✅
  - `WorldBookEntry.comment` ✅
- **注意**：entries 是 decoded 后的 Swift 数组，不能用 SwiftData predicate 搜，必须 fetch 所有 WorldBook 再内存过滤

### Memory（`Models/Memory.swift`）+ MemoryNote（`Models/MemoryNote.swift`）
- 都是 SwiftData @Model，都按 profileId 楼层隔离
- Memory 可搜：`content` ✅、`keywords` (数组)
- MemoryNote 可搜：`content` ✅

## 跳转实现的候选方案

### 方案 A：全局 Environment "pending scroll target"

加一个 Observable（或简单的 @State 绑定）：

```swift
@Observable
final class RightPanelNavigator {
    var pendingScroll: (tool: String, targetId: String)? = nil
}
```

点搜索结果 → `navigator.pendingScroll = ("memory", memoryId)` + 打开右栏 + 切 tool → 目标面板 `onChange(of: navigator.pendingScroll)` + 用 `ScrollViewReader` 滚动 + 清零 pending。

**优点**：各面板逻辑自洽，只在相关面板加一点点代码。  
**缺点**：要改三个面板 + 一个新对象注入 Environment。

### 方案 B：每个面板自带 "initialScrollId"

通过绑定传入，但绑定穿透多层复杂。**否决**。

### 方案 C：NotificationCenter

SwiftUI 里用 `NotificationCenter` 可行，但风格和项目其它部分不一致（本项目没这么用）。**否决**。

**建议方案 A**。【✅】

## UI 行为不确定点（需粟粟定）

### 1. 搜索字段范围（每种资源）

| 资源 | 建议搜 | 可选 |
|---|---|---|
| 角色卡 | name + description + personality + scenario | + firstMes / systemPrompt / creatorNotes？ |
| 世界书 | WorldBook.name + entry.keys + entry.content + entry.comment | + secondaryKeys？ |
| 记忆 | Memory.content + MemoryNote.content | + Memory.keywords？ |

**倾向**：搜字段宽一些，结果 row 高亮用第一个命中片段。

### 2. 「类型」行 UI

从 `全部` `🎨贴纸` → 加到 5 个单选：

```
类型   全部   🎨 贴纸   👤 角色卡   📚 世界书   🧠 记忆
```

Emoji 用不用？粟粟喜欢暖奶白少 emoji。建议纯文字：

```
类型   全部   贴纸   角色卡   世界书   记忆
```

### 3. 搜索结果 row 的样子

每种资源 row 里应该显示啥？

- **角色卡**：头像缩略 + 卡名（高亮） + 命中片段预览（比如 personality 里命中"温柔"）
- **世界书条目**：WorldBook.name > entry comment (高亮) + content 预览片段
- **记忆**：content 片段（高亮） + category icon/颜色

### 4. 点击跳转动作

| 资源 | 面板 | 目标行为 |
|---|---|---|
| 角色卡 | cardLibrary | 滚动到卡 row + ???（要不要直接弹出 Editor sheet？） |
| 世界书条目 | worldBook | 切到对应 WorldBook + 滚动到 entry |
| 记忆 | memory | 滚动到条目 + 可能高亮闪一下 |

**高亮闪烁**要不要？我倾向加一个 1.5s 的短暂背景色脉冲，粟粟能看到"就是这条"。

### 5. 现有「其他筛选」（时间/角色/排序）在资源类型下的行为

- **时间**：资源也有 createdAt，能用 conv.createTime / Memory.createdAt 过滤
- **角色（user/assistant）**：资源没 role 概念 → **灰掉**
- **排序**：最近/最早可用，A→Z/Z→A 按资源名排序
- **范围（标题/内容/两者）**：资源没"标题 vs 内容"的二分 → **灰掉** 或直接保持默认

## 性能考虑

- CharacterCard 总数 ~ 10-50 张，纯内存过滤，无压力
- WorldBook 总数 ~ 10 本，每本 entries ~ 20-100 条，最多几千条，内存过滤 OK
- Memory 可能多（几百到几千），但有 `@Model`，能用 SwiftData predicate `content.localizedStandardContains`
- MemoryNote 类似 Memory

## 影响文件估算

**新增**：
- `Services/SearchService.swift` 加 3 个新函数 `searchCharacterCards` / `searchWorldBooks` / `searchMemories`
- 新类型：`SearchResourceKind`，新结构：`CharacterCardSearchResult` / `WorldBookSearchResult` / `MemorySearchResult`
- `Services/RightPanelNavigator.swift`（新文件，~20 行）

**改动**：
- `Views/SidebarView.swift`：
  - 「类型」行扩展 5 选一
  - `searchShowStickers: Bool` 改成 `searchType: SearchResourceKind`（enum）
  - 搜索结果视图新增 3 个 branch + row 渲染
  - triggerSearch 按 type 分发
- `Views/MemoryPanelView.swift` / `Views/WorldBookPanelView.swift` / `Views/CardLibraryPanelView.swift`：
  - 包 `ScrollViewReader`
  - 订阅 `navigator.pendingScroll`，滚动后 clear

  工作量中等偏大。建议**一次做一个资源**更稳妥，但粟粟说"一起" — 那就一次都上，分 task 清晰。

## 粟粟需要定的

1. 搜字段范围（第 1 节）：宽 or 窄？【原来多宽现在就多宽】
2. 类型行 UI：**要不要 emoji**？【先加emoji试试】
3. 角色卡点击：**只滚动** or **滚动+自动弹 Editor**？【只滚动】
4. 高亮闪烁：**要** or 只滚动就够？【要】
5. 时间/角色/排序/范围在资源类型下的行为：按我上面表格建议 OK 吗？【OK】

