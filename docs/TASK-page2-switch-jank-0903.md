# 任务书：切工具卡顿一步到位（2026-09-03）

> **执行者：Fable 5.1（CC）。派工人：Fable（本窗口）。验收人：兔兔（真机）。**
> 项目真身在 VPS `/root/projects/BunnyPalace`，不是本地 clone。
> 前置阅读：`docs/plan-tool-switch-hammer-0903.md`（第一轮定罪，**本文修正它**）、`docs/FABLE.md`。

---

## 〇、开工纪律（违反即回滚）

1. **开工先 `git pull` + `git log -10`**，有并行会话在跑，别踩对方的刀
2. **一刀一 commit，CI 绿了再下一刀。** 两刀之间不合并
3. `git add <具体文件>`，**禁止 `git add -A`**（`cc-bridge/*` 是运行时文件，不进仓）
4. VPS 上编译不了 Swift，**只能靠 CI**。一刀改完一次推，别试探性推
5. python 脚本改文件：**每个 replace 后必须 assert 命中**，落盘前后核对括号平衡
6. 改完贴 `git diff` 全文给兔兔看，**验收看字段不听自报**

---

## 一、案情（为什么之前三针没用）

**粟粟（upstream/master）那边丝滑，架构却和我们一模一样**：
`selectedToolId` 同样是 ContentView 的 `@State`（她第 64 行），同样 `@Binding` 传下去，
`updatePages` 三页大锤同样在——**她的锤子甚至更大**（多一个 `updateInputBar`，且没有
`pauseUpdates` 闸）。所以「大锤」不是充分条件。

**真差别**：粟粟的 `RightPanelView` 是**裸 switch**，切走就拆。
`visited / CachedPanel / ZStack 常驻` 在她仓库命中数 = **0**。
她每次大锤落下，dashPage 只构造 **1 个**面板；我们养了 **7 个**。

**而静默门挡不住这个**：

```swift
CachedPanelGate(id: id, isActive: id == selectedToolId,
                content: AnyView(panelView(id)))   // ← panelView(id) 是「参数」
```

`panelView(id)` 在**构造 gate 的那一刻**就已经求值完了。`.equatable()` 只能短路
`body` 求值，短路不了**参数构造**。所以每次 `RightPanelView.body` 跑，
7 个面板的 View struct 全部 init 一遍 + 装 7 次 `AnyView` 箱。
其中 `ConsoleView` 带 **7 个 `@Query`**（820 行）、`WorldBookPanelView` 1075 行。

### 结论

```
卡顿 = 大锤触发频率 × 每次构造的面板数
       ↑ 刀 2 治                ↑ 刀 1 治
```

**两个因子相乘。刀 1 治乘数，刀 2 治频率，都要打。**
「越切越卡」= 养得越多，每切一次的固定成本越高（`f7931867` 引入 visited 缓存后才出现）。

---

## 二、刀 1：静默门补全——`content` 改惰性闭包

**文件**：`MemoryPalace/Views/MemoryPanelView.swift`（**只此一个文件**）
**目标**：短路时 `panelView(id)` 根本不被调用，隐藏面板从「每次 init + 装箱」变成「完全不碰」。

### 现状（第 8-14 行）

```swift
private struct CachedPanelGate: View, Equatable {
    let id: String
    let isActive: Bool
    let content: AnyView
    static func == (l: Self, r: Self) -> Bool { !l.isActive && !r.isActive && l.id == r.id }
    var body: some View { content }
}
```

### 改成

