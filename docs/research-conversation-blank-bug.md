# Research: 进入对话"空白"+ 回底按钮失灵 — 三层 bug 诊断报告

> 2026-04-20 | 粟粟和 Claude 深度 log 调研结果
> 关联：`research-scroll-to-bottom-bug.md`（前一阶段诊断，onScrollGeometry 方案，只解决了一部分问题）

---

## TL;DR

以为是 pin 引入的 bug，**其实是三层问题叠加**，和 pin 基本无关：

1. **最核心（未修）**：`buildTreeInBackground` 的 root 选择用了 `.first(where:)` 在 Dictionary.values 上，**Swift dict 迭代顺序不定**，导致"抽盲盒"——同一个对话有时 `pathNodeIds=9` 有时 `pathNodeIds=0` → 时而正常时而空白
2. **中间（已修 commit 90e9c1b）**：`ContentHeightKey.reduce` 用了 `max(value, nextValue())`，MarkdownUI async 渲染高度 1pt 抖动被累积，触发 content size 无限增长 + body 每秒几十次重建
3. **表层（已修 commit 7ba31b7）**：切对话后 scroll offset 不重置 + `isAtBottom` state 泄漏 → 即使 tree 正常也可能 scroll 到错位

pin 不是元凶。**pin 之前这些 bug 就都存在**，只是粟粟加 pin 后更频繁切对话测试，把它们都暴露了。

---

## 症状（粟粟口述）

> "点对话列表 — 点进去是空白的 — 出去刷新怎么刷都没用 — 我去切了楼层再切回来才可能触发好了，但是也不是全好下一个对话还是有可能点不进来。"
>
> "回底按钮一直不灵。"
>
> "但是 pinbar 一直很灵。"
>
> "抽盲盒一样，有时候不空白有时候空白"

---

## 探针部署

**位置**（临时 debug，修完要撤）：
- `CardFlowView.body` — 每次重建打印 `isLoading` + `pathCount`
- `CardFlowView.onChange(of: selectedConversation?.id)` — 切对话时机
- `CardFlowView.onChange(of: isLoading)` — loading 变化时机 + `scrollToLastMessage` 调用
- `CardFlowView.onScrollGeometryChange` — scroll offset / containerSize / contentSize
- `ConversationViewModel.applyTreeData` — `pathNodeIds.count` / `nodeMap.count` / `currentPath.count`

统一前缀 `[PROBE]`，便于 Xcode console 过滤。

---

## 诊断 1：ContentHeightKey runaway loop

### 证据

第一轮 log 显示 content size 持续增长 + body 高频重建：

```
[PROBE] geom offY=0 cont=562 size=3050
[PROBE] body rebuild isLoading=false pathCount=9
[PROBE] geom offY=524 cont=562 size=3428
[PROBE] body rebuild isLoading=false pathCount=9
[PROBE] geom offY=524 cont=562 size=3457
[PROBE] body rebuild isLoading=false pathCount=9
...
[PROBE] geom offY=524 cont=562 size=6500+
```

- content size 从 3050 一路累积到 6500+，**每次 body rebuild 后增 1-2pt**
- body rebuild 频率：每秒数十次
- 明显不合理——`pathCount=9` 固定，内容该稳定

### 根因

`CardFlowView.swift:514`：

```swift
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())   // ← 永远只增不减
    }
}
```

循环：
1. body 渲染 → LazyVStack layout
2. MarkdownUI async 渲染 / font loading / image cache 等，每次 layout 高度有 1pt 浮点抖动
3. `GeometryReader` 上报 → `reduce` 用 `max` → 永远取更大值
4. `onPreferenceChange` 触发 → `@State contentHeight` 变
5. body rebuild → 回到 1，无限循环累积

### 修法（已 apply，commit 90e9c1b）

```swift
value = nextValue()  // 取最新值，不累积
```

### 效果

