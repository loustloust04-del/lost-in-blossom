# Plan: 自定义 Tag 功能

> 前置：`research-custom-tags.md`
> 日期：2026-04-17

## 设计概览

```
[全部] [收藏] [回收站] [🌸 工作] [💡 想法] [➕]
  内置 tab（不可移动）     自定义 folder/tag     加号按钮
   ↓ 水平 ScrollView（tag 多时可滚动）
```

**复用：** `Folder` 模型、`FavoriteItem` join table、现有 `selectedFolderId` 筛选逻辑、`NewFolderSheet` 的 emoji picker UI。

**新增：** 动态 tab（`SidebarTab.folder(id:)`）、tag 栏水平滚动、拖拽排序、删除菜单、"➕"按钮。

## Task Checklist

### T0：字段重命名 Folder → ConversationTag

`Folder` 这个名字以后留给真正的项目文件夹用，现在的"文件夹"逻辑其实就是"标签"（多对多）。彻底改名：

- [ ] `Models/Folder.swift` → `Models/ConversationTag.swift`
- [ ] `@Model final class Folder` → `@Model final class ConversationTag`
- [ ] `FavoriteItem.folderId` → `FavoriteItem.tagId`
- [ ] `Conversation.folderId: String?` 保留（留给以后真的文件夹，目前未使用）
- [ ] 全局搜索替换：
  - `Folder` → `ConversationTag`（类型）
  - `folderId` → `tagId`（FavoriteItem 字段、本地变量）
  - `selectedFolderId` → `selectedTagId`
  - `FolderRow` → 删除（未使用）
  - `NewFolderSheet` → `NewTagSheet`
  - `showNewFolderSheet` → `showNewTagSheet`
- [ ] `@Query(sort: \Folder.order)` → `@Query(sort: \ConversationTag.order)`
- [ ] SwiftData 注册：`MemoryPalaceApp.swift` 的 `modelContainer` Schema 列表更新
- [ ] 旧数据：SwiftData 把 `Folder` → `ConversationTag` 当作新类型，老用户的旧 Folder 记录会丢失。但现在 Folder UI 已隐藏，没人在用，直接丢弃可接受。

### T1：扩展 `SidebarTab` 为动态类型

- [ ] `SidebarTab` enum 改为 `Hashable`（保留 all/favorites/trash），加 `case folder(id: String)`
- [ ] 去掉 `CaseIterable`（dynamic 了）
- [ ] `currentTab` getter：如果 `selectedFolderId` 有值 → `.folder(id:)`
- [ ] `selectTab(_:)` 处理 `.folder(id:)` case：设置 `selectedFolderId = id`，清空 `showFavoritesOnly` / `showTrash`
- [ ] 计算 `allTabs` 数组：`[.all, .favorites, .trash] + folders.map { .folder(id: $0.id) }`

### T2：tag 栏水平滚动 + 动态 tab 渲染

- [ ] `sidebarTabBar` 改为 `ScrollView(.horizontal, showsIndicators: false)` 包裹 HStack
- [ ] `ForEach(allTabs)` 渲染所有 tab
- [ ] Tab label：对于 `.folder` 显示 `emoji + name`，对于内置显示 `rawValue` 式名称（新加 `displayTitle` computed）
- [ ] 保持现有圆角 + 反向圆角 + fill 逻辑
- [ ] 末尾加 "➕" 按钮（独立样式，不是 tab，一个圆形玻璃按钮）

### T3：新建 tag sheet

- [ ] 复用 `NewFolderSheet` 组件（代码已存在）
- [ ] 把触发入口从旧位置移到 "➕" 按钮
- [ ] 标题文案"新建文件夹" → "新建标签"
- [ ] 创建后的 folder 自动出现在 tab 栏（SwiftData `@Query` 自动刷新）
- [ ] `order` 默认赋值 `folders.count`（已有逻辑）

### T4：拖拽排序（仅自定义 tag）

- [ ] 自定义 folder tab 加 `.onDrag { NSItemProvider(object: folder.id as NSString) }`
- [ ] 对应 `.onDrop(of: [.text], delegate: ...)` 复用 `ToolReorderDropDelegate` 模式
- [ ] 新建 `FolderReorderDropDelegate` 在 SidebarView.swift
- [ ] 拖拽时写入 Folder.order（整数重排）
- [ ] 内置 tab（all/favorites/trash）**不加** `.onDrag`，用户无法拖它们

### T5：删除 tag

- [ ] 自定义 folder tab 加 `.contextMenu` → "删除标签"
- [ ] 删除时：删 Folder + 删所有 folderId 匹配的 FavoriteItem
- [ ] 如果当前选中的就是被删的，`selectedFolderId = nil`（回落到"全部"）
- [ ] 用 `confirmationDialog` 二次确认

### T6：右侧出屏 tag 的反向圆角

- [ ] 验证：tag 在 ScrollView 里滚动时，反向圆角是否跟着 tab 一起移动（应该会，因为 overlay 在 tab label 上）
- [ ] 如果有异常：不做特殊处理，接受边界情况

### T7：空 tag 状态

- [ ] `compactListEmptyStateTitle` 加 `.folder` case：`"这个标签还没有对话"`
- [ ] `compactListEmptyStateIcon`：`"tag"`
- [ ] `compactListEmptyStateSubtitle`：`"在对话上长按可以添加到这个标签"`

### T8：build + 双平台验证 + commit + push

- [ ] macOS build 通过
- [ ] iOS build 通过
- [ ] 手测：加 tag / 切换 tag / 拖拽排序 / 删除 tag / 空状态
- [ ] git commit + push

## 不做（留给未来）

- 给单个 conv 加 tag 的 UI（现在没入口，之后在 conv context menu 加"加标签"）
- tag 颜色
- tag 批量管理页
- 内置 tag 改名

## 文件变动预估

| 文件 | 改动 |
|---|---|
| `Models/Folder.swift` | 不改 |
| `Views/SidebarView.swift` | 改 SidebarTab enum + sidebarTabBar + 加 "➕" + DropDelegate + 删除逻辑 + 空状态文案 |
| `Models/...` | 不改 |
| `docs/research-custom-tags.md` | 已写 |
| `docs/plan-custom-tags.md` | 本文件 |

## 风险缓解

- **风险**：反向圆角在滚动时位置错乱
  **缓解**：反向圆角作为 tab label 的 overlay，会跟着 tab 滚动，预期没问题
- **风险**：内置 tab + 自定义 tab 宽度不一（自定义多了 emoji）
  **缓解**：用 `.fixedSize()` 让 tab 宽度由内容决定，而不是 `.frame(maxWidth: .infinity)`
- **风险**：tab 太多屏幕装不下
  **缓解**：水平 ScrollView 天然解决
