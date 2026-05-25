# Plan: iOS 键盘牵一发而动全身（B7）

> 2026-04-18
> 依赖：`docs/research-ios-keyboard.md`（已 ultrathink + 模拟器实测 + 粟粟批注）

## 目标

解决粟粟报告的五个键盘症状（S1~S5），但由于**模拟器无法复现 S1/S2/S3**，Plan 分两阶段：

- **Phase 1：真机 A/B Debug Build** — 加 4 个 UserDefault 开关，粟粟在 iPhone 18 上挨个对比，5 分钟把新假设 A'/B'/C'/S2 根因定位清楚
- **Phase 2：根据 Phase 1 结论写真正的 fix**（plan 末尾占位，等反馈）
- **S3+S4**（设置页/空 ScrollView 滑动收键盘）独立走，不依赖 Phase 1 —— 可以现在就做

## 原则

- **不改动默认行为**：所有开关**默认关闭** → debug build 装上粟粟不翻开关，行为和 release 完全一致
- **只在 DEBUG 编译时编译进去**：用 `#if DEBUG`，避免污染 TestFlight / release
- **每个开关单独可测**：粟粟一次只翻一个 toggle，报告结果

---

## Phase 1：真机 A/B Debug Build

### 1. 新建 `KeyboardDebugFlags.swift`

文件：`MemoryPalace/Utils/KeyboardDebugFlags.swift`（新建）

内容：
```swift
#if DEBUG
import SwiftUI

/// 键盘调试开关（仅 DEBUG build 启用）
/// 粟粟在设置 → 通用底部的「键盘调试」section 翻开关
enum KeyboardDebugFlags {
    @AppStorage("kbd.noInteractive") static var noInteractive = false
    @AppStorage("kbd.tapOverride")   static var tapOverride   = false
    @AppStorage("kbd.patchTabPan")   static var patchTabPan   = false
    @AppStorage("kbd.noAutomatic")   static var noAutomatic   = false
}
#endif
```

> **注**：`@AppStorage` 不能直接在 enum static 里用 —— 要么用 `UserDefaults.standard.bool(forKey:)` 包一层计算属性，要么用一个 `@Observable` 类单例。第一版 plan 先用 `UserDefaults.standard.bool(forKey:)` 纯静态读取；SwiftUI view 里再自己 `@AppStorage` 绑定。**这条细节 implement 阶段确认，不影响 plan 决策。**

#### Checklist
- [ ] 1a. 新建 `KeyboardDebugFlags.swift`，定义 4 个布尔 flag + 对应 key
- [ ] 1b. 添加到 `project.yml` 的 sources 里（或 xcodegen 自动捡起 Utils/）
- [ ] 1c. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS build` 验证

### 2. 在 `GeneralSettingsTab.swift` 底部加「键盘调试」section（仅 DEBUG）

文件：`MemoryPalace/Views/GeneralSettingsTab.swift`

位置：iOS 版 body 的 List 最底部（在其它 section 之后）

```swift
#if DEBUG
Section("键盘调试（DEBUG）") {
    Toggle("关闭 glass .interactive()（测 A'）", isOn: kbdNoInteractive)
    Toggle("加 onTapGesture 抢焦点（测 A'+）", isOn: kbdTapOverride)
    Toggle("给 TabView panGesture 打 delays=false（测 B'）", isOn: kbdPatchTabPan)
    Toggle("聊天页改 contentInsetAdjustment=.never（测 S2）", isOn: kbdNoAutomatic)

    Text("开关后**必须杀进程重启 app**。一次只翻一个。")
        .font(.caption2)
        .foregroundColor(Theme.textMuted)
}
.listRowBackground(Theme.mainBg)
#endif
```

#### Checklist
- [ ] 2a. 找到 `GeneralSettingsTab.swift` 的 iOS body
- [ ] 2b. 底部插入 `#if DEBUG` 包的 "键盘调试" section
- [ ] 2c. 每个 Toggle 绑 `@AppStorage` 到对应 key
- [ ] 2d. 文案清楚说明"翻开关要杀 app 重启"（safeAreaInset 和 UICollectionView.pan 的改动要重建 view 层才生效）

