# Research: B16 PROBE() 在 Release iOS 编译失败

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 触发：ultrareview `merged_bug_006`，紧急度实际 **P0**——下次 TestFlight Archive 必挂。

---

## 1. 现象（理论）

`xcodebuild -scheme MemoryPalaceIOS -configuration Release` 或 Xcode → Product → Archive 走 Release iOS 时编译报：

```
error: cannot find 'PROBE' in scope
```

Debug iOS 与 macOS（双 config）build 无影响。

## 2. 根因（已核对源码）

### 2.1 PROBE() 定义在 `#if DEBUG && os(iOS)`

`MemoryPalace/Utils/ProbeStickerSeed.swift:1`：
```swift
#if DEBUG && os(iOS)
import Foundation
import SwiftData
…
@inline(__always)
func PROBE(_ msg: String) { … }      // line 14
…
#endif                                 // 文件末尾
```

整个文件被 `#if DEBUG && os(iOS)` 包，意味着 `PROBE` 符号**只在 DEBUG iOS** 存在。

### 2.2 Release iOS 不带 `DEBUG`

`project.yml` 没自定义 `SWIFT_ACTIVE_COMPILATION_CONDITIONS`（已 grep 确认无该 key）。xcodegen 走 Xcode 默认行为：`DEBUG` 仅在 Debug build configuration 通过 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 定义，Release config 没这条。

→ Release iOS 编译时 `DEBUG` 未定义 → ProbeStickerSeed.swift 整个 `#if DEBUG && os(iOS)` 块 false → `PROBE(_:)` **不被声明**。

### 2.3 调用 site 的 `#if` 包裹审计

`grep -rn "PROBE(" MemoryPalace/`，逐文件核对：

| 文件 | 行号 | 包裹 | Release iOS 安危 |
|------|------|------|----------|
| `Utils/ProbeStickerSeed.swift` | 60, 126, 128 | 整文件 `#if DEBUG && os(iOS)` | ✅ 安全（与 PROBE 同 scope）|
| `Views/ContentView.swift` | 231, 238, 242, 245 | 都在 line 228 的 `#if DEBUG` 块内 | ✅ 安全 |
| `Views/Paging/PagingViewController.swift` | 193, 212, 270, 353 | 每条独立 `#if DEBUG` 包 | ✅ 安全 |
| **`Views/StickerCanvasLayer.swift`** | **26** | **仅 `#if os(iOS)`，无 DEBUG** | ❌ **Release iOS 报 cannot find PROBE** |
| **`Views/StickerGestureOverlay.swift`** | **13, 20, 28, 32, 38, 43, 114, 118, 120, 121, 124, 138, 224, 298, 328, 358, 360, 387, 403, 546（共 20 处）** | **整文件仅 `#if os(iOS)`，无 DEBUG** | ❌ **Release iOS 报 cannot find PROBE × 20** |

**两个文件 = 21 处调用 site 在 Release iOS 编译时找不到 PROBE 符号**。

### 2.4 验证 #if 包裹（实测代码）

`StickerCanvasLayer.swift:24-28`：
```swift
var body: some View {
    #if os(iOS)
    let _ = PROBE("[PROBE 贴纸 layer.body] editing=…")
    #endif
    return ZStack(alignment: .topLeading) {
```
**只 `#if os(iOS)`，无 DEBUG 嵌套**。

`StickerGestureOverlay.swift:1`：
```swift
#if os(iOS)
import SwiftUI
import UIKit
```
整文件 `#if os(iOS)` 包到末尾（line 551 `#endif`）。**所有内部 PROBE 调用都暴露在 Release iOS**。

## 3. 影响

### 3.1 紧急度
- 当前 commit `2dfd961` 标题 `chore: TestFlight 上架配置同步到 kelivo`——粟粟正在准备 TestFlight 上架
- TestFlight 上传走 Release Archive
- **下一次 Archive 直接编译失败**

