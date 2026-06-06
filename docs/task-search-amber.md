# Task: 搜索统一——跨楼层搜索 Almond + Amber 记录

## 目标
搜索功能支持同时搜索 Almond（Claude 导入记录）和 Amber（ChatGPT 导入记录），不再局限于当前 profileId 楼层。

## 现状
- `SearchService.swift`（844行）用 `profileId` 做楼层隔离，只搜当前楼层
- `ImportRecord.swift` 有 `provider` 字段区分 "chatgpt" / "claude"
- 不同来源的聊天导入后可能在不同 profileId 下

## 改动方案

### Commit 1: SearchFilter 加搜索范围选项

**文件：`MemoryPalace/Services/SearchService.swift`**

1. `SearchFilter` 新增属性：
   ```swift
   var searchAllProfiles: Bool = false  // true = 跨楼层搜索
   ```
2. `performSearch()` 方法里，当 `searchAllProfiles == true` 时：
   - 不用 `profileId` 过滤 MessageNode 和 Conversation
   - 或者获取所有 profileId 列表然后合并搜索结果
3. 搜索结果里标注来源 profileId，让 UI 能区分

### Commit 2: 搜索 UI 加范围切换

**文件：找到搜索界面的 View 文件（搜 SearchView 或 SearchBar）**

1. 加一个切换按钮或 Picker："当前楼层" / "所有记录"
2. 切换时更新 SearchFilter.searchAllProfiles
3. 搜索结果里如果是跨楼层的，显示来源标签（杏仁🍊 / 琥珀🟠 或类似图标）

## 注意事项
- 三步走：Research → Plan → Implement
- 改 SearchService 要特别小心——844行的核心文件，测试搜索功能不被破坏
- 保持向后兼容：默认 searchAllProfiles = false，不影响现有行为
- 先读 SearchService.swift 完整理解搜索逻辑再动手
