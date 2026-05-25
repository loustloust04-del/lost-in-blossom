# Research: 贴纸搜索 + 重名处理

## 两种搜索，两个位置

### 左栏：搜"贴在哪了"（PlacedSticker 使用记录）

**用途**：我记得某个对话里贴了个什么贴纸，想找到它。

**数据源**：PlacedSticker，关联 conversationId + stickerAssetId（找名字）+ nearestMessageId。

**搜索逻辑**：
1. 用户输入关键词（搜贴纸名 or 便签内容）
2. 查 StickerAsset.name 匹配 → 拿到 assetId 列表
3. 查 PlacedSticker.stickerAssetId in assetIds → 拿到贴纸使用记录
4. 也搜 PlacedSticker.noteContent（便签内容直接匹配）
5. 按 conversationId 分组，显示"对话标题 → N 个贴纸"

**展示**：
- 跟消息搜索结果并列，或者用 FilterChip 切换（消息/贴纸/全部）
- 每条结果：贴纸缩略图 + 名称 + 所在对话标题
- 点击 → 跳转到那个对话 + 滚动到贴纸附近的消息（nearestMessageId）

**集成方式**：
左栏搜索 FilterChip 加一个"贴纸"chip。选中后搜索结果切换为贴纸结果。
或者更自然：搜索同时搜消息和贴纸，贴纸结果混在消息结果里，用图标区分。

**推荐：混合搜索** — 搜索时同时查消息 + 贴纸，结果统一展示。贴纸结果用 🎨 图标区分。FilterChip 加"贴纸"可以只看贴纸结果。

### 右栏：搜"库里有什么"（StickerAsset 资产）

**已有** — StickerLibraryView 顶部搜索栏，按 name + tags 过滤 Gallery。不需要改。

## 贴纸重名处理

### 现状
用户导入两张图片都叫"猫"，StickerAsset.name 都是"猫"。搜索能搜到，Gallery 显示两个，但用户分不清。

### 方案
1. **导入时自动去重命名**：检测同名，自动加序号"猫 (2)"
2. **Gallery 显示时如果重名加小标注**：比如显示创建日期
3. **搜索结果显示缩略图**：即使名字一样也能通过图看出区别

**推荐：方案 1 + 3**。导入时检测重名自动编号。搜索/Gallery 因为有缩略图所以不怕同名。

## 实现细节

### SidebarView 改动

**搜索结果新增贴纸组**：
- 新类型 `StickerSearchResult`：assetName, thumbnailPath, conversationTitle, conversationId, nearestMessageId, placedStickerId
- `triggerSearch()` 里追加贴纸搜索
- 显示用新的 `StickerMatchRow`（缩略图 + 名称 + 对话标题）
- 点击 → loadConversation + scrollToNodeId

**FilterChip 新增**：
- 现有：全部 / 收藏 / 回收站
- 新增：在搜索激活时显示"消息"/"贴纸"/"全部"筛选

### StickerViewModel 改动

**导入去重命名**：
`importImages()` 里检查现有 stickerAssets 是否已有同名，有则自动加序号。