第二轮 log 显示 size 稳定在 5032 附近（不再无限增长），body rebuild 频率大幅下降。但**空白 bug 依然随机出现**——说明还有别的 bug。

---

## 诊断 2：buildTreeInBackground root 选择的非确定性 bug（核心 bug，未修）

### 证据

第二轮 log 关键片段：

```
[PROBE] applyTreeData pathNodeIds=9 nodeMap=11 currentPath=9 convId=5969260F-...  ← 成功
[PROBE] body rebuild isLoading=false pathCount=9
... 滚动看内容 ...

[PROBE] body rebuild isLoading=true pathCount=0
[PROBE] applyTreeData pathNodeIds=0 nodeMap=11 currentPath=0 convId=5969260F-...  ← 同一对话，空白！
[PROBE] body rebuild isLoading=false pathCount=0

[PROBE] applyTreeData pathNodeIds=9 nodeMap=11 ...  ← 又成功
[PROBE] applyTreeData pathNodeIds=0 nodeMap=11 ...  ← 又空白
[PROBE] applyTreeData pathNodeIds=9 nodeMap=11 ...  ← 又成功
[PROBE] applyTreeData pathNodeIds=0 nodeMap=11 ...  ← 又空白
```

**同一个 convId、同一个 nodeMap.count=11、同一个 SwiftData 数据**，`pathNodeIds` 在 0 和 9 之间随机跳。

### 根因

`ConversationViewModel.swift:196` buildTreeInBackground 里：

```swift
// Find root
var rootId = infoMap.values.first(where: { $0.parentId == nil })?.id
if rootId == nil {
    rootId = infoMap.values.first(where: { infoMap[$0.parentId ?? ""] == nil })?.id
}
```

**`Dictionary.values` 在 Swift 里没有保证顺序**。`.first(where:)` 对非空 dict 是非确定性的——每次调用可能遍历顺序不同，返回不同节点。

对粟粟这个有 11 个节点的对话：
- 可能有多个 `parentId == nil` 候选（真 root + system/tool 孤立节点 + 其他边缘情况）
- 也可能没有 `parentId == nil`，进 fallback 分支找"parent 不在 infoMap 里"的节点，同样可能有多个候选
- `.first` 这次选到真 root → 遍历能走到 user/assistant → `pathNodeIds=9` ✅
- 下次选到孤立节点 → 遍历路径上没有显示 role → `pathNodeIds=0` ❌

**100% 是真正意义的盲盒**：dict 内部状态、hash seed、节点数都可能影响迭代顺序。

### 为什么 pin 之前没被注意到

pin 之前：
- 这个 bug 一直存在
- 但粟粟切换对话频率低，即使碰到空白也以为是"加载中"
- 没有 `isAtBottom` 和 `contentHeight` 的动态 state 放大问题

pin 之后：
- 粟粟频繁切对话测试 pin 功能，高频暴露随机性
- 上面诊断 1 的 runaway loop 让 UI 看起来"坏掉"，伪装成 pin 的问题

### 推荐修法（方案 A，未 apply，等粟粟批准）

用 `currentNodeId` 往上回溯找 root（确定性）：

```swift
// Trace from currentNodeId up to root (deterministic)
var mainPathIds = Set<String>()
var rootId: String? = nil
var traceId: String? = currentNodeId
while let nid = traceId, let info = infoMap[nid] {
    mainPathIds.insert(nid)
    if info.parentId == nil || infoMap[info.parentId ?? ""] == nil {
        rootId = nid
    }
    traceId = info.parentId
}

// Fallback: 如果 currentNodeId 不在 infoMap 里（conversation.currentNodeId stale），
// 选 createTime 最早的 parentId==nil 节点
if rootId == nil {
    let candidates = infoMap.values.filter { $0.parentId == nil || infoMap[$0.parentId ?? ""] == nil }
    // 需要给 NodeInfo 加 createTime 字段才能排序
    rootId = candidates.min(by: { ($0.id < $1.id) })?.id  // 用 id 排序做确定性 fallback
}
```

