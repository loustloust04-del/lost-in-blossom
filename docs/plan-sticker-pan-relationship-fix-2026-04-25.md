# Plan: 修贴纸单指拖"时灵时不灵" — 方案 B (`_UIRelationshipGestureRecognizer` simultaneously)

> 日期：2026-04-25
> Research：`docs/research-sticker-gesture-regression-2026-04-24.md`（已更新）
> Bug：长按贴纸进编辑模式后**头几次单指拖完全不响应**，必须先做一次双指 pinch/rotate 才能解锁单指拖。
> 状态：**plan-only，don't implement yet**，等粟粟批注。

## 根因摘要（log 实测）

`stickerItem.onLongPressGesture(0.3s)` 进编辑模式 → SwiftUI 把内部私有 recognizer **`_UIRelationshipGestureRecognizer` 置 state=3 (.recognized/.ended)** → 它 require-to-fail 我们的 `SingleFingerPanGesture`（因为我们 `shouldRecognizeSimultaneouslyWith` 对它返回 `false`）→ pan 卡死 `.possible` → 用户拖不动。

双指 pinch/rotate 触发后，iOS 把 `_UIRelationshipGestureRecognizer` reset 到 state=0 → pan 解锁。

## 为什么选 B（不选 A 或 C）

- **A**（对所有 system recognizer 返回 true）：副作用窗口太大，可能让 SwiftUI `.contextMenu` 长按和 pan 同时识别，引入未知 iOS 26 UI 怪行为。
- **B**（只对 `_UIRelationshipGestureRecognizer` 返回 true）：精准对症，副作用窗口最小。
- **C**（废弃 SwiftUI `.onLongPressGesture` 改 UIKit）：最干净但改动大，涉及 stickerItem.onLongPressGesture / 编辑模式入口 / contextMenu — 一旦改坏一处贴纸入口都不能用。

## B 方案：具体改动

### 改动 1：StickerGestureOverlay.swift Coordinator delegate

**文件**：`MemoryPalace/Views/StickerGestureOverlay.swift`
**位置**：line ~480 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`

```swift
// 现在：
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    let isMultiTouch = { (g: UIGestureRecognizer) -> Bool in
        g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer
        || (g is UILongPressGestureRecognizer && g.numberOfTouches >= 2)
    }
    if isMultiTouch(gestureRecognizer) || isMultiTouch(other) { return true }
    return false
}

// 改成：
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    let isMultiTouch = { (g: UIGestureRecognizer) -> Bool in
        g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer
        || (g is UILongPressGestureRecognizer && g.numberOfTouches >= 2)
    }
    if isMultiTouch(gestureRecognizer) || isMultiTouch(other) { return true }

    // [FIX 单指拖时灵时不灵]
    // SwiftUI 注入的私有 _UIRelationshipGestureRecognizer 在 .onLongPressGesture
    // 进编辑模式后停留在 state=3 (.recognized/.ended) ~几秒，require-to-fail
    // SingleFingerPanGesture，导致 pan 卡 .possible 不能 .began。
    // 我们对它返回 simultaneously=true 解开阻塞 — pan 仍按自己 threshold 识别。
    // 用 className 匹配（私有类，无符号）。
    let otherClassName = String(describing: type(of: other))
    if otherClassName.contains("_UIRelationshipGestureRecognizer") {
        return true
    }

    return false
}
```

### 改动 2：探针保留还是清

- 保留 PROBE — 装机测时还能看 fix 效果（log 应该看到 `state=3` 时 simul=true，pan 顺利 .began）
- 不清，等真机验证 fix 后一起 git revert 探针 commits

## 验证步骤

### Step 1：build 绿
```bash
cd .claude/worktrees/theme-kelivo-settings
xcodegen generate
xcodebuild build -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
```

### Step 2：claude 自己跑真机 UITest 验证 fixture 路径
```bash
xcodebuild test -scheme StickerProbeUITests -destination 'platform=iOS,id=3D915F44-2AEF-5E1E-B49C-1EE41B65BB9A' -allowProvisioningUpdates
xcrun devicectl device copy from --device 3D915F44-2AEF-5E1E-B49C-1EE41B65BB9A \
  --source Documents/probe.log --destination /tmp/probe-fix-v1.log \
  --domain-type appDataContainer --domain-identifier com.susu.MemoryPalace.ios