### 3.2 受影响 build
| Build | 状态 |
|-------|------|
| iOS Debug Simulator | ✅ 通过（DEBUG 定义，PROBE 可见）|
| iOS Debug Device | ✅ 通过 |
| iOS Release / Archive | ❌ **编译失败** |
| macOS Debug | ✅ 通过（`#if os(iOS)` 排除文件）|
| macOS Release | ✅ 通过 |

### 3.3 PROBE 实际作用
PROBE 是 sticker 手势 / shield 调试日志，写 NSLog + `Documents/probe.log`。Release 用户**不应该**有这种日志（性能 + 隐私 + 文件污染），所以 Release 里就该是 no-op。

## 4. 修复方案候选

### A. 加 no-op stub（推荐）
在 `ProbeStickerSeed.swift` 末尾加：
```swift
#if !DEBUG && os(iOS)
@inline(__always)
func PROBE(_ msg: String) {}
#endif
```
- 优点：**1 处改动**，覆盖所有 21 个 call site，无 diff 噪声
- 优点：未来再加 PROBE 调用，无需挨个 `#if DEBUG`
- 优点：`@inline(__always)` + 空体 → Release 编译期被消除，零运行时开销
- 风险：低。stub 跟 DEBUG 版本签名一致（`func PROBE(_: String)`），Swift 类型推断不受影响

### B. 给 21 个 call site 各加 `#if DEBUG`（精细但繁琐）
比照 PagingViewController.swift 已有模式：
```swift
#if DEBUG
PROBE("…")
#endif
```
- 优点：跟项目里其他 PROBE 包裹方式一致
- 缺点：**21 处改动**，diff 大、噪声多
- 缺点：StickerGestureOverlay.swift 整文件 PROBE 密度高，包成蜂窝
- 缺点：未来加 PROBE 容易再次漏包（粟粟 memory `feedback_probes_over_reasoning` 鼓励"早点加探针"，那就要让加探针的成本足够低）

### C. 把 PROBE 定义提到 `#if os(iOS)` 范围（不改 DEBUG 限制）
在 ProbeStickerSeed.swift 把 `#if DEBUG && os(iOS)` 改成 `#if os(iOS)`，PROBE 始终定义。
- 缺点：Release 也会写 NSLog + probe.log，**性能 + 隐私 + 文件污染**
- ❌ **不推荐**——背离原始设计意图

### D. 把 sticker 那两个文件的 PROBE 全删
- 缺点：还在 sticker debug 阶段，删了下次出问题没探针
- ❌ 不推荐

---

## 5. 待确认（plan 阶段处理）

- [ ] 选 A 还是 B？我倾向 **A**（minimal diff + 防再撞），但 B 也 OK 看粟粟洁癖
- [ ] 如果选 A：no-op stub 该放 ProbeStickerSeed.swift 末尾还是单独 file？同 file 末尾最简单
- [ ] 修完后 build 验证：必须跑 **Release iOS** 才能验证（之前所有 build 都跑 Debug）
- [ ] B16 在 roadmap 标 ✅

---

## 6. 文件参考

- `MemoryPalace/Utils/ProbeStickerSeed.swift:1, 14` — PROBE 定义
- `MemoryPalace/Views/StickerCanvasLayer.swift:24-28` — 1 个未保护调用
- `MemoryPalace/Views/StickerGestureOverlay.swift:1, 13~546` — 20 个未保护调用，整文件 `#if os(iOS)`
- `MemoryPalace/Views/Paging/PagingViewController.swift:193, 212, 270, 353` — 已正确 `#if DEBUG` 包（参考样式）
- `MemoryPalace/Views/ContentView.swift:228-249` — 已正确 `#if DEBUG` 包（参考样式）
- `project.yml` — 无自定义 `SWIFT_ACTIVE_COMPILATION_CONDITIONS`，Release 不带 DEBUG

---

*research-only。粟粟选 A/B 后再写 plan。*
