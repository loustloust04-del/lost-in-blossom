# Research + Plan: B20 中段空白（part 1：贴纸出格撑虚高 ZStack）

> 2026-05-02
> 状态：H1 实测锁定 → 修法 B clamp + migration
> Part 2「真正的对话气泡丢失」是另一回事，待粟粟下次复现单独诊断

---

## 一、症状（粟粟两张截图）

### 截图 1（金瓶梅话本对话）

- 顶部 PinBar 下方：能看到上一段对话尾巴 "嘴撅成什么样" 残影
- 中段往下：**全空白**
- 底部：输入框 + 模型选择器
- ScrollView 滚动条：显示已滚到底

### 截图 2（同对话，再滑）

- 顶部 PinBar：还在
- 大段空白
- **屏幕中下偏右：一个斜放的黄色便签 "1"**（这是这条对话的唯一贴纸）
- 底部：输入框

---

## 二、H1 验证

**workaround 实测**：进入贴纸编辑模式，把"1"便签拖到对话顶部气泡附近 → **中段空白消失，气泡正常显示到底**。

✅ **H1 锁定**：贴纸 `positionY` 异常大，被算进 `StickerCanvasLayer.stickerExtent`，撑出 ZStack 巨大高度。

---

## 三、根因链

### 3.1 设计上为什么 sticker overlay 决定 ZStack 高度

`MemoryPalace/Views/CardFlowView.swift:191`：

```swift
ZStack(alignment: .topLeading) {
    LazyVStack(spacing: bubbleSpacing) { ForEach(currentPath) ... }   // 真气泡
    StickerCanvasLayer(stickerVM: ..., profileId: ...)                 // sibling
}
```

`StickerCanvasLayer.stickerExtent`（行 16-22）：

```swift
private var stickerExtent: CGFloat {
    let maxY = stickerVM.placedStickers.map { sticker -> CGFloat in
        let size = stickerVM.stickerSizes[sticker.id] ?? CGSize(width: 80, height: 80)
        return sticker.positionY + size.height * sticker.scale / 2
    }.max() ?? 0
    return maxY + 50
}

// body 内：
Color.clear
    .frame(maxWidth: .infinity)
    .frame(minHeight: max(stickerExtent, 1))  // 撑高
```

ZStack 自然 layout：`height = max(LazyVStack.h, stickerExtent)`。  
ScrollView contentSize 跟着 ZStack 走。

**这个设计本身没错**——是 04-25 修过的，目的是让用户拖到 LazyVStack 之外的贴纸还能接 touch（详见 git log `pre-kelivo-20260423`）。

### 3.2 真正的根因：drag 累加无 clamp

`positionY` 在 4 个地方被无界写入：

| 文件 | 行 | 操作 | 是否有 clamp |
|---|---|---|---|
| `StickerGestureOverlay.swift` | 255 | `sticker.positionY += t.y`（iOS drag delta 累加） | ❌ |
| `StickerGestureOverlay.swift` | 281 | `sticker.positionY += slideY`（iOS fling） | ❌ |
| `StickerCanvasLayer.swift` | 230 | `sticker.positionY = value.location.y`（macOS drag 绝对赋值） | ❌ |
| `StickerCanvasLayer.swift` | 259 | `sticker.positionY += velocity.height * friction`（macOS fling） | ❌ |

加上 drop / paste 创建时也直接用落点 y，无 clamp。

### 3.3 链式膨胀机制

1. 上一个 sticker 落在 `positionY = N` → `stickerExtent = N + 50`
2. ZStack 撑到 N+50 → ScrollView contentSize 大
3. user 拖贴纸时，可拖到 N+1000（仍在 ScrollView 范围内）
4. drag end 写入 `positionY = N + 1000` → `stickerExtent = N + 1050`
5. ZStack 又撑大 → 下次 user 又能拖更远 → 链式膨胀

「金瓶梅话本」那个 "1" 便签大概率就是被 fling 飞远的（短暂操作 → velocity 大 → slideY 累加）。

### 3.4 为什么粟粟看到的是"中段下面全空白 + 一个孤立贴纸"

- LazyVStack 实际气泡区只有几条（"垃圾桶 🔞" 对话不长）→ 高度可能 800pt
- 贴纸 positionY 可能飞到 5000+pt → stickerExtent ≈ 5050pt
- ZStack height = max(800, 5050) = 5050
- ScrollView contentSize ≈ 5050pt
- 视觉上：[0, 800] 是气泡，[800, 5000] 是空白，5000 处有一个孤立贴纸

完全符合截图。

---

## 四、修法选型

### 选 B（clamp positionY），舍 A、C

| 方案 | 评价 |
|---|---|
| **A. cap stickerExtent 在 LazyVStack 高度** | ❌ 需要 GeometryReader 测 LazyVStack 高度（memory `feedback_swiftui_geometry_apis_lazyvstack_stuck.md`：在 LazyVStack 里不可靠）；破坏 04-25 sibling 设计的初衷（"拖到 LazyVStack 之外能接 touch"） |
| **B. clamp positionY 在合理上限内** | ✅ 治本，不依赖 layout pass，保留合法"末尾下方贴"能力；migration 一次性修存量 |
| **C. UI 提示 + scrollTo 跳过去** | 治标不治本，留 v2 体验补丁 |

