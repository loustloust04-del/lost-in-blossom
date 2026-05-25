# Plan: 修 codex 两个回归 — 聊天 wallpaper 失效 + iOS safe-area 白条

日期：2026-04-19
分支：`codex/theme-kelivo-settings`
前置文档：
- [research-ios-chat-background-safearea-regression-2026-04-18.md](./research-ios-chat-background-safearea-regression-2026-04-18.md)（codex 写的根因，我独立对着代码核验过为真）
- [plan-ios-background-leak-fix-2026-04-18.md](./plan-ios-background-leak-fix-2026-04-18.md)（codex 上一轮 plan，原则对、落地选择过激）

状态：**Draft，等粟粟批注**

---

## 1. 目标

这一轮不是加功能，是**把 codex 上一轮修 wallpaper leak 造成的两个副作用回滚回到正道**。

- **回归 A**：开了背景图主题，聊天页主背景**完全看不到 wallpaper**（被 `Theme.mainBg` 连刷 4 层实底盖掉）
- **回归 B**：`iOSSafeAreaFill` 挂 iOS root 层，和聊天底部的 `safeAreaInset`/`overlay`/页码点 overlay 五层打架 → 底部白条 + 页码飘

---

## 2. 根因核对（我独立看过代码，不是只信 codex 的 research）

### 2.1 回归 A 的来源

`MemoryPalace/Models/AppTheme.swift:274` — `applyingBackgroundImageSurfaceStyle(for:)`

初始 commit `e351250` 里原本是：
```swift
copy.mainBg = copy.mainBg.multipliedAlpha(0.88)       // light
copy.sidebarBg = copy.sidebarBg.multipliedAlpha(0.82)
```

`01e5fea` 把这两行删了，只保留 `userBubble / assistantBubble / accent` 的降 alpha。

同时，聊天页多层实底盖死：
- `MemoryPalace/Views/ContentView.swift:276` — `iOSChatPage.background(Theme.mainBg)`（整页）
- `MemoryPalace/Views/CardFlowView.swift:142` — `ScrollView.background(Theme.mainBg)`
- `MemoryPalace/Views/CardFlowView.swift:226` — 外层 `VStack.background(Theme.mainBg)`
- `MemoryPalace/Views/CardFlowView.swift:149-154` — 顶部 overlay 渐变起点是不透明 `Theme.mainBg`
- `MemoryPalace/Views/CardFlowView.swift:624-629` — ChatInputBar 底部渐变终点是不透明 `Theme.mainBg`
- `MemoryPalace/Views/CardFlowView.swift:81` — loading 态 `.background(Theme.mainBg)`

结果：wallpaper 在 root 层确实渲染了（`ThemeBackgroundView` 本身健康），但被上面这 6 层不透明 mainBg 依次盖死，基本穿不透到聊天主内容区。

### 2.2 回归 B 的来源

`MemoryPalace/Views/ContentView.swift:291` — `iOSSafeAreaFill(topInset:bottomInset:)` 在 iOS ZStack root 里刷两条 `currentIOSPageSurface` (mainBg/sidebarBg) 色带：
- 顶部 `height: topInset`
- 底部 `height: bottomInset + 28` ← 多刷 28pt，硬编码无来由
- 通过 `.ignoresSafeArea(edges:)` 拉进 safe area

聊天页底部本来就已经有：
1. `CardFlowView.swift:187` — ChatInputBar 通过 `.safeAreaInset(edge: .bottom, spacing: 0)` 插入
2. `CardFlowView.swift:228-252` — StickerKeyboardPanel 通过 `.overlay(alignment: .bottom)` + `.ignoresSafeArea(.container, edges: .bottom)` 叠
3. `ContentView.swift:174-187` — 页码点在 root ZStack 的 VStack+Spacer 里，`.padding(.bottom, max(safeAreaInsets.bottom, 12) + 8)`
4. ChatInputBar 背景本身是 VariableBlur + 从透明 → mainBg 的渐变（`CardFlowView.swift:619-639`），不是实底

再加 root 级的 `iOSSafeAreaFill` → 五层互不知情。

---

## 3. 设计决策

