# Research: 搜索集成 + 设置贴纸 Tab + 导入导出

## 1. 搜索集成

### 现状
- `SearchService.swift` 已有 `searchStickers(keyword:profileId:container:)` 和 `findStickersNearMessage(messageId:profileId:container:)` 方法
- `SidebarView.swift` 的搜索结果只显示 `ContentMatchRow`（纯文字），不显示贴纸
- 搜索触发在 `triggerSearch()` 里调 `SearchService.performSearch()`

### 需要做的

**A. 搜索结果旁显示贴纸缩略图**
当搜索结果的 `matchedNode.id` 对应的消息附近有贴纸（通过 `nearestMessageId` 关联），在 ContentMatchRow 旁边显示贴纸小缩略图。

实现：
- `triggerSearch()` 里，搜完消息后，额外调 `SearchService.findStickersNearMessage` 查每个 matchedNode 有没有关联贴纸
- 或者更简单：一次性查所有有 `nearestMessageId` 的 PlacedSticker，建 `[messageId: [PlacedSticker]]` 字典
- ContentMatchRow 右侧加贴纸缩略图（如果有的话）

**B. 贴纸库搜索**
已有——StickerLibraryView 的搜索栏按 name + tags 过滤，在 Gallery 内部完成。

**C. 图层筛选**
搜索高级面板加 FilterChip：
- "便签" — 只显示便签关联的结果
- "贴纸" — 只显示图片贴纸关联的结果
- "全部" — 默认

这个比较复杂，先不做。第一版只做 A（搜索结果旁显示缩略图）。

## 2. 设置加贴纸 Tab

### 现状
SettingsView 有 5 个 tab：通用 / Prompt / API / 记忆 / 导入导出

`enum SettingsTab` 加 `case sticker = "贴纸"` 即可。

### 贴纸设置 Tab 内容
- 贴纸库统计（数量、占用空间）
- 默认描边样式选择
- 默认描边宽度滑块
- 清理未使用的贴纸文件

## 3. 贴纸导入导出

### 导出
把整个贴纸库打包：
- 所有 StickerAsset 的 metadata → JSON
- 所有 PNG 文件
- 打成一个 `.stickerpack` 文件（实际是 zip）

### 导入
选择 `.stickerpack` 文件 → 解压 → 读 JSON → 创建 StickerAsset + 复制 PNG

### 实现位置
放在设置的贴纸 Tab 里，"导出贴纸包" / "导入贴纸包" 两个按钮。

## 优先级

1. **设置贴纸 Tab**（加 enum case + 基础 UI）— 5 分钟
2. **导出贴纸包**（JSON + zip PNG）— 30 分钟
3. **导入贴纸包**（解压 + 创建）— 30 分钟
4. **搜索结果显示贴纸缩略图**— 20 分钟
5. **图层筛选**— 后续