### 3. 改 `CardFlowView.swift` — 响应 flag A'/A'+

文件：`MemoryPalace/Views/CardFlowView.swift` (ChatInputBar body)

**现状** (:525-526)：
```swift
#if os(iOS)
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 20))
```

**改成**：
```swift
#if os(iOS)
.glassEffect(.regular.tint(Color.white.opacity(0.15)).conditionalInteractive(!kbdNoInteractive), in: .rect(cornerRadius: 20))
.optionalTapOverride(enabled: kbdTapOverride, action: { isFocused = true })
```

其中 helper（写在文件底部或 `Utils/GlassEffectHelpers.swift`）：
```swift
#if DEBUG
extension Glass {  // or whatever the modifier type is
    func conditionalInteractive(_ on: Bool) -> some Glass { on ? self.interactive() : self }
}

extension View {
    @ViewBuilder
    func optionalTapOverride(enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            self.contentShape(Rectangle()).onTapGesture(perform: action)
        } else {
            self
        }
    }
}
#endif
```

> **⚠️ iOS 26 `Glass` 类型 API 未必支持 conditional，implement 时若 API 不允许就直接在 ChatInputBar 里 if/else 两支 `.glassEffect(...)` 调用，不抽 extension。**

#### Checklist
- [ ] 3a. 在 ChatInputBar 里读两个 flag（`@AppStorage`）
- [ ] 3b. 根据 `kbdNoInteractive` 决定 `.glassEffect` 是否带 `.interactive()`（两支 if/else 最稳）
- [ ] 3c. 根据 `kbdTapOverride` 决定是否加 `.contentShape(Rectangle()).onTapGesture { isFocused = true }`
- [ ] 3d. release build（`#if !DEBUG`）保持 `.interactive()` 开、`.onTapGesture` 不加 —— 就是现在的行为

### 4. 改 `ContentView.swift` — 响应 flag B'/S2

文件：`MemoryPalace/Views/ContentView.swift`

**改动 1**（flag B'，给 TabView 底层 UICollectionView.pan 打延迟补丁）：

在 `disableBounceInSubviews(of:)` 里，拿到 collectionView 的那一支加：
```swift
if kbdPatchTabPan {
    collectionView.panGestureRecognizer.delaysTouchesBegan = false
    collectionView.panGestureRecognizer.delaysTouchesEnded = false
    collectionView.panGestureRecognizer.cancelsTouchesInView = false
}
```

**改动 2**（flag S2，强行把聊天页改 `.never`）：

```swift
let behavior: UIScrollView.ContentInsetAdjustmentBehavior =
    (iOSPage == 1 && !kbdNoAutomatic) ? .automatic : .never
collectionView.contentInsetAdjustmentBehavior = behavior
```

同样要同步改 `updateKeyboardBehavior(for:)` 里的那一行。

#### Checklist
- [ ] 4a. 在 ContentView 里读两个 flag
- [ ] 4b. `disableBounceInSubviews`：拿到 collectionView 后，flag 打开时设 `delaysTouchesBegan/Ended = false`
- [ ] 4c. `disableBounceInSubviews` + `updateKeyboardBehavior(for:)`：`contentInsetAdjustmentBehavior` 用 flag 控制
- [ ] 4d. release build（flag 全关）= 现行 `.automatic`/`.never` 路径不变

### 5. build + 装真机