### 3.1 分层模型：structure vs atmosphere

原 plan（`plan-ios-background-leak-fix-2026-04-18.md` step 2）的原则对：
> `mainBg` / `sidebarBg` 不能继续既当结构底，又当氛围半透明层。

codex 的执行方向错了 — 他选择让 `mainBg/sidebarBg` 永远实底，把"氛围"整个取消。本轮方向：
- **`mainBg` / `sidebarBg` 保持"默认不透明实底"**（作为结构骨架，比如输入栏背景、按钮底、卡片填充），不再在 `applyingBackgroundImageSurfaceStyle` 里降 alpha
- **聊天主内容区、列表卡片之外的留白、右页工具页卡片之外的留白 — 不主动刷 mainBg 背景**，让 root `ThemeBackgroundView` 自然透出
- 顶底 blur 渐变可以保留 "从 mainBg 渐到透明"，作为视觉缓冲 — 在内容边缘让阅读区清晰

### 3.2 iOSSafeAreaFill 整个删掉

iOS 的 safe area 遮蔽应该由各页自己决定，不在 root 层无差别刷。替代方案：
- 左页 (Sidebar)：如果 Sidebar 顶部/底部设计需要 mainBg 保底，Sidebar 自己的 root 用 `.background(Theme.sidebarBg).ignoresSafeArea()` 解决
- 中页 (Chat)：输入栏底部 blur 渐变已经做了视觉收口；顶部工具栏下那段渐变 overlay 也已经做过 → 不需要再补色条
- 右页 (Dashboard)：类似左页

所以 `iOSSafeAreaFill` 的存在本身就是错层，删。

### 3.3 root wallpaper 挂法

当前 `ContentView.swift:95` 的挂法：
```swift
.background {
    ThemeBackgroundView(...)
        .ignoresSafeArea()
}
```
`ThemeBackgroundView` 本身干净（ZStack { fill; image.overlay(gradient).opacity(...) }），这个挂法**保留不动**。它负责全屏渲染 wallpaper 的 fill + image。上面的 page surface 决定在哪些区域让 wallpaper 透出。

### 3.4 页码点放哪

当前放在 root ZStack 的 VStack + Spacer（`ContentView.swift:174-187`），位置 `padding(.bottom, max(safeAreaInsets.bottom, 12) + 8)`。

问题：它在 root 层，会飘到聊天底栏上面。

方案：
- A. 保持 root 层，但在聊天页(iOSPage == 1)时藏起来（只在列表/右页显示）
- B. 移进各页内部
- C. **保持 root 层 + 移到聊天底栏之上更远的位置，加半透明小胶囊背景**

我偏 A。理由：聊天页底栏视觉已经很满（输入栏 + 贴纸入口 + 模型选择 + 发送键），页码点再叠上去纯噪音，且键盘弹起时它本来也会被 `!isKeyboardVisible` 隐藏，所以聊天页默认不显示页码点也不违和。列表页/右页才需要页码点告诉用户"还有两张卡可以滑"。

**（这一条请粟粟确认，A/B/C 都是可接受的实现）**

---

## 4. 修改清单

每条给 file:line + 现状 + 目标改法。

### 4.1 `MemoryPalace/Models/AppTheme.swift:274-291`

**现状**：`applyingBackgroundImageSurfaceStyle` 只降 bubble/accent alpha，mainBg/sidebarBg 不降。
**目标**：函数本身保持现状（不降 mainBg/sidebarBg）—— 这一条是对的，mainBg 作为结构 token 就该实底。回归 A 要修的不是这里，是"哪些页面区域使用 mainBg 盖死内容"。
**改动**：0 行（保留）。

### 4.2 `MemoryPalace/Views/ContentView.swift:276`

```swift
iOSChatPage {
    ZStack(alignment: .top) { ... }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.mainBg)   // ← 删掉
}
```
**理由**：让聊天页自然透到 root wallpaper。
**改动**：删 `.background(Theme.mainBg)` 一行。

### 4.3 `MemoryPalace/Views/ContentView.swift:287`