好处：
- 确定性，不再盲盒
- root 就是 currentNodeId 那条 path 的顶层（语义正确）
- fallback 用 id 字典序保证确定

风险：
- 如果 `conversation.currentNodeId` 本身指向错误节点，root 会错
- 但这样至少结果是**稳定的**错，方便调试

### 方案 B（备选）

保持当前结构，只把 `.first(where:)` 改成按确定性字段选：

```swift
var rootId = infoMap.values
    .filter { $0.parentId == nil }
    .min(by: { $0.id < $1.id })?.id
```

更简单，改动更小。但没利用 currentNodeId 这个语义信号。

---

## 诊断 3：切对话 scroll/state 泄漏（已修 commit 7ba31b7）

### 证据

- 切对话时 `isAtBottom` 保留上一对话的值 → safeAreaInset 高度错
- ScrollView scrollOffset 跨对话保留 → 新对话短时 scroll 超出 contentSize

### 修法（已 apply）

```swift
.onChange(of: viewModel.selectedConversation?.id) { _, _ in
    isAtBottom = true  // 重置
    pinCurrentIndex = 0
    pinBarHidden = false
}

.onChange(of: viewModel.isLoading) { _, loading in
    if !loading, !viewModel.currentPath.isEmpty {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToLastMessage(proxy: proxy)  // 两步 scrollTo 兜底
        }
    }
}
```

### 限制

这个修法**假设 currentPath 非空**——如果诊断 2 的 buildTreeInBackground 返回 pathNodeIds=0，currentPath 还是空，scrollTo 无事可做，空白依旧。

所以必须先修诊断 2 才能彻底解决。

---

## 探针保留策略

**暂不撤**。等诊断 2 修完后，让粟粟再跑一次复现，看：
- `applyTreeData pathNodeIds` 是否稳定返回相同值（应该是 9）
- 切对话后不再有 `pathNodeIds=0` 的情况
- `geom size` 稳定
- `body rebuild` 低频

确认全绿再 remove probes。

探针位置（方便下次清理）：
- `CardFlowView.swift`：
  - line ~130 `_printBodyProbe(...)`
  - line ~230 `onChange(of: selectedConversation?.id)` 内第一行 print
  - line ~300 `onChange(of: isLoading)` 内 print + tick scrollToLast
  - line ~308 `onScrollGeometryChange` 内 print（用了 ScrollProbe struct）
  - line ~530 `ScrollProbe struct`（可删）
  - line ~97 `_printBodyProbe` static func（可删）
- `ConversationViewModel.swift`：
  - line ~288 `applyTreeData` 里的 print

---

## 时间线（commits）

| Commit | 做了什么 |
|---|---|
| cd878b2 | 第一批探针（convChange / isLoading / geom） |
| 7ba31b7 | 切对话重置 isAtBottom + 兜底 scrollToLast |
| 77ea3b3 | 第二批探针（body rebuild / applyTreeData） |
| 90e9c1b | **修诊断 1**：ContentHeightKey max → nextValue |
| （未） | **修诊断 2**：buildTreeInBackground root 选择确定性化 |

---

## 教训

1. **Dictionary 迭代顺序**：Swift 没保证，任何关键逻辑不能依赖 `dict.values.first(where:)`。必须排序或用确定性字段。
2. **PreferenceKey reduce 的副作用**：`max` 在 async layout 场景下会累积抖动。对"取瞬时值"的语义应该用 `nextValue()` 或 `value = max(value, nextValue())` **加容差判断**。
3. **SwiftUI @State 跨 view-hierarchy 泄漏**：view 条件渲染（if/else）会 unmount view，但父级的 @State 不会随之重置。切换场景时要主动 reset。
4. **探针大于推理**：花了两天时间靠推理找 scroll / pin / layout 的 bug，加两行 print 10 分钟定位到真正根因。**下次早点加探针**。

---

*等粟粟批准方案 A 或 B 后修诊断 2。*
