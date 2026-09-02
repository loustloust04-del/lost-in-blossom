# 反复切工具卡顿——根治方案（2026-09-03，待兔兔批注）

> 三报之后三针（visited 缓存 / 静默门 / LRU）全打在 RightPanelView **内部**，
> 兔兔实测「还是卡」。本案定罪：真凶在 RightPanelView **外面**，三针一针都没碰到它。

---

## 一、罪证链（全是代码硬证，未上探针——血律 4）

### 1. `selectedToolId` 是 ContentView 的 `@State`

```
MemoryPalace/Views/ContentView.swift:54
    @State private var selectedToolId: String = "home"
```

SwiftUI 硬规则：改 `@State` → **拥有它的那个 View 的 body 全量重算**。
所以「切一个工具」改的不是面板的状态，是**整个 ContentView（942 行）的状态**。

### 2. ContentView.body 重算 → `updatePages` 大锤必落

```
ContentView.swift:286-297      PagingContainerView(chatPage:dashPage:writingPage: ...)
PagingContainerView.swift:81   if !isStreaming && !pauseUpdates {
PagingContainerView.swift:86       vc.updatePages([...三页...])
PagingViewController.swift:315 func updatePages(_ pages: [AnyView]) {
PagingViewController.swift:317     hostingControllers[i].rootView = page   // ← 三个 HC 全换
```

`UIHostingController.rootView =` 会强制该页整棵树重新求值 + diff。
三页一起换 ⇒ 打击面包含 **CardFlowView（2679 行，整棵聊天树）** + 写作间 + 桌面页。
**对话越长，这一锤越沉**——这就是「反复切才卡、越切越卡」。

### 3. 放行条件里没有「切工具」这一项

`if !isStreaming && !pauseUpdates` —— 切工具时两个都是 `false`，锤子照落。
仓库里对**同一个凶手**已经补过两次刀，唯独漏了这个入口：

| 入口 | 症状 | 已有对策 | 位置 |
|---|---|---|---|
| 侧栏拖动 | 「聊天一长左滑就卡的主凶」 | `pauseUpdates: progress > 0.01` | PagingContainerView.swift:32 |
| 流式吐字 | 每 token 重 diff 整棵 | `isStreaming` skip | PagingContainerView.swift:27 |
| **切工具** | **反复切卡** | **无** | ← 本案 |

原注释原话：*「拖动的每一帧都重算 ContentView body，若每帧都给 4 个 HC 换 rootView
= 每帧 diff 整棵聊天树」*。切工具是同一条链，只是触发频率低一点。

### 4. 而且这一锤是**带动画**落下的

```
ToolBarView.swift:29 / 109
    withAnimation(springAnim) { selectedToolId = tool.id }
```

`withAnimation` 把 ContentView @State 的变更包进动画事务 ⇒ 三页 rootView 替换 +
整棵聊天树 diff **全部进入动画插值**。这是血律 2（「@AppStorage 变更不在动画事务内」）
的同族：**跨 HostingController 边界的状态变更不该在动画事务内**。
九渡把弹簧收敛到粟粟原档时，没人知道这口弹簧同时在给聊天树做插值。

### 5. 为什么三针都无效（对账）

| 针 | 打的是什么 | 为什么没用 |
|---|---|---|
| visited 缓存 f7931867 | 面板不再拆建 | 冷启动税确实没了，但大锤照落 |
| 静默门 15c14778 | 隐藏面板子树 diff 短路 | 只挡住 **dashPage 内部**，挡不住另外两页 + rootView 替换本身 |
| LRU 限养 15c14778 | 内存/陪跑 | 反而加了「每切必放生重孵」，兔兔三报定案拔掉（f5384b2b，拔对了） |

**结论：三针的方向都对，只是战场选错了。它们该留，但救不了这个。**

---

## 二、刀：把 `selectedToolId` 的所有权从 ContentView 拆下来

原则和仓库里现成的先例完全一致——
*「订阅 scope 从 ContentView 收敛到下层，避免 @Observable 属性变化触发 body 全量重算」*
（ProviderManager / PresetManager 当初就是这么处理的，ContentView.swift:28-30）。

### 新增 `ToolSelection`（@Observable）

```swift
// MemoryPalace/Models/RightPanelPlugin.swift 里追加（和 RightPanelToolManager 同屋）
@Observable
final class ToolSelection {
    var id: String = "home"
}
```