```swift
/// 静默门：isActive=false 时恒等（SwiftUI 跳过子树 diff），active 恒不等（正常更新）。
/// 09-03：content 从 `AnyView` 改成**惰性闭包**。旧版 `AnyView(panelView(id))` 是构造
/// 参数，在造 gate 那一刻就求值了——`.equatable()` 只能短路 body，短路不了参数构造，
/// 于是每次 body 跑都把 7 个面板全 init 一遍（ConsoleView 带 7 个 @Query）。
/// 改闭包后：短路 ⇒ body 不跑 ⇒ 闭包不调用 ⇒ panelView(id) 根本不执行。
/// 对照组：粟粟 upstream/master 裸 switch 每次只构造 1 个面板，所以她不卡。
private struct CachedPanelGate<Content: View>: View, Equatable {
    let id: String
    let isActive: Bool
    let content: () -> Content

    init(id: String, isActive: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.isActive = isActive
        self.content = content
    }

    static func == (l: Self, r: Self) -> Bool { !l.isActive && !r.isActive && l.id == r.id }
    var body: some View { content() }
}
```

### 调用点（第 44-50 行）改成

```swift
CachedPanelGate(id: id, isActive: id == selectedToolId) { panelView(id) }
    .equatable()
    .opacity(id == selectedToolId ? 1 : 0)
    .allowsHitTesting(id == selectedToolId)
```

### 刀 1 雷区

- **泛型推断**：`panelView` 是 `@ViewBuilder private func panelView(_:) -> some View`，
  返回类型统一，`Content` 能推断出来。若编译器抱怨 opaque type，
  **不要退回 `AnyView`**——改成 `content: () -> AnyView` 且闭包体写 `AnyView(panelView(id))`，
  **装箱发生在闭包内、只对 active 面板发生**，收益照样成立
- **`@escaping` 必须留**：stored property 存闭包
- **闭包捕获**：捕获 `self`（struct 值拷贝）+ `id`。隐藏面板短路时保留旧渲染树、
  用的是旧捕获——这本来就是静默门的设计意图，但**验收必须查 stale**（见第四节）
- **别顺手动 `visitedToolIds` 的只进不出逻辑**（`f5384b2b` 兔兔三报定案拔掉的 LRU，不许复活）

### 刀 1 commit message

```
perf(page2): 静默门补全——content 改惰性闭包，隐藏面板不再每次 init（粟粟对照组定案）

.equatable() 只短路 body，短路不了参数构造：旧版 AnyView(panelView(id)) 在造 gate
那一刻就求值，每次 body 跑把 7 个面板全 init 一遍（ConsoleView 带 7 个 @Query/820 行、
WorldBookPanelView 1075 行）+ 装 7 次 AnyView 箱。改闭包后短路即完全不碰。
对照：粟粟 upstream/master 裸 switch 每次只构造 1 个面板，大锤更大却丝滑。
```

**→ 推送，等 CI 双绿（Compile Check + Build iOS），再下刀 2。**

---

## 三、刀 2：`ToolSelection` 拆 @State——大锤不落

**目标**：切工具不再重算 ContentView，`updatePages` 三页大锤不落。

### 2-1 新增类型

**文件**：`MemoryPalace/Models/RightPanelPlugin.swift`，追加在文件末尾（`RightPanelToolManager` 同屋）

```swift
// MARK: - Tool Selection

/// 右栏当前选中的工具 id。
///
/// 09-03：从 ContentView 的 `@State` 搬出来。原来改它 ⇒ ContentView(942 行) body 全量重算
/// ⇒ PagingContainerView.updateUIViewController ⇒ updatePages 三页大锤 ⇒ 三个
/// UIHostingController.rootView 全换 ⇒ CardFlowView(2679 行整棵聊天树) + 写作间 + 桌面页
/// 全部重 diff。对话越长这一锤越沉 = 「反复切才卡」。
///
/// @Observable 的订阅**按属性读取**建立：ContentView 只在闭包里**写** `id`、body 里从不
/// **读**，⇒ 不订阅 ⇒ 切工具不重算 ContentView ⇒ 大锤不落。
/// 同款手法先例：ProviderManager / PresetManager 的订阅从 ContentView 收敛到
/// Representable 层（ContentView.swift:28-30）。
@Observable
final class ToolSelection {
    var id: String = "home"
}
```