grep -E "Relationship|handlePan|shouldSimul.*Relationship" /tmp/probe-fix-v1.log | head -30
```
**期望 log**：shouldSimul `_UIRelationshipGestureRecognizer` → **true**（不再 false），pan **第一次就能 .began**。

### Step 3：粟粟真机手动验证（5 秒）
- `git pull` → Cmd+Shift+K → Cmd+R
- 进真实贴纸对话 → 长按进编辑 → **马上**单指拖（不用先双指）
- 应该一下就跟手

### Step 4：副作用回归
- contextMenu 长按弹菜单仍正常？
- 退出编辑后长按贴纸进编辑仍正常？
- 双指 pinch/rotate 仍正常？
- 切对话 / 切楼层 / sidebar 划手势仍正常？

## Task Checklist

- [x] T1：改 StickerGestureOverlay.swift 的 shouldRecognizeSimultaneouslyWith — commit `46399ea`
- [x] T2：xcodegen + build iOS 模拟器绿
- [x] T3：claude 自己跑真机 UITest（fixture 路径），devicectl 拉 log，确认 shouldSimul → true + handlePan .began fire
- [x] T4：粟粟真机手动验证 — 反馈"还是单指第一次不灵"，发现第二个根因 contentHeight=0 让 overlay frame=1pt
- [x] T4.5：方案 3 v1（哨兵 GeometryReader maxY）— commit `d208797` — **失败**：哨兵 maxY 也 stuck 0
- [x] T4.6：方案 3 v2（onScrollGeometryChange contentSize）— **失败**：layout 时不 fire
- [x] T4.7：方案 3 v3（onGeometryChange）— **失败**：嵌套下也 stuck
- [x] T4.8：方案 2 v1（.overlay() 替代 ZStack sibling）— **失败**："时灵时不灵"，sticker 拖到 LazyVStack 外丢失
- [x] T4.9：方案 2 v2（ZStack sibling + stickerExtent 自声明 minHeight）— commit `ba15466` — **成功** ✓
- [x] T5：粟粟回归确认 — pan/pinch/rotate 全 work，frame 自适应 571pt → 45950pt
- [ ] T6：探针 + fixture + UITest target 暂留作安全网（粟粟决定），稳定几天后撤
- [x] T7：memory 沉淀 — `feedback_uirelationship_blocks_uipan.md` + `feedback_swiftui_geometry_apis_lazyvstack_stuck.md`，MEMORY.md 索引更新
- [x] T8：commit + push + tag `sticker-fix-final`

## 完成总结

**最终生效的 3 个 fix（叠加）**：

1. `46399ea` Plan B — `_UIRelationshipGestureRecognizer` simultaneously：解 "长按进编辑后头几次单指拖完全无响应、必须先双指激活" 的 root cause
2. `ed195c2` SingleFingerPan .began 后容忍误触：解 "拖到一半第二指意外触屏 → pan 自杀"
3. `ba15466` ZStack sibling + stickerExtent：解 "sticker 拖到 LazyVStack frame 外就接不到 touch" 的根本结构问题

**实测数据**（粟粟真机 iPhone Air iOS 26.4）：
- pan 成功 8 次 / 14 次 touchesBegan（剩 6 次是 tap 短触）
- handlePan .changed 564 次持续 fire
- frame 自适应 571pt → 45950pt 跟着 sticker 走

**Plan doc 状态**：完成，归档供后续 reviewer 参考。

## 回滚

如果 fix 引入新问题（比如 contextMenu 长按怪 / 编辑模式入口失灵）：
- `git revert` 这一个 commit（独立于探针 commit）
- 退到方案 C（写 UIKit longPress 替代 SwiftUI onLongPressGesture），更结构性但改动更大

## 待粟粟批注 / 决定

1. **方案 B 描述里的 className 匹配** `String(describing: type(of: other)).contains("_UIRelationshipGestureRecognizer")` —— iOS 26 内部类名稳定吗？以后 iOS 升级类名变了 fix 失效，能接受吗？（可加 fallback：所有非 UIKit 公开类的 system recognizer 都返回 true，更 robust 但更接近方案 A）
2. **T6 的"正经 fix"**（contentHeight 测量根因）粟粟想让我现在做，还是先确认 B 解决了"时灵时不灵"再说？我倾向先确认 B，再做 T6。
3. **T7 memory 沉淀**默认做？