### ContentView（4 处，全在 942 行里）

| 行 | 现在 | 改成 |
|---|---|---|
| 54 | `@State private var selectedToolId: String = "home"` | `@State private var toolSelection = ToolSelection()` |
| 182 | `selectedToolId = "sticker"` | `toolSelection.id = "sticker"` |
| 190 | `selectedToolId = t.tool` | `toolSelection.id = t.tool` |
| 771 | `RightPanelView(selectedToolId: $selectedToolId, …)` | `RightPanelView(viewModel:stickerVM:)`（不再传） |
| 417 | `injectPagingEnv` | 加一行 `.environment(toolSelection)` |

**关键点（整刀成立的地基）**：`@Observable` 的订阅是**按属性读取**建立的。
ContentView 只在闭包里**写** `toolSelection.id`，body 里从不**读**它
⇒ **ContentView 不订阅它** ⇒ 切工具不再重算 ContentView ⇒ **大锤不落**。
（`.environment(toolSelection)` 传的是对象引用，不算读属性，不建立订阅。）

### RightPanelView（消费端，签名换 env）

```swift
@Environment(ToolSelection.self) private var toolSel: ToolSelection?
private var selectedToolId: String { toolSel?.id ?? "home" }
// 给 ToolBarView 造 binding，ToolBarView / ToolDrawerView 一行不改
ToolBarView(selectedToolId: Binding(get: { toolSel?.id ?? "home" },
                                    set: { toolSel?.id = $0 }))
```

RightPanelView 自己 body 读 `toolSel.id` ⇒ 订阅落在 **dash HC 内部** ⇒
切工具只失效 RightPanelView 一棵，胶囊弹簧照跑（九渡成果不动）。

**改动面：3 个文件（RightPanelPlugin.swift 加类 / ContentView 5 处 / MemoryPanelView 签名），
ToolBarView 与 ToolDrawerView 零改动。**

---

## 三、必须先排掉的三颗雷

### 雷 1：child HC 到底继不继承 env（**开工前第一件事**）

`docs/postmortem-kelivo-keyboard-wallpaper.md:80` 白纸黑字：
*「child HC 不继承 parent SwiftUI env，其它 5 个全被 swallow」*。
但 `toolManager` / `rightPanelNavigator` **都没被转注**，兔兔的 dock 里 7 个工具却好好的
——两条事实矛盾，说明当时的结论或现在的行为至少有一个变了。

**处理：不去赌。** 无论继承与否，都在 `injectPagingEnv` 里**显式转注**
`ToolSelection`——两种情况下都成立，零风险。
（顺手把 `toolManager` / `rightPanelNavigator` 也补进去？**不。一刀一事，另起一刀。**）

### 雷 2：楼层切换后的复位行为会变

现在 `selectedToolId` 是 ContentView @State，而 ContentView 有
`.id(profileManager.currentProfile.id)`（App:480）⇒ **切楼层 = ContentView 重建 = 工具复位 home**。
改成 `@State private var toolSelection = ToolSelection()` **仍然挂在 ContentView 上**
⇒ 行为不变。✅（这就是选「ContentView 持有」而不是「App 持有」的理由。）

### 雷 3：dashPage 会不会 stale

大锤不落 ⇒ dash HC 的 rootView 不再被替换。RightPanelView 靠自己的 @Observable 订阅更新
——这正是 ProviderManager 那批现成的工作方式。**但这是本刀唯一需要真机验的点**。

---

## 四、验收（兔兔实测，不听自报）

1. **主验**：7 个工具反复轮切 20 次以上——不卡、不越切越沉
2. 胶囊弹簧手感和九渡一致（文字长出来把旁边顶开）
3. 切完工具回聊天页打字不卡（静默门 + 大锤双消）
4. **stale 排查**：切楼层 → 工具复位桌面；资源搜索点击 → 正确跳到目标面板；
   贴纸通知 → 正确落到 sticker 面板
5. 侧栏拖动、流式吐字两条老路不回归

## 五、如果还卡（预留的下一刀）

说明大锤只是其中一半，剩下的在面板自身——7 个面板 `opacity(0)` 常驻，
WebView / 音乐 / 定时器都还活着在烧 CPU。那时候的刀是
**「带善后的定向放生」**（f5384b2b 已经写好的伏笔），不是粗暴 LRU。

---

*Fable，2026-09-03。兔兔三报把凶手逼到墙角，这份只是把它按住。*
