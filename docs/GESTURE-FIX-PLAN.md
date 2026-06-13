# 左缘手势冲突修复方案（GESTURE-FIX-PLAN）

> 任务：左侧"防触碰"手势吞掉了世界书长按删除等交互。
> 目标：只接管**水平向右滑动**（拉侧边栏），不再干扰长按 / 竖直滚动。

## 1. 现状：手势是怎么设置的

侧边栏左缘拉出手势在 `MemoryPalace/Views/Paging/PagingViewController.swift`：

```swift
// viewDidLoad (L138-144)
let edgePan = UIPanGestureRecognizer(target: self, action: #selector(handleSidebarEdgePan(_:)))
edgePan.delegate = self
view.addGestureRecognizer(edgePan)
self.edgePanGesture = edgePan
scrollView.panGestureRecognizer.require(toFail: edgePan)

// UIGestureRecognizerDelegate (L420-423)
func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === edgePanGesture else { return true }
    return gestureRecognizer.location(in: view).x < 60
}
```

要点：

- 挂在 **PagingViewController.view** 上——即整个三页容器（page 0 聊天 /
  page 1 右栏插件 / page 2 记忆馆）的左缘 60pt 都被它覆盖。
- 是普通 `UIPanGestureRecognizer`，**不判方向**：起点在左 60pt 内、任意方向
  移动超过 ~10pt 系统阈值就 `.began`。
- `handleSidebarEdgePan` 里虽然有 `guard currentPage == 0`（L227），但那只是
  **不处理事件**；手势本身照样 `.began`，touch 已经被吞了。
- `cancelsTouchesInView` 默认 true：edgePan 一旦 `.began`，UIKit 给命中视图发
  `touchesCancelled`，SwiftUI 那边所有进行中的手势（长按、滚动）全部作废。

## 2. 影响面分析

左缘 60pt 竖条内、起点落在其中的所有触摸都受影响：

| 交互 | 页面 | 症状 | 机制 |
|---|---|---|---|
| 世界书长按删除（contextMenu） | page 1（RightPanelView → MemoryPanelView → WorldBookPanelView） | **长按被吞**（已确认） | 长按期间手指漂移 ≥10pt（任意方向）→ edgePan `.began` → touchesCancelled 杀掉 UIContextMenuInteraction 的 pending 长按 |
| 其他面板的 contextMenu / 长按（侧边栏对话行、记忆卡、贴纸等凡是行首贴左缘的） | 全部三页 | 同上 | 同上 |
| 竖直滚动（聊天消息列表、世界书列表、记忆馆列表） | 全部三页 | 从左缘起手的竖直滑动被劫持：列表不动，page 0 上侧边栏还会跟着竖直滑动的微小 x 分量抖动 | edgePan 对竖直移动也 `.began`，抢走 touch；page 0 上还会把 translation.x 发给 `sidebarEdgePanChanged` |
| 水平翻页（page 0→1 的左缘起手右滑以外的情况不受影响；左缘起手的**左滑**翻页） | 全部三页 | 左缘起手往左滑也被 edgePan 接管（pan 不分左右），翻页 pan 因 `require(toFail:)` 等待后失效 | `scrollView.panGestureRecognizer.require(toFail: edgePan)` |
| 按钮点击 | 全部三页 | 不受影响 | pan 需要位移，纯 tap 不触发 |

## 3. 修复方案：方向 + 页码双重门控

只动 `gestureRecognizerShouldBegin`，其余结构（挂载点、require(toFail:)、
NotificationCenter 转发）全部不变：

```swift
func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === edgePanGesture else { return true }
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }

    // 1) 仅左缘 60pt 起手（现有规则，保留）
    guard pan.location(in: view).x < 60 else { return false }

    // 2) 仅 chat 页（page 0）。handleSidebarEdgePan 里本来就 guard 了 page，
    //    但必须在 shouldBegin 就拒绝，否则 page 1/2 上手势照样 .began 吞 touch。
    let pageWidth = max(scrollView.frame.width, 1)
    let page = Int(round(scrollView.contentOffset.x / pageWidth))
    guard page == 0 else { return false }

    // 3) 仅"明显水平向右"的滑动：横向分量占优且向右。
    //    shouldBegin 在移动超过系统阈值、即将离开 .possible 时被询问，
    //    此刻 velocity 已经有有效方向信息。
    //    长按（基本无位移）、竖直滚动（|vy| ≥ |vx|）、向左滑都返回 false，
    //    recognizer 立即 .failed，touch 原封不动交还给 SwiftUI 层。
    let v = pan.velocity(in: view)
    return v.x > 0 && abs(v.x) > abs(v.y)
}
```

### 为什么这样就不吞长按了

`gestureRecognizerShouldBegin` 返回 false 时 recognizer 直接转 `.failed`，
**不会**给命中视图发 `touchesCancelled`——长按、竖直滚动从头到尾感知不到
edgePan 的存在。同时 `require(toFail: edgePan)` 的水平翻页 pan 在 edgePan
立即 fail 后零延迟恢复（这正是 L417-419 注释里原本的设计意图，只是当时
只做了 x<60 一个条件）。

### 备选方案（评估后不采用）

| 方案 | 不采用原因 |
|---|---|
| 换 `UIScreenEdgePanGestureRecognizer`（系统级左缘 pan，自带方向判定） | 触发区固定在系统边缘 ~13-16pt，比现在 60pt 窄很多，拉侧边栏手感变差；且与 `require(toFail:)` 的现有依赖关系需要重新调参 |
| 给世界书行加 `highPriorityGesture` / 调 SwiftUI 手势优先级 | 治标不治本：每个受影响面板都要逐个打补丁，漏一个吞一个 |
| edgePan.cancelsTouchesInView = false | 长按不被取消了，但滚动和 pan 同时生效会出现"侧边栏拉出的同时列表也在滚"的双响应 |

## 4. 改动清单

1. `MemoryPalace/Views/Paging/PagingViewController.swift`
   - `gestureRecognizerShouldBegin`：按上面代码加方向 + 页码门控（唯一改动点）。
   - `handleSidebarEdgePan` 里的 `guard currentPage == 0` 保留（双保险，无害）。

## 5. 验证清单

- [ ] page 1 世界书行（贴左缘）长按 → contextMenu 正常弹出，删除可点
- [ ] page 0 聊天列表从左缘起手竖直滚动 → 列表正常滚，侧边栏不抖
- [ ] page 0 左缘起手右滑 → 侧边栏正常拉出（跟手 + 松手 spring）
- [ ] page 0 左缘起手左滑 → 正常翻到 page 1（不再被 edgePan 拦截）
- [ ] page 1/2 左缘任何操作 → 与屏幕其他区域行为一致
- [ ] 侧边栏已打开时的左滑关闭（ContentView L315 的 DragGesture）不受影响
- [ ] 贴纸编辑模式（disableScroll=true）下左缘手势行为不回归

## 6. 风险

- 慢速、接近 45° 的右滑：`abs(v.x) > abs(v.y)` 判定下可能偶尔判负 →
  侧边栏没拉出来。用户重试即可，比吞长按的代价小得多。如果反馈手感变钝，
  可放宽为 `v.x > 0 && abs(v.x) > abs(v.y) * 0.8`。
- `shouldBegin` 时 velocity 为零的极端情况（理论上移动阈值已保证非零）：
  返回 false，等同长按路径，安全。