```swift
iOSDashboardPage { ... }
.background(Theme.sidebarBg)   // ← 删掉或改
```
**现状**：右页整页刷 sidebarBg，盖死。
**目标**：右页主内容区也应能透 wallpaper，但右页各个工具卡（贴纸库/记忆库/预设等）自己有卡片背景，够用。
**改动**：删 `.background(Theme.sidebarBg)` 或改成只在工具卡位置刷。**第一轮先整页删**，看视觉。

### 4.4 `MemoryPalace/Views/ContentView.swift:149-217` — iOSLayout 全段

**现状**：ZStack root 里包含 `iOSSafeAreaFill` + TabView + 页码点 overlay。
**目标**：
- 删除 `iOSSafeAreaFill` 调用（152 行）
- 删除 `iOSSafeAreaFill(topInset:bottomInset:)` 函数定义（291-305 行）
- 删除 `currentIOSPageSurface` 计算属性（307-316 行）
- 页码点：改成 iOSPage != 1 时才显示（或粟粟选 B/C 另议）

**改动**：删 3 段共约 30 行。

### 4.5 `MemoryPalace/Views/CardFlowView.swift:142`

```swift
ScrollView { ... }
.background(Theme.mainBg)   // ← 改为透明（删掉）
```
**理由**：让聊天气泡之间的空隙透 wallpaper。气泡本身有 userBubble/assistantBubble 颜色，不透明，不会撑破结构。
**改动**：删 `.background(Theme.mainBg)` 一行。

### 4.6 `MemoryPalace/Views/CardFlowView.swift:149-154`

顶部渐变 overlay 起点是 `Theme.mainBg`（实底）。
**目标**：保持"从实底渐变到透明"的氛围 blur 效果 —— 这个是正确设计，顶部工具条下方需要渐变遮蔽保证标题可读。
**改动**：0 行。保留。

### 4.7 `MemoryPalace/Views/CardFlowView.swift:226`

```swift
VStack(spacing: 0) { ... }
.animation(...)
.background(Theme.mainBg)   // ← 删掉
```
**理由**：外层 VStack 又刷一层 mainBg，重复，盖死 wallpaper。
**改动**：删 `.background(Theme.mainBg)` 一行。

### 4.8 `MemoryPalace/Views/CardFlowView.swift:277`

```swift
.toolbarBackground(Theme.mainBg, for: .navigationBar)
```
**现状**：iOS 导航栏背景 = mainBg。聊天页顶部其实是自己 overlay 的 ZStack（244-271 行），不走 NavigationBar，`.toolbarBackground` 这里其实不一定生效（CardFlowView 被 iOSChatPage 包裹但 iOSChatPage 没 NavigationStack）。
**目标**：先保留，修完别的看是否有剩余视觉 bug 再决定。
**改动**：0 行（观察）。

### 4.9 `MemoryPalace/Views/CardFlowView.swift:81`

```swift
VStack { ProgressView... }
.background(Theme.mainBg)  // loading 态
```
**目标**：loading 态保留实底没问题（加载中不透 wallpaper 视觉更稳），也可以改透明让 wallpaper 穿透。
**改动**：**保留**（loading 本来就是短暂态）。

### 4.10 `MemoryPalace/Views/CardFlowView.swift:619-639`

ChatInputBar 底部 VariableBlur + 渐变（透明 → mainBg）。
**目标**：保留 — 这是底栏的视觉收口，和本轮修复方向一致。
**改动**：0 行。

### 4.11 左页 Sidebar（`SidebarView.swift`）

Sidebar 被 codex 在 `01e5fea` 改过 628 行，需要单独看现状。但粟粟当前只反馈"聊天背景失效 + 底部白条"，没说左页右页。

**本轮建议**：Sidebar 不主动动。先改聊天页 + 删 iOSSafeAreaFill，build + 跑一遍，看左页右页是否有残留 leak 或失效。如果有再单独一轮。

---

## 5. 不做的事

