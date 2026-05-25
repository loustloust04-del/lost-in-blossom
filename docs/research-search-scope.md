# Research: 搜索范围筛选（标题 / 内容 / 标题+内容）

## 粟粟的需求

1. 筛选面板加"范围"：标题 / 内容 / 标题+内容（单选，默认标题+内容）
2. 标题+内容模式下，结果列表**不混杂**：
   - 上面一排：**纯 title 匹**的 conv（不展开任何内容）
   - 下面一排：**内容匹**的 conv（展开 matchedNodes）

## 现状（SearchService.performSearch）

### 当前合并逻辑（SearchService.swift:166-196）

```
titleConvs = fetch conversations where title contains keyword
contentByConv = { convId: [matched nodes] }

for conv in titleConvs:
    push SearchResult(isTitleMatch=true, matchedNodes=contentByConv[conv.id] ?? [])
for convId in contentByConv.keys - titleConvs:
    push SearchResult(isTitleMatch=false, matchedNodes=contentByConv[convId])
```

然后一口气 `sortOrder` 排序整个数组 — 所以 title match 和 content-only match 会按 conv time/title 混在一起。

### SearchResult 字段

- `isTitleMatch: Bool` — 标题是否匹
- `matchedNodes: [MatchedNode]` — 内容匹到的消息节点
- `isExpanded: Bool` — UI 展开状态（init 时 = !matchedNodes.isEmpty）

## 现有 UI 对 SearchResult 的使用

`SidebarView.swift:237-330` — `ForEach($searchResults) { $group in ... }` flat 渲染：
- 每个 group 显示一个 conv 头（标题）+ 可展开 matched nodes 列
- 排序：整个数组一次 sort

## 关键决策（需要粟粟确认）

### 1. Overlap：既 title 匹又 content 匹的 conv 怎么办？

**场景**：conv 标题"我爱你"，里面还有消息"你好吗"（都含"你"）。

| 方案 | 效果 |
|---|---|
| **A 归标题块，不展开内容** | overlap conv 只出 1 次，纯 title 行，content 匹被隐藏 |
| B 两块都出一次 | 重复 2 行，不直觉 |
| C 归标题块但展开内容 | 等于现在的混杂逻辑，粟粟明确说不要 |

**建议 A**。想看内容匹的话切"只搜内容"。【B吧，不直觉总比让人找不到好】

### 2. Section header 要不要？

```
—— 标题匹配 (5) ——
我爱你
心里在想你
...
—— 内容匹配 (12) ——
> 对话甲
    你好吗
    ...
```

| 方案 | |
|---|---|
| X 加明显分隔（上图） | 清楚但啰嗦，占空间 |
| **Y 隐式分块（空行 / 细线）** | 视觉不打扰，靠顺序暗示 |
| Z 不分块，就靠顺序 | 最简，但 title 和 content row 视觉差距不大时可能混 |

**倾向 Y**（一根细线 / 小 spacer + 淡灰色 count 标签）。✅

### 3. 排序在两块里分别排，还是全局排？

**建议分别排**。sortOrder 作用到每块内部：

- 标题块按 title A→Z 排 → 上面一排标题 A→Z
- 内容块按 conv time / title 排

**两块的前后顺序固定：标题总在上、内容总在下**（和 sort 无关）。✅

### 4. 只搜标题 / 只搜内容模式下

| 模式 | 搜什么 | 角色 chip | 时间对谁生效 |
|---|---|---|---|
| 只搜标题 | conv.title 匹配 | **灰掉** | conv.createTime |
| 只搜内容 | node.content 匹配 | 激活可点 | node.createTime（已改内存过滤） |
| 标题+内容 | 两个都搜 | 激活可点 | title 块用 conv.createTime, 内容块用 node.createTime |

### 5. 列表过滤模式（不按 ➡️）下，「范围」应该？

**建议**：列表模式下范围筛选灰掉（和角色一样）。列表模式只筛标题，无"范围"概念。
按 ➡️ 进全量搜索后范围才激活。【不是啊，{范围:标题}不就等于列表过滤模式吗？】

## 影响范围

**改动文件**：
- `MemoryPalace/Services/SearchService.swift` — SearchFilter 加 scope，performSearch 分支
- `MemoryPalace/Views/SidebarView.swift` — 面板加「范围」行、UI 分块渲染

**不动**：
- 贴纸搜索路径
- 列表过滤模式 (`refreshList/fetchPage`)
- 我上一轮刚修的 triggerSearchIfActive / dateRange 过滤

## 性能

- **只搜标题**：比现在快（跳过 content 搜索）
- **只搜内容**：比现在快（跳过 title 搜索）
- **标题+内容**：和现在差不多（两个都跑，只是展示分块）
