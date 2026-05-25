# Handoff: iOS 全局 wallpaper safe-area 问题 — 搁置存档

日期：2026-04-19
分支：`codex/theme-kelivo-settings`
存档 commit：**`866e2bc`**
状态：**暂停**。粟粟反馈 6 种 debug 模式"全都不对，各有各的诡异"。上架测试优先级更高，改换方案：**只聊天界面带背景图，不做全局 wallpaper**。后续上架后再回来琢磨这个问题。

---

## 1. 当前保留下来的产物

### 1.1 Research 文档（保留）

- [`research-ios-wallpaper-safearea-root-cause-2026-04-19.md`](./research-ios-wallpaper-safearea-root-cause-2026-04-19.md) — 查了 xcdocs + 网上（SwiftUI Field Guide / Swift with Majid / Fatbobman / Apple Forums / Chris Eidhof），列出 3 层事实 + 6 条候选 fix。
- [`research-ios-background-leak-cause-2026-04-18.md`](./research-ios-background-leak-cause-2026-04-18.md) — codex 的前一份 research，讲 leak 三层叠加。
- [`research-ios-chat-background-safearea-regression-2026-04-18.md`](./research-ios-chat-background-safearea-regression-2026-04-18.md) — codex 的前一份 research，讲 01e5fea / f2a27e2 两个回归。

### 1.2 Plan 文档（保留）

- [`plan-theme-chat-wallpaper-surface-2026-04-19.md`](./plan-theme-chat-wallpaper-surface-2026-04-19.md) — 第一版 plan，只修聊天页多层 mainBg 盖死 + iOSSafeAreaFill。部分落地（commit `0f496a7`）。
- [`plan-ios-background-leak-fix-2026-04-18.md`](./plan-ios-background-leak-fix-2026-04-18.md) — codex 的原 plan。
- [`plan-theme-background-regression-2026-04-18.md`](./plan-theme-background-regression-2026-04-18.md) — codex 的原 plan。

### 1.3 代码（保留，**暂时不要删**）

- `MemoryPalace/Utils/DebugRenderSettings.swift` — 两个枚举 + @AppStorage key
- `MemoryPalace/Views/DebugSettingsTab.swift` — 「设置 → 开发调试」页（iOS）
- `MemoryPalace/Views/ThemeBackgroundView.swift` — 4 种渲染模式 switch
- `MemoryPalace/Views/ContentView.swift` — wallpaper 挂法（zstackLayer mode 挪 ZStack）+ 页码 4 种模式 switch
- `MemoryPalace/Views/SettingsView.swift` — 「开发调试」tab 入口（iOS）

粟粟要求"先保留，后续可能还有用，上架前再删"。**不要 revert 这些 commit**，它们是后续继续查 bug 的入口。

### 1.4 关键 commit 链

- `0f496a7` fix: 聊天 wallpaper 失效 + iOS safe-area 白条（删 iOSSafeAreaFill + 聊天页多层 mainBg）
- `d79c67c` fix: iOS safe area 切割线 — 按页铺 backdrop（**已 revert**，别的路线）
- `c200add` Revert ↑ 那条
- `6fa7c32` fix: 左页 safe area 切割线 — 删 Sidebar 的 ignoresSafeArea()
- `866e2bc` ← **存档点**：debug 6 模式切换

从 `866e2bc` 出发做后续调查是安全的。

---

## 2. 已经验证为真的事实（可以直接引用，不用重查）