1. **不动主题功能本身** — ThemeManager / AppTheme / ThemeBackgroundView / ThemeSettingsTab / ThemeEditorView 全部保留现状
2. **不引入新 token**（一度考虑加 `atmosphereSurface`，发现用 "mainBg 实底 + 不在主内容区刷它" 就够了）
3. **不改 sidebar** — 本轮先集中修聊天页 + root safe-area
4. **不升级 kelivo 主题的 palette** — 暖奶白配色不动
5. **不做渐变掩盖 bug** — codex 的原则正确，本轮继承

---

## 6. 验证方案

### 6.1 Build

```bash
xcodebuild -scheme MemoryPalace build
xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build
```
两个都过才继续。

### 6.2 手动验证（iOS simulator + 开一个带 wallpaper 的主题）

1. **聊天页**：气泡之间空隙能看到 wallpaper。顶部 nav 按钮下方有渐变过渡，不是硬切。底部输入栏之上有渐变过渡。输入栏实底，键盘弹起时不露怪东西。
2. **聊天页**：切主题到**不带 wallpaper** 的（暖奶白默认），聊天背景是纯 mainBg，不能穿帮变透明看到怪东西。
3. **列表页**：页码点在底部显示，不飘，卡片之间能看到 wallpaper（如果左页 Sidebar 没改，这条可能不成立 — 观察）。
4. **右页**：切到右页正常显示工具。
5. **页面指示器**：聊天页不显示（按方案 A），列表/右页底部显示，位置稳定，不飘到输入栏里。
6. **无 wallpaper 主题**：一切正常，不能因为拆了 mainBg 盖法就看起来通透 / 脏。

### 6.3 截图回归

修完至少截 4 张：
- 聊天页 + wallpaper
- 聊天页 + 无 wallpaper（默认暖奶白）
- 列表页 + wallpaper
- 输入栏聚焦键盘弹起 + wallpaper

存到 `docs/screenshots/`（新建）或直接丢 `/tmp/` 贴给粟粟看。

---

## 7. 成功标准

- [ ] 背景图主题下，聊天气泡之间空隙能看到 wallpaper
- [ ] iOS 聊天页底部不再有"莫名其妙一条白条"
- [ ] 页码点不再飘到输入栏里
- [ ] 无 wallpaper 主题不被改坏（视觉同修复前）
- [ ] macOS build 通过
- [ ] iOS build 通过
- [ ] 不引入新的 leak（顶部 status bar 区 / 底部 home indicator 区不出现视觉噪音）

---

## 8. Checklist

- [ ] 粟粟批注此 plan（尤其第 3.4 的 A/B/C 选项）
- [ ] 4.4 删 `iOSSafeAreaFill` 调用 + 函数定义 + `currentIOSPageSurface`
- [ ] 4.2 删 `iOSChatPage.background(Theme.mainBg)`
- [ ] 4.3 删 `iOSDashboardPage.background(Theme.sidebarBg)`
- [ ] 4.5 删 `ScrollView.background(Theme.mainBg)` @ CardFlowView.swift:142
- [ ] 4.7 删 `VStack.background(Theme.mainBg)` @ CardFlowView.swift:226
- [ ] 页码点处理：聊天页(iOSPage == 1)隐藏
- [ ] `xcodebuild -scheme MemoryPalace build` 通过
- [ ] `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build` 通过
- [ ] iOS simulator 跑一遍验证清单（6.2 节）
- [ ] 截图 4 张
- [ ] git commit + push

---

## 9. 风险

1. **Sidebar / 右页仍有漏点** — 本轮不碰 Sidebar。如果删完聊天页的 mainBg 盖法后发现右页或左页视觉回归更严重，立即 stop 回来补 plan，不打补丁。
2. **顶部 status bar 条漏图** — 删 `iOSSafeAreaFill` 后顶部 safe area 会暴露 root wallpaper。**这是预期的（沉浸感）**。如果粟粟看了觉得不行，单独再加一个顶部 mainBg 保底（不要和 iOSSafeAreaFill 同一个做法）。
3. **底部 home indicator 区漏图** — 同上。ChatInputBar 底部渐变本来就已经渐到 mainBg 实底，再加 `.safeAreaInset(edge: .bottom)` 的方式，home indicator 区会被 inputbar 的实底背景盖住。列表页/右页没有这种底栏 — 如果粟粟觉得底部漏图太明显，再议。
