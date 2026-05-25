# Plan: B16 PROBE Release no-op stub

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 依赖 research：`docs/research-probe-release-build.md`
> 状态：**plan-only，粟粟批注后再 implement，don't implement yet**

---

## 0. 已确认方向（粟粟 2026-04-25）

| 问题 | 决定 |
|------|------|
| 修复方案 | **A：no-op stub**（1 处改动，未来加 PROBE 无需挨个 `#if DEBUG`）|
| 范围 | 只 iOS（PROBE 本来就是 iOS-only）|
| 不动 | 21 处 call site 不动（保持当前 `#if os(iOS)` 包裹）；DEBUG 版 PROBE 行为不变 |

---

## 1. 目标

让 Release iOS / Archive build 编译通过。

**不做**：
- 不改 21 处 call site
- 不改 DEBUG 版 PROBE 的行为（NSLog + probe.log 写文件）
- 不改 macOS 路径（macOS 走 `#if os(iOS)` 排除整文件，无影响）
- 不解决 B17/B18/B19（独立处理）

---

## 2. 改动方案

### 2.1 在 `ProbeStickerSeed.swift` 末尾加 Release iOS no-op stub

`MemoryPalace/Utils/ProbeStickerSeed.swift` 文件末尾（最后一个 `#endif` 之后）加：

```swift
#if !DEBUG && os(iOS)
/// Release iOS no-op stub。让 21 处 PROBE call site（StickerCanvasLayer / StickerGestureOverlay）
/// 在 Release 编译时也找得到符号。`@inline(__always)` + 空体 → 编译期被消除，零运行时开销。
@inline(__always)
func PROBE(_ msg: String) {}
#endif
```

**位置**：放在文件末尾（已有 `#if DEBUG && os(iOS)` 块的 closing `#endif` **之后**），**新建**一个独立的 `#if !DEBUG && os(iOS)` 块。

### 2.2 为什么签名要严格一致

DEBUG 版定义：
```swift
@inline(__always)
func PROBE(_ msg: String) { ... }
```

stub 也用相同签名：
- 单参数 `_ msg: String`
- 同 `@inline(__always)`
- 顶层全局 func（不是 method）

这样 Swift 类型推断不变、call site 一行字都不用动。

### 2.3 为什么是 `#if !DEBUG && os(iOS)` 而不是 `#else`

可以用 `#else`，但分两个独立块更清晰：
- `#if DEBUG && os(iOS)` 定义 DEBUG 版（含 NSLog / probe.log 写盘）
- `#if !DEBUG && os(iOS)` 定义 Release stub

互斥、显式、未来好读。

### 2.4 macOS 不影响

PROBE 调用全部在 `#if os(iOS)` 包裹下，macOS build 时 stub 跟 DEBUG 版都不存在，但 call site 也不存在 → 无问题。

---

## 3. 风险与防守

### R1. stub 签名跟 DEBUG 版不一致 → 编译误差

防守：直接 copy DEBUG 版签名只去掉 body。已在 §2.2 强调。

### R2. `@inline(__always)` 在 Release 优化级别下行为

`@inline(__always)` 强制内联。空体内联 → 调用变成 NOP。Release 是 `-O` 优化，进一步消除 dead code。**最终汇编无残留**。

文档：[Swift Inline Attributes — Apple Forums](https://forums.swift.org/t/inline-always/) — `@inline(__always)` 即使在 -Onone 也内联，-O 下空函数被完全消除。

### R3. `Documents/probe.log` 已存在（DEBUG 时遗留），Release 不写新内容但旧文件还在

PROBE Release stub 不写文件，旧 probe.log 不影响行为。粟粟看着不舒服可以手动删。**不在本 plan scope**。

### R4. 加了 stub 会不会影响 DEBUG 版

不会。`#if DEBUG && os(iOS)` 跟 `#if !DEBUG && os(iOS)` 互斥。任意 build 只 active 其中一个。

### R5. xcodegen 是否真的不给 Release 配 DEBUG？

已 grep 确认 `project.yml` 无 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 自定义。xcodegen 走 Xcode 默认。**双保险**：implement 后跑 Release build 验证，build 通过 = 假设成立；若不通过，stub 没起作用，需要回头查 build settings。

---

## 4. 实施步骤

### Step 1：加 stub

- [ ] 编辑 `MemoryPalace/Utils/ProbeStickerSeed.swift`
- [ ] 在文件末尾（已有 `#endif` 之后）加 `#if !DEBUG && os(iOS)` 块 + 4 行 stub

完成标准：
- `git diff` 显示 ~6 行新增（包括注释 + 空行）
- 没动 21 处 call site
- 没动 DEBUG 版 PROBE

### Step 2：build 双 config 验证

- [ ] `xcodegen generate`（重新生成 .xcodeproj）
- [ ] **iOS Debug**：`xcodebuild -scheme MemoryPalaceIOS -destination 'generic/platform=iOS Simulator' build` → 通过 + DEBUG 版 PROBE 工作
- [ ] **iOS Release**：`xcodebuild -scheme MemoryPalaceIOS -configuration Release -sdk iphoneos build` → **通过**（关键验证）
- [ ] **macOS**：`xcodebuild -scheme MemoryPalace build` → 通过

完成标准：三种 build 都 `** BUILD SUCCEEDED **`。

### Step 3：Release iOS PROBE 不写日志验证（可选）

如果模拟器能跑 Release build，启动 app → home indicator 区点 / 长按 → 确认 `Documents/probe.log` 没新增行（stub 是 no-op 不写）。

完成标准：optional 验证项，不阻挡 commit。

### Step 4：commit + push + roadmap 标 B16 ✅

- [ ] `git add MemoryPalace/Utils/ProbeStickerSeed.swift docs/research-probe-release-build.md docs/plan-probe-release-build.md docs/PROJECT_ROADMAP.md`
- [ ] commit message: `fix(iOS): B16 PROBE Release no-op stub — Archive 编译通过`
- [ ] push 到 origin
- [ ] roadmap B16 行打 ✅

---

## 5. 影响范围

### 必改文件
- `MemoryPalace/Utils/ProbeStickerSeed.swift`（+~6 行 stub block）
- `docs/PROJECT_ROADMAP.md`（B16 标 ✅）

### 不改
- `MemoryPalace/Views/StickerCanvasLayer.swift`（call site 保持）
- `MemoryPalace/Views/StickerGestureOverlay.swift`（call site 保持）
- 其他所有 PROBE 相关文件

### 新增文件
- `docs/research-probe-release-build.md`（已写）
- `docs/plan-probe-release-build.md`（本文件）

---

## 6. 完成定义

1. iOS Release / Archive build 通过（Archive 不挂）
2. iOS Debug + macOS build 也通过（无回归）
3. DEBUG 版 PROBE 行为不变（NSLog + probe.log 还在）
4. Release 版 PROBE 是 no-op，不写日志
5. roadmap B16 标 ✅
6. commit + push

---

## 7. Todo Tracker

- [x] 1. ProbeStickerSeed.swift 末尾加 `#if !DEBUG && os(iOS)` no-op stub
- [x] 2. iOS Debug build（MemoryPalaceIOS scheme，iOS Simulator）
- [x] 3. **iOS Release build**（关键，关键验证通过：`-configuration Release -destination 'generic/platform=iOS'`）
- [x] 4. macOS build
- [x] 5. roadmap 标 B16 ✅
- [x] 6. commit + push

---

## 8. 状态

✅ **关档 2026-04-25** — 三种 build 全通过，Archive 不再挂。