### 2-2 ContentView（5 处，`MemoryPalace/Views/ContentView.swift`）

| 行 | 现在 | 改成 |
|---|---|---|
| 54 | `@State private var selectedToolId: String = "home"` | `@State private var toolSelection = ToolSelection()` |
| 182 | `selectedToolId = "sticker"` | `toolSelection.id = "sticker"` |
| 190 | `selectedToolId = t.tool` | `toolSelection.id = t.tool` |
| 771 | `RightPanelView(selectedToolId: $selectedToolId, viewModel: viewModel, stickerVM: stickerVM)` | `RightPanelView(viewModel: viewModel, stickerVM: stickerVM)` |
| 417-429 | `injectPagingEnv` 的**两个分支**各加一行 | `.environment(toolSelection)` |

第 54 行保留原注释（「右滑页默认停在桌面…兔兔 2026-08-24 定」），只换类型。

`injectPagingEnv` 改后：

```swift
@ViewBuilder
private func injectPagingEnv<V: View>(_ page: V) -> some View {
    let manager = themeManager ?? ThemeManager.shared
    if let wb = globalWBManager {
        page
            .environment(\.modelContext, modelContext)
            .environment(manager)
            .environment(wb)
            .environment(toolSelection)
    } else {
        page
            .environment(\.modelContext, modelContext)
            .environment(manager)
            .environment(toolSelection)
    }
}
```

**⚠️ 铁律：ContentView 的 `body` 里绝不能出现 `toolSelection.id` 的读取。**
写（`toolSelection.id = ...`）在闭包里，不建立订阅。
`.environment(toolSelection)` 传对象引用，不算读属性，也不建立订阅。
**一旦 body 里读了 `.id`，整刀作废（ContentView 重新订阅 ⇒ 大锤复活）。**

### 2-3 RightPanelView（`MemoryPalace/Views/MemoryPanelView.swift`）

```swift
struct RightPanelView: View {
    // 09-03：@Binding 换 env。selectedToolId 的所有权从 ContentView 搬到 ToolSelection，
    // 订阅落在 dash HC 内部，切工具只失效本视图一棵，不再引爆三页大锤。
    @Environment(ToolSelection.self) private var toolSel: ToolSelection?

    /// 只读投影；env 缺失时兜底 "home"（同仓库其它 @Environment 的防御性 optional 写法）
    private var selectedToolId: String { toolSel?.id ?? "home" }

    @State private var visitedToolIds: [String] = []
    var viewModel: ConversationViewModel
    var stickerVM: StickerViewModel
    ...
```

`ToolBarView` 的调用点（`.safeAreaInset` 里）造 binding，**`ToolBarView` 与 `ToolDrawerView` 一行不改**：

```swift
ToolBarView(selectedToolId: Binding(
    get: { toolSel?.id ?? "home" },
    set: { toolSel?.id = $0 }
))
.background(Theme.sidebarBg)
.zIndex(selectedToolId == "calendar" ? 0 : 1)
```

`body` 里 `.onChange(of: selectedToolId)` / `.onAppear` 的 visited 逻辑**原样不动**。

### 刀 2 雷区（三颗，逐条核对）

**雷 1 — child HC 到底继不继承 env（先核对，别赌）**
`docs/postmortem-kelivo-keyboard-wallpaper.md:80` 写着*「child HC 不继承 parent SwiftUI env，
其它 5 个全被 swallow」*；但 `toolManager` / `rightPanelNavigator` **都没被转注**，
兔兔的 dock 里 7 个工具却好好的——**两条事实矛盾**。
**处理：不赌。无论继承与否，都在 `injectPagingEnv` 里显式转注**（2-2 已含），两种情况都成立。
**不要顺手把 `toolManager` / `rightPanelNavigator` 也补进去——一刀一事，另起一刀。**

