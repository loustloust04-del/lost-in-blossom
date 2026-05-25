# Research: 自定义 Tag 功能

> 日期：2026-04-17

## 用户需求

1. 在 tag 栏的 `全部/收藏/回收站` 后面，用户可以自定义加 tag
2. 点"➕"弹 sheet，自定义标题 + emoji
3. Tag 排序（拖拽）
4. 点击 tag = 筛选 conversation

## 现有架构发现 — Folder 模型几乎就是 Tag

### `Models/Folder.swift` 已存在，完美契合 Tag 需求

```swift
@Model final class Folder {
    @Attribute(.unique) var id: String
    var name: String
    var emoji: String = "📁"
    var order: Int = 0
    var createTime: Date = Date()
}

@Model final class FavoriteItem {
    @Attribute(.unique) var id: String
    var nodeId: String?
    var conversationId: String    // ← conv 端
    var folderId: String          // ← folder 端
    var contentPreview: String
    var createTime: Date
}
```

**FavoriteItem 就是 conv ↔ folder 的 join table** — 等价于多对多关系。一个 conv 可以属于多个 folder/tag。

### 已存在但隐藏的 UI 组件

- `FolderRow`（SidebarView.swift:1147）— folder 行视图
- `NewFolderSheet`（SidebarView.swift:1186）— emoji picker（6 列 grid，12 个预设 emoji）+ 名称输入
- `selectedFolderId` + `refreshList()` 里的 folder 筛选逻辑完整（按 folderId fetch FavoriteItem → 提取 convIds → 过滤 Conversation）

### 之前被我暂时移除但代码还在的功能

上次做 Chrome tab 时移除了：
- FilterChip 那行里的 "新建文件夹" 按钮
- Folders section（FolderRow 列表）
- `showNewFolderSheet` state 可能还在

**这些是 dead code 还是被移到别的地方？** 需要快速确认。

## 关键决定

### 命名：叫"标签"还是"文件夹"？

- 代码层面用 `Folder`（已存在，避免迁移）
- UI 层面显示"标签"
- 用户视角就是"自定义 tag"

### 模型要改的吗？

不改 Folder 模型。已有 `id, name, emoji, order, createTime` 完全够用。

### 现有 SidebarTab 枚举和动态 Folder 的融合

现在：
```swift
enum SidebarTab: CaseIterable {
    case all, favorites, trash
}
```

改成支持动态 folder：
```swift
enum SidebarTab: Hashable {
    case all, favorites, trash
    case folder(id: String)   // 动态
}
```

`currentTab` / `selectTab` 相应扩展。

`selectedFolderId` 的现有 state 继续沿用（对应 `.folder(id:)` 的 payload）。

### "➕" 按钮放哪？

tag 栏末尾，最后一个 tab 后面：
```
[全部] [收藏] [回收站] [🌸 自定义1] [💡 自定义2] [➕]
```

但：tag 多了之后会超出屏幕宽度 → tag 栏需要水平 ScrollView。

### 排序

长按 tag 拖拽 → 更新 Folder.order。与 toolbar 工具排序逻辑一致（那个用 `.onDrag` + `DropDelegate`，因为 HStack 不支持 `.onMove`）。

复用 `ToolReorderDropDelegate` 的思路即可。

### 内置 tag 能拖吗？

`全部/收藏/回收站` 是系统 tab，应该**不可移动不可删除**。只有用户自定义的 folder 可拖拽和删除。

### 删除 tag 怎么办？

Context menu："删除标签"。删除时：
- 删 Folder 记录
- 删所有对应的 FavoriteItem（避免悬空）
- 如果当前选中被删，回落到"全部"

### 空 tag 显示什么？

和现在"回收站是空的"一样的 `compactEmptyCard`，自定义文案。

## 风险

1. **tag 栏宽度**：原来 3 个 tab 刚好占满，加了自定义后要水平滚动。chrome tab 在 ScrollView 里的反向圆角视觉可能有问题（tab 跟着滚时圆角位置要一起动），需要验证
2. **"➕" 按钮形态**：不能是 tab 样式（会被误认为可选中），应该是独立的小圆按钮
3. **数据迁移**：之前可能有 Folder 数据残留，新用户没有，老用户可能有旧数据。不需要处理
4. **筛选逻辑**：现有 `selectedFolderId` 筛选已工作。只需触发 selectTab 时设置它

## 不做的

- 不做 tag 颜色（保持简洁，只有 emoji）
- 不做 tag 嵌套
- 不做"所有 tag 并集"这种复杂筛选
- 不做给单个 conv 加 tag 的 UI（已存在 conv context menu 里的"移到文件夹"，等用户要再做）