1. `applyingBackgroundImageSurfaceStyle` 在最初 `e351250` 会把 `mainBg/sidebarBg` 降 alpha，`01e5fea` 改成只降 bubble/accent — 是 codex 为了止 leak 走的一步。本轮保持 codex 的后版（mainBg 不降 alpha）。
2. **GeometryReader 在 `.background { ... }` 里被 parent size 限制**（[Swift with Majid](https://swiftwithmajid.com/2020/11/04/how-to-use-geometryreader-without-breaking-swiftui-layout/)）。
3. **`.ignoresSafeArea()` 加在 `.background` 的 content 上只改视觉不改 proxy.size**（[Fatbobman](https://fatbobman.com/en/posts/safearea/)）。
4. **view 完全在 safe area 内时 proxy.safeAreaInsets = 0**（[Apple Forum 709480](https://developer.apple.com/forums/thread/709480)）。
5. **TabView `.page` 样式 + ignoresSafeArea(.bottom) 和 home indicator 冲突**（[Apple Forum 762286](https://developer.apple.com/forums/thread/762286)）。

---

## 3. 粟粟反馈 "6 种都不对" 意味着什么

我在当前 research 里提的 3 条 wallpaper fix + 3 条 page indicator fix，**每一条都是围绕"让 ThemeBackgroundView 真正漫到全屏 safe area"展开的**。粟粟说全都不对，有三种可能：

**可能性 A**：8 种组合里可能有某些"部分对"，但粟粟整体放弃了不想逐一挑，觉得投入产出比低。
**可能性 B**：我漏了一个关键层级的 bug（例如 SidebarView 内部除了已删的 `.ignoresSafeArea()` 之外还有其他遮蔽层；或者 SwiftUI 的 UIHostingController 在 iOS 26.4 引入了新的 system background 覆盖行为）。
**可能性 C**：Image 的 scaledToFill + frame + clipped 组合本身有 iOS 26.4 特定 bug，不能用常规 SwiftUI 技巧修。

**要恢复追查，最稳的路径**：让粟粟一次性给 8 张不同组合的截图 + 一句话症状描述（见我最后那次消息），用真实数据交叉比对淘汰假设。在那之前任何"新写的 fix"都是赌。

---

## 4. 现在切换到的新方向（这份 handoff 之后要做的）

**新目标**：只有**聊天界面**能看到背景图，其它页面（列表 / 右页 / 设置 / 主题编辑 / 预览）不再有 wallpaper，用纯 `Theme.mainBg / Theme.sidebarBg` 实底。

**好处**：

1. 全局 safe-area 漏白不再是阻塞问题 — 列表/右页是实底 sidebarBg，根本没 wallpaper 可漏
2. 聊天页自己可以用 ZStack 底层 + clip 方式挂 wallpaper，scope 缩小好控
3. 功能上"用户能换背景图"这个核心诉求保留
4. 上架测试压力释放

**新方案改动点**（下一轮 plan 里写）：

- `ContentView` body 去掉 `.background { ThemeBackgroundView.ignoresSafeArea() }`
- `iOSChatPage` 和 `CardFlowView` 内部挂 `ThemeBackgroundView`（聊天页本地 wallpaper）
- macOS 的 `normalLayout` / `fullscreenLayout` 里聊天区域同样处理（如果粟粟要 iOS + macOS 统一）
- `SettingsView` 的 `.background { ThemeBackgroundView... }` 改成 `.background(Theme.sidebarBg)`
- ThemeEditor / ThemeSettingsTab 的"背景图预览"继续显示预览——但只在聊天页生效
- ThemeManager / AppTheme / ThemeAssetStore 不动，数据模型没变
- debug 代码保留

---

## 5. 后续回到这个问题时的建议起手式

1. 读本文档 + section 1.1 的三份 research
2. 回到 `866e2bc`（或当时 HEAD），跑 `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build`
3. 在 simulator 里开主题，启用一张 wallpaper，进「设置 → 开发调试」
4. **按 section 3.末 的 8 张图请求**，一次性收齐 8 张截图 + 症状描述
5. 根据真实现象淘汰假设，不要再瞎开新药方
6. 如果 8 种都不行，看 section 3.B/C 可能性，用 Apple Forum + iOS 26.4 release note 排 iOS 26.4 TabView 行为变化
7. 考虑做一个 `.onGeometryChange` 式的"实测 safeAreaInsets"可视化面板（4 个小数字贴屏幕四边），肉眼对比"SwiftUI 报的 safe area" vs "真实屏幕 safe area"