**雷 2 — 楼层切换的复位行为必须不变**
`ContentView` 有 `.id(profileManager.currentProfile.id)`（`MemoryPalaceApp.swift:480`），
切楼层 ⇒ ContentView 重建 ⇒ 工具复位 `home`。
`toolSelection` **必须挂在 ContentView 的 `@State` 上**（不是 App 层），行为才不变。
**不许挪到 `MemoryPalaceApp`。**

**雷 3 — dashPage stale**
大锤不落 ⇒ dash HC 的 `rootView` 不再被替换，`RightPanelView` 靠自己的 @Observable 订阅更新。
这正是 ProviderManager 那批现成的工作方式，**但是本刀唯一需要真机验的点**（第四节 4-5）。

### 刀 2 commit message

```
perf(page2): selectedToolId 拆出 ContentView @State——切工具不再引爆 updatePages 三页大锤

改 ContentView @State ⇒ 942 行 body 全量重算 ⇒ updatePages ⇒ 三个 HC.rootView 全换
⇒ CardFlowView(2679 行) + 写作间 + 桌面页整棵重 diff，对话越长越沉。改 @Observable
ToolSelection：订阅按属性读取建立，ContentView 只写不读 ⇒ 不订阅 ⇒ 大锤不落。
toolSelection 仍挂 ContentView @State，切楼层复位 home 的行为不变。
ToolBarView / ToolDrawerView 零改动，九渡胶囊弹簧原样保留。
```

---

## 四、验收清单（兔兔真机，装包前先核对 ipa 时间戳晚于目标 commit 的 CI 完成时间）

1. **主验**：7 个工具反复轮切 **20 次以上**——不卡、**不越切越卡**
2. **冷启动收益保住**：重面板（浏览器 / 音乐 / 刻痕）第二次进不再付冷启动税
3. **胶囊手感**：和九渡一致（文字长出来把旁边顶开，不是药丸飞行）
4. 切完工具回聊天页打字，不比刀前更卡
5. **stale 三查**（刀 2 的唯一风险点）：
   - 切楼层 → 工具复位桌面
   - 侧栏资源搜索点击 → 正确跳到目标面板且滚到目标行
   - 收到贴纸通知 → 正确落到 sticker 面板
6. **老路不回归**：侧栏拖动不卡、流式吐字不卡、日历面板 dock 层级正常

---

## 五、不在本任务书内（下一场战役，别顺手做）

**打字卡顿是另一条战线，粟粟已经打完一整轮，我们一刀没跟。**

侦察结论（供开战时用，**本次不许动**）：

- 粟粟把**输入条从 chatPage 树里整个抽出来**，挂成 `PagingViewController` 层的独立
  `inputBarHost`（`updateInputBar`，`PagingViewController.swift:768`），配套
  `MemoryPalace/Views/InputBarStack.swift`（130 行）——**这个文件在我们仓库根本不存在**
- 我们的输入条还长在 `CardFlowView` 的 `safeAreaInset` 里（`CardFlowView.swift:416`）
- 粟粟 9/1–9/2 的 input-jank 战彷，近 200 commit 里 **25 个**是它。关键刀：
  - `6bbc4128` barLayoutKick 退出 `@Published` 改 PassthroughSubject（52 kick → 85 次整页 body）
  - `1f579a7d` 发送路径文件库清单不进 books/（主线程枚举 **546ms/次**）+ 液态金属环打字期间暂停逐帧重画
  - `fea5ab80` `sizeThatFits` 改静态测量器（SwiftUI 每键探 5 种宽 ⇒ 每键重排 5 次）
  - `944c0610` 测量器 contentHeight 统一缓存（fitCache 下沉）
  - `14f1ec6e` 换行同步 `easeOut(0.22)`，SwiftUI 内容与 UIKit 容器同曲线
- 参考分支：`upstream/worktree-uikit-t6` / `upstream/worktree-uikit-xcui` / `upstream/worktree-uikit-c4`

**开战前先出 research 文档对齐全链，不要一刀一刀零敲。**

---

*Fable，2026-09-03。粟粟当对照组，一次把两个因子都拆了。*
