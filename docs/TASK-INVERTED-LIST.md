# 任务：反转列表（长对话性能优化）

> 参考：粟粟的实现（/root/projects/SusuPalace origin/master 分支）
> 优先级：高（长对话越来越卡的根源之一）
> 预计改动：CardFlowView.swift 为主，约 5 个 Phase

---

## 背景

当前 CardFlowView 用正序 LazyVStack + onChange 滚到底部。问题：
- LazyVStack 正序排列，新消息在底部，每次都要 scrollTo bottom
- 长对话时 scrollTo 触发大量 view 计算
- 新消息出现时有明显跳动

粟粟的方案（学 Stream Chat SwiftUI）：ScrollView 整体翻转 + 每个 cell 翻回正 + ForEach 数据 reversed。这样 offset=0 就是最新消息，不需要 scrollTo。

---

## 核心原理

```
正常 ScrollView：         翻转后 ScrollView：
┌─────────────┐          ┌─────────────┐
│ 消息1（最旧）│          │ 消息N（最新）│ ← offset=0，直接可见
│ 消息2       │          │ 消息N-1     │
│ ...         │          │ ...         │
│ 消息N（最新）│ ← 要滚这│ 消息1（最旧）│
└─────────────┘          └─────────────┘
```

---

## 实施步骤

### Phase 1：添加翻转修饰符

在 CardFlowView.swift 顶部（import 之后）加：

```swift
/// ScrollView 整体翻 + 每个 cell 翻回正 = 最新消息在顶部（视觉底部）
struct FlippedUpsideDown: ViewModifier {
    func body(content: Content) -> some View {
        content
            .rotationEffect(.radians(Double.pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
extension View {
    func flippedUpsideDown() -> some View { modifier(FlippedUpsideDown()) }
}
```

### Phase 2：翻转 ScrollView + ForEach

找到 ScrollView 和 ForEach 的位置：

1. **ScrollView 内容末尾**加 `.flippedUpsideDown()`（整体翻转）
2. **ForEach 的每个 cell**（makeBubbleView 返回的 view）加 `.flippedUpsideDown()`（翻回正）
3. **ForEach 数据源** `currentPath` 改成 `currentPath.reversed()`
   - 或者用 `Array(currentPath.reversed())` 传给 ForEach

参考粟粟的实现：
```bash
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Views/CardFlowView.swift | grep -n "flippedUpsideDown\|reversed()\|\.reversed" | head -10
```

### Phase 3：修复 scrollTo 行为

翻转后物理方向反了：
- **之前**：scrollTo(lastNodeId, anchor: .bottom) = 滚到底部
- **现在**：scrollTo 可能不需要了（新消息直接在视口），但如果需要跳到某条消息（搜索结果），anchor 要改

具体检查所有 `scrollTo` 调用：
```bash
grep -n "scrollTo\|scrollToNodeId\|scrollToLastMessage" MemoryPalace/Views/CardFlowView.swift
```

- 删掉或简化 `onChange(of: viewModel.streamingText)` 里的自动滚底逻辑（翻转后不需要了）
- 搜索跳转的 scrollTo 保留，但 anchor 可能需要调整

### Phase 4：修复 isAtBottom 判断

如果有"是否在底部"的检测（用于显示"回到底部"按钮），逻辑要反转：
- **之前**：offset 接近 contentHeight = 在底部
- **现在**：offset 接近 0 = 在底部

搜索相关代码：
```bash
grep -n "isAtBottom\|atBottom\|scrollPosition\|onScrollGeometry" MemoryPalace/Views/CardFlowView.swift
```

### Phase 5：适配贴纸层 + 其他副作用

- 如果贴纸/附件位置依赖 ScrollView 方向，需要适配
- 检查下拉刷新（如果有）
- 检查键盘弹出时的滚动行为
- 检查群聊气泡的 senderName 显示是否正常

---

## 验证清单

1. [ ] 编译通过
2. [ ] 普通对话：新消息直接出现在视口底部，不跳动
3. [ ] 长对话（50+ 条）：滚动流畅，不卡顿
4. [ ] 搜索跳转：点搜索结果能跳到对应消息
5. [ ] 群聊：多角色气泡正常显示
6. [ ] 流式输出：token 逐字出现，不闪烁
7. [ ] "回到底部"按钮（如果有）正常工作

---

## 参考文件

- 粟粟实现：`/root/projects/SusuPalace` → `git show origin/master:MemoryPalace/Views/CardFlowView.swift`
- 粟粟做了 5 个 Phase 的反转列表，commit 搜 `scroll-perf` 或 `反转`
- Stream Chat SwiftUI 的反转列表方案（粟粟参考的）

---

## 注意事项

1. **不要碰 CLAUDE.md**
2. **每个 Phase 单独 commit**，方便回滚
3. Phase 2 改完就编译测试，不要等到 Phase 5
4. 如果某个 Phase 改崩了，回退这个 Phase 的改动继续下一个
5. commit message：`feat(scroll-perf): 反转列表 Phase N — xxx`

---

## ⚠️ 重要：上下文菜单翻转问题（粟粟踩过的坑）

粟粟做完反转列表后发现：iOS 长按上下文菜单也会跟着翻转（上下颠倒）。

她尝试过的方案：
- ❌ Option D（preview API 绕过）— spike 死刑，完全无效
- ✅ Phase 1 UIKit 桥 — 用 UIKit 的 UIContextMenuInteraction 替代 SwiftUI .contextMenu

**建议**：Phase 2 做完翻转后，先检查长按菜单是否正常。如果翻了，用 UIKit 桥方案：
```swift
// 在翻转的 cell 上用 UIViewRepresentable 包装 UIContextMenuInteraction
// 而不是 SwiftUI 的 .contextMenu modifier
```

参考粟粟的实现：
```bash
cd /root/projects/SusuPalace
git log origin/master --oneline | grep contextmenu
```