---

## 五、实施

### 5.1 clamp 上限算法

```swift
maxAllowed = max(stickerVM.bubblePositions.values.max() ?? 0,   // 已渲染 bubble 最远 midY
                 CGFloat(currentPathCount) * 200                  // 粗估 LazyVStack 高度（保守）
                ) + 1500                                           // buffer：用户在末尾下方 1500pt 内合法
```

- **drag end / fling end** 时 `bubblePositions` 已填（user 必然渲染过这些 bubble），用 `bubblePositions.max()` 准确
- **migration** 时 `bubblePositions` 可能空（刚切对话），fallback 用 `currentPathCount × 200`（200pt 是保守 bubble 估算）
- 1500 buffer：覆盖最后一个 bubble 估算误差 + 给用户在末尾下方贴的空间

### 5.2 调用点（5 处）

| 调用点 | 文件 |
|---|---|
| iOS drag `.ended` 后 | `StickerGestureOverlay.swift:290` |
| macOS drag `.onEnded` 后 | `StickerCanvasLayer.swift:260` |
| sticker drop 创建 | `StickerViewModel.swift:251` |
| sticker drop 创建（另一路径） | `StickerViewModel.swift:276` |
| sticker paste 创建 | `StickerViewModel.swift:391` |
| migration on conv load | `CardFlowView.onChange(isLoading)` |

### 5.3 API 设计

`StickerViewModel` 加两个 method：

```swift
@MainActor
func clampStickerY(_ sticker: PlacedSticker, currentPathCount: Int) {
    let bubbleMaxY = bubblePositions.values.max() ?? 0
    let estimatedFullH = CGFloat(currentPathCount) * 200
    let maxAllowed = max(bubbleMaxY, estimatedFullH) + 1500
    if sticker.positionY > maxAllowed {
        sticker.positionY = maxAllowed
    }
}

@MainActor
func migrateStickerPositions(currentPathCount: Int, context: ModelContext) {
    // bubblePositions 可能空，用 estimatedFullH only
    let maxAllowed = CGFloat(currentPathCount) * 200 + 1500
    var migrated = 0
    for sticker in placedStickers where sticker.positionY > maxAllowed {
        sticker.positionY = maxAllowed
        migrated += 1
    }
    if migrated > 0 {
        try? context.save()
        print("[StickerMigration] clamped \(migrated)/\(placedStickers.count), maxY=\(maxAllowed), pathCount=\(currentPathCount)")
    }
}
```

### 5.4 `currentPathCount` 怎么传给 StickerCanvasLayer

加 prop：

```swift
struct StickerCanvasLayer: View {
    var stickerVM: StickerViewModel
    let profileId: String
    let currentPathCount: Int   // 新加
    ...
}
```

CardFlowView 调用时传 `viewModel.currentPath.count`。
StickerGestureOverlay 通过 parent.currentPathCount 拿到。

---

## 六、Task Checklist

- [ ] 1. `StickerViewModel.swift`：加 `clampStickerY` + `migrateStickerPositions`
- [ ] 2. `StickerViewModel.swift` L251/276/391：drop/paste 后 clamp
- [ ] 3. `StickerCanvasLayer.swift`：加 `currentPathCount` prop；macOS drag `.onEnded` 后 clamp
- [ ] 4. `StickerGestureOverlay.swift`：iOS drag `.ended` 后 clamp（通过 parent 拿 currentPathCount）
- [ ] 5. `CardFlowView.swift`：调 `StickerCanvasLayer` 传 `currentPathCount`；加 `.onChange(isLoading)` migration hook
- [ ] 6. `xcodegen generate && xcodebuild ... build` macOS 验证编译过
- [ ] 7. 粟粟在 Xcode 选 17 Air dev build → 进入金瓶梅对话 → 看 console `[StickerMigration]` log + 贴纸位置自动 clamp 回来
- [ ] 8. commit + push
- [ ] 9. 进 PROJECT_ROADMAP.md 标 B20 part 1 ✅，留 part 2「真正气泡丢失」

---

## 七、Part 2 待续：真正的"对话气泡丢失"

粟粟说"有的是真的对话气泡丢失，不只是贴纸出格"。这次没复现，留待下次。可能 hypothesis：

- **H4**：MessageNode tree 在某些 path 上 children 链断（`effectiveChildrenMap` filter 掉了什么）
- **H5**：导入 Claude.ai 对话时 `parent_message_uuid` 链有断点，buildTreeInBackground 走到断点就停
- **H6**：SwiftData lazy fetch 在路线 B 单 container 改造后某 fetch 漏 profileId 或 stale ref

下次粟粟看到"明显气泡数量比预期少"时，记下：
- 对话 ID
- 预期 vs 实际气泡数量
- 是否每次进都少同样的几条 / 还是随机

我加 `[PROBE]` 在 `applyTreeData` 打印 `pathNodeIds.count` vs `nodeMap.count`，就能区分是 tree build 漏了 还是 SwiftData fetch 漏了。

---

*粟粟"自己看着办" → B 选定 → 直接 implement。*