#### Checklist
- [ ] 5a. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination "generic/platform=iOS" build`
- [ ] 5b. 装到粟粟 iPhone 18：用 Xcode Run 或 `xcrun devicectl device install app`
- [ ] 5c. 验证 release/flag-off 路径：所有 toggle 关着，键盘行为 = 装之前一样（不应有回归）

### 6. 粟粟真机操作手册（给粟粟的说明）

1. 全部关着，先记症状：点 TextField 是不是还要长按？
2. 只开 **"关闭 glass .interactive()"** → 杀 app 重启 → 测点 TextField
   - 键盘能立刻弹起？→ A 成立（但牺牲玻璃发光，不符合她要求，继续测别的）
   - 键盘更不弹？→ 和模拟器一样，A 被否 ✓
3. 关闭上一条，只开 **"加 onTapGesture 抢焦点"** → 重启 → 测
   - 点一下就弹？→ A' 成立（抢焦点有效，这是候选 fix）
4. 关闭上一条，只开 **"给 TabView panGesture 打 delays=false"** → 重启 → 测
   - 点一下就弹？→ B' 成立（TabView 底层 pan 延迟是真凶）
5. 关闭上一条，只开 **"聊天页改 .never"** → 重启 → 测
   - "全界面平移 20-30px" 消失？→ S2 由 `.automatic` 导致
   - 滑动到键盘不见？→ 副作用，需要后续补救
6. 把结果写进 plan 末尾的 "Phase 1 反馈" section，我根据结果写 Phase 2 真·fix。

---

## Phase 2：根据 Phase 1 反馈写真正的 fix

**占位 —— 等粟粟反馈。**

可能的方向（到时候挑一条）：
- 如果 A' 成立（`.onTapGesture` 抢焦点修 S1）→ release build 保留 `.interactive()` + 加 `.onTapGesture`
- 如果 B' 成立（TabView pan 延迟）→ `disableBounceInSubviews` 里无条件给 collectionView.pan 打 delays=false
- 如果 S2 由 `.automatic` 导致 → 无条件改 `.never`，并验证满屏对话时 safeAreaInset 仍给 ScrollView 正确 bottom inset（不然最后消息被 ChatInputBar 遮住）

---

## S3 + S4：设置页 / 空 ScrollView 滑动收键盘

**不依赖 Phase 1**，独立推进。

### S4 子任务：给常用设置子页加 `.scrollDismissesKeyboard(.immediately)`

按粟粟"先别搞麻烦"的原则，**只加常用页**：

- [ ] S4a. `APISettingsTab.swift:215` List 链上加 `.scrollDismissesKeyboard(.immediately)`
- [ ] S4b. `GeneralSettingsTab.swift` 的 List/Form 链上加
- [ ] S4c. `IOSMemoryPage`（在 MemorySettingsTab？） 的 List 链上加
- [ ] S4d. `IOSStickerPage`、`IOSAppearancePage`、`IOSRegexPage`、`IOSRightPanelPage` 的 List 链上加
- [ ] S4e. WorldBookPanelView / CharacterCardEditor / RegexScriptEditor 这些**先不加**（复杂页，按粟粟"别搞麻烦"延后）

### S3 子任务：搜索无结果空态点击收键盘

按粟粟答复"**点空白试试？**"：

- [ ] S3a. `SidebarView.swift:294-305` 的 "没有找到结果" VStack 外层加 `.contentShape(Rectangle()).onTapGesture { UIApplication.shared.sendAction(...) }`
- [ ] S3b. 同理给"回收站是空的" VStack（:506-517）加

### S5：回归验证 checklist

每次 Phase 2 改完 + S3/S4 改完，必须跑一遍：

- [ ] S5a. 聊天页键盘弹起：模型按钮/贴纸按钮/页面指示器**仍然自动隐藏**
- [ ] S5b. 顶部 VariableBlur：键盘起/落时视觉平滑
- [ ] S5c. 编辑 user 气泡（`isEditing=true`）键盘行为正常
- [ ] S5d. 贴纸面板 `showStickerPanel=true`：safeAreaInset 切到 Color.clear.frame(320) 后键盘面板仍然挂得上
- [ ] S5e. TabView 翻页：翻页后键盘仍能 dismiss（line 167 的 resignFirstResponder 还在）

---

## 文件改动总览

| 文件 | Phase | 改动量 |
|------|-------|--------|
| `MemoryPalace/Utils/KeyboardDebugFlags.swift`（新）| 1 | ~15 行 |
| `MemoryPalace/Views/GeneralSettingsTab.swift` | 1 | +~20 行（DEBUG section）|
| `MemoryPalace/Views/CardFlowView.swift` | 1 | +~10 行（两个 flag 分支）|
| `MemoryPalace/Views/ContentView.swift` | 1 | +~8 行（两个 flag 分支）|
| `MemoryPalace/Views/APISettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/GeneralSettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/MemorySettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/StickerSettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/AppearanceSettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/RegexSettingsTab.swift` | S4 | +1 行 |
| `MemoryPalace/Views/RightPanelSettingsView.swift` | S4 | +1 行 |
| `MemoryPalace/Views/SidebarView.swift` | S3 | +~6 行（两个 empty state tap）|
| `project.yml` | 1 | 可能无需改（`Utils/` 已包含）|

总计：**一个新文件 + ~50 行改动**，都小、可逆。

---

## Phase 1 反馈（粟粟 2026-04-19 iPhone 17 Air 真机实测）

| Toggle | 效果 | 全局平移 | 结论 |
|---|---|---|---|
| 只开 1（关 `.interactive()`）| 仍需按两下 | 仍上移 | **原假设 A 推翻**（`.interactive()` 不是吞 tap 的元凶）|
| **只开 2（`.onTapGesture` 抢焦点）**| **变灵，基本每次都成功** | 仍上移 | **A' 成立 → S1 最终 fix** |
| 只开 3（TabView pan delays=false）| 没 2 灵 | 仍上移 | B' 部分有效但 A' 是主因，3 不必要 |
| **只开 4（contentInsetAdjustment=.never）**| — | **不上移了** | **S2 根因确认 → 最终 fix**。副作用：键盘紧贴输入框（pixel-perfect），粟粟希望留 5px 间距 |

### 粟粟附加反馈
- **iPhone 17 Air 是主力**（不是之前以为的 iPhone 18；`iPhone18,4` 是内部型号编号 = 17 Air）
- **iPhone 14 本身就卡**（"什么都不开也卡"）—— 是 app 整体性能问题，与本 bug 无关，**另外开 roadmap 条目**
- **S2 全页面上移**不分设备、不分情况，一直存在，所有机型都需要修

### Phase 2 真·fix（已实施）

| 症状 | Fix | 文件 |
|------|-----|------|
| S1 | 保留 `.glassEffect(...interactive())` 视觉，HStack 外加 `.contentShape(Rectangle()).onTapGesture { isFocused = true }` 抢焦点 | `CardFlowView.swift` |
| S2 | `disableBounceInSubviews` 里 `contentInsetAdjustmentBehavior` 聊天页也用 `.never`（全部统一）；删掉 `updateKeyboardBehavior(for:)`（没用了）| `ContentView.swift` |
| Q1 5px | `.padding(.bottom, isFocused ? 5 : 8)` 代替 `isFocused ? 0 : 8` | `CardFlowView.swift` |
| cleanup | 删 `KeyboardDebugFlags.swift` + GeneralSettingsTab 的 `IOSKeyboardDebugSection`（A/B 开关使命完成）| 3 个文件 |

---

## Commit 策略

按 CLAUDE.md "改完 build 验证、方向错了 revert 不打补丁"：

- **commit 1**: `debug: add iOS keyboard A/B flags + GeneralSettings debug section`
- **commit 2**: `debug: wire kbdNoInteractive + kbdTapOverride in ChatInputBar`
- **commit 3**: `debug: wire kbdPatchTabPan + kbdNoAutomatic in ContentView`
- **commit 4**: (Phase 2) `fix: <S1 真·fix，按 Phase 1 结论>`
- **commit 5**: `fix: S4 scrollDismissesKeyboard across common settings pages`
- **commit 6**: `fix: S3 tap-to-dismiss on sidebar empty states`

每个 commit 后 push。
