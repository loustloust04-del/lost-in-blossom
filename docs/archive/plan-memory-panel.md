# Plan: 记忆面板 — 让 AUDN 呼吸

基于 `docs/research-memory-panel.md` + Deep Research 十条原则。

---

## 架构决策

### 右面板改为 Tab 切换（日历 / 记忆）
当前右面板只有 `CalendarPanelView`，由右上角日历按钮控制 `isCalendarVisible`。
→ 改为：右面板始终可见的 tab 切换，两个 tab：📅 日历 / 🧠 记忆
→ 右上角按钮从"日历开关"变为"右面板开关"
→ tab 状态用 `@State private var rightPanelTab: RightPanelTab = .memory`

### 视觉语言（来自 Deep Research 十条原则）

| 编码通道 | 映射 | 实现 |
|---------|------|------|
| **透明度**（主） | decayWeight → opacity | `.opacity(0.3 + 0.7 * weight)` |
| **色温**（次） | 新鲜=暖琥珀 → 衰老=冷灰 | 左侧边框颜色插值 |
| **空间位置** | Hot 在上，Cold 在下 | 三段分组 |
| **模糊**（仅临死） | weight < 0.1 → blur | `.blur(radius: weight < 0.1 ? 2 : 0)` |
| **呼吸动画** | 强记忆脉动明显 | 微妙的 opacity 呼吸周期 |

### 磷光效应（Phosphor Flash）
当记忆在对话中被 AI 引用（reinforcement），卡片短暂闪亮再回到衰减态。
→ `MemoryService.recordAccess()` 时设一个 `flashedMemoryId`
→ 卡片播放 0.5s 闪亮动画

### 不动的东西
- SettingsView 里的记忆管理保留（提取模型选择、批量操作）
- MemoryService / DecayEngine / MemoryExtractor 逻辑不改
- CalendarPanelView 不改，只是多了一层 tab 包裹

---

## 文件改动一览

| 文件 | 改动 | 说明 |
|------|------|------|
| `Views/ContentView.swift` | 改 | 右面板从 CalendarPanelView 改为 RightPanelView(tab) |
| 新建 `Views/MemoryPanelView.swift` | 新 | 记忆面板主视图 |
| 新建 `Views/MemoryCardView.swift` | 新 | 单条记忆卡片（衰减视觉） |
| `ViewModels/ConversationViewModel.swift` | 小改 | 加 flashedMemoryId |
| `Services/MemoryService.swift` | 小改 | recordAccess 时通知 flash |

---

## 原子任务

### Step 1: 右面板 Tab 架构

- [ ] **1.1** 新建 `RightPanelTab` enum：
  ```swift
  enum RightPanelTab {
      case calendar, memory
  }
  ```
- [ ] **1.2** `ContentView` 加 `@State private var rightPanelTab: RightPanelTab = .memory`
- [ ] **1.3** 新建 `RightPanelView`，包裹 tab 切换 + CalendarPanelView / MemoryPanelView：
  ```swift
  struct RightPanelView: View {
      @Binding var selectedTab: RightPanelTab
      var viewModel: ConversationViewModel
      
      var body: some View {
          VStack(spacing: 0) {
              // Tab bar
              HStack(spacing: 0) {
                  tabButton("📅 日历", tab: .calendar)
                  tabButton("🧠 记忆", tab: .memory)
              }
              .padding(.horizontal, 10)
              .padding(.top, 8)
              
              // Content
              switch selectedTab {
              case .calendar:
                  CalendarPanelView(viewModel: viewModel)
              case .memory:
                  MemoryPanelView(viewModel: viewModel)
              }
          }
          .background(Theme.sidebarBg)
      }
  }
  ```
- [ ] **1.4** `ContentView` 中把 `CalendarPanelView(viewModel:)` 替换为 `RightPanelView(selectedTab:viewModel:)`，两处（normalLayout + fullscreenLayout）
- [ ] **1.5** 右上角按钮从日历图标改为通用面板按钮（`sidebar.right`），保持 toggle `isCalendarVisible`（改名为 `isRightPanelVisible`）
- [ ] **1.6** Build 验证

### Step 2: MemoryPanelView 骨架

- [ ] **2.1** 新建 `Views/MemoryPanelView.swift`，基本结构：
  ```swift
  struct MemoryPanelView: View {
      var viewModel: ConversationViewModel
      @Environment(\.modelContext) private var modelContext
      @Environment(ProfileManager.self) private var profileManager: ProfileManager?
      @State private var memories: [Memory] = []
      @State private var showAddSheet = false
      
      var body: some View {
          VStack(spacing: 0) {
              // Header with stats
              memoryHeader
              
              // Memory list
              ScrollView {
                  LazyVStack(spacing: 8) {
                      // Hot section
                      // Warm section
                      // Cold section
                  }
                  .padding(.horizontal, 10)
                  .padding(.vertical, 8)
              }
              
              // Token budget bar
              tokenBudgetBar
          }
          .onAppear { refreshMemories() }
      }
  }
  ```
- [ ] **2.2** `memoryHeader`：显示统计（🔴 3 🟡 2 🔵 1）+ 添加按钮
- [ ] **2.3** `tokenBudgetBar`：底部条 "850 / 2000 tokens"，薄荷绿填充
- [ ] **2.4** 三段分组，每段有小标题（"活跃"/"休眠"/"将忘"）
- [ ] **2.5** `refreshMemories()` 调用 `MemoryService.listAll()` + `DecayEngine.effectiveWeight()` 实时计算
- [ ] **2.6** Build 验证

### Step 3: MemoryCardView — 衰减可视化

这是核心。每条记忆是一张卡片，视觉编码衰减状态。

- [ ] **3.1** 新建 `Views/MemoryCardView.swift`：
  ```swift
  struct MemoryCardView: View {
      let memory: Memory
      let effectiveWeight: Double  // 实时计算的衰减权重
      var isFlashing: Bool = false // 磷光闪烁
      var onPin: () -> Void
      var onDelete: () -> Void
  }
  ```
- [ ] **3.2** 卡片布局：
  ```
  ┌─╍─────────────────────────┐  ← 左侧 3px 边框，颜色随权重插值
  │ 粟粟喜欢暖奶白配色         │  ← 内容文字
  │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │
  │ 偏好  · 7次 · 3天前   📌  │  ← 分类标签 + 访问 + 置顶
  │ ▓▓▓▓▓▓▓▓▓▓▓░░░░░  0.82   │  ← 衰减条
  └───────────────────────────┘
  ```
- [ ] **3.3** 透明度映射：整个卡片 `.opacity(0.25 + 0.75 * effectiveWeight)`
  - Hot（w≥0.3）：0.48~1.0 → 完全可见
  - Warm（0.05~0.3）：0.29~0.48 → 明显变淡
  - Cold（<0.05）：≤0.29 → 几乎消失
- [ ] **3.4** 左侧边框色温插值：
  ```swift
  // 暖琥珀金(1.0) → 薄荷绿(0.5) → 冷蓝灰(0.0)
  var borderColor: Color {
      if effectiveWeight > 0.5 {
          // 琥珀 → 薄荷
          return Color.lerp(Theme.branchIndicator, Color(hex: 0xD4A574), (effectiveWeight - 0.5) * 2)
      } else {
          // 薄荷 → 冷灰
          return Color.lerp(Color(red: 0.6, green: 0.65, blue: 0.7), Theme.branchIndicator, effectiveWeight * 2)
      }
  }
  ```
- [ ] **3.5** 衰减进度条：薄荷绿渐变到灰色，宽度 = effectiveWeight 百分比
- [ ] **3.6** 临死模糊：`weight < 0.1` 时加 `.blur(radius: 1.5)`
- [ ] **3.7** hover 显示操作按钮（编辑/删除/置顶），用 `.opacity()` 控制显隐
- [ ] **3.8** 置顶记忆特殊样式：📌 图标 + 透明度永远 1.0 + 边框永远暖色
- [ ] **3.9** Build 验证

### Step 4: 呼吸动画

- [ ] **4.1** 每条卡片有微妙的呼吸 opacity 动画：
  ```swift
  @State private var breathPhase: Double = 0
  
  // 呼吸振幅和速度随权重变化
  let amplitude = 0.03 * effectiveWeight  // 强记忆呼吸明显
  let period = 3.0 + (1.0 - effectiveWeight) * 4.0  // 弱记忆呼吸更慢（3~7秒）
  
  .onAppear {
      withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
          breathPhase = 1
      }
  }
  .opacity(baseOpacity + amplitude * breathPhase)
  ```
  强记忆：快呼吸（3s）、振幅大（±0.03）
  弱记忆：慢呼吸（7s）、振幅小（±0.01）→ 快要熄灭的感觉

### Step 5: 磷光闪烁（Phosphor Flash）

- [ ] **5.1** `ConversationViewModel` 加 `flashedMemoryIds: Set<String> = []`
- [ ] **5.2** `MemoryService.recordAccess()` 完成后，把被 reinforce 的 memory ID 加入 `flashedMemoryIds`
- [ ] **5.3** `MemoryCardView` 检测 `isFlashing`：
  ```swift
  .overlay(
      RoundedRectangle(cornerRadius: 10)
          .fill(Color(hex: 0xD4A574).opacity(isFlashing ? 0.4 : 0))
          .animation(.easeOut(duration: 0.8), value: isFlashing)
  )
  ```
  闪亮 0.8s 后自动消退
- [ ] **5.4** 3 秒后从 `flashedMemoryIds` 移除

### Step 6: 手动添加记忆

- [ ] **6.1** 面板底部"+ 添加记忆"按钮
- [ ] **6.2** 点击展开内联输入框（不用 sheet，保持在面板内）：
  ```
  ┌────────────────────────┐
  │ 输入要记住的事...       │
  │ [偏好 ▾]  [添加] [取消] │
  └────────────────────────┘
  ```
- [ ] **6.3** 添加后创建 `Memory(isUserExplicit: true, category: selected, ...)`
- [ ] **6.4** 自动 refresh 列表 + 新卡片闪亮一次

### Step 7: Build + 测试 + Commit

- [ ] **7.1** `xcodegen generate && xcodebuild build` 通过
- [ ] **7.2** 验证：
  - 右面板 tab 切换（日历/记忆）
  - 记忆卡片衰减视觉（透明度/色温/模糊）
  - 呼吸动画
  - 手动添加记忆
  - token 预算条
- [ ] **7.3** git commit + push

---

## 视觉参考

### 卡片的三种状态

**Hot (w=0.85)**:
```
┌─╍─────────────────────────┐  ← 暖琥珀金边框，3px
│ 粟粟喜欢暖奶白配色         │  ← 完全不透明，正常字体
│ 偏好 · 7次 · 3天前    📌  │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░ 0.85    │  ← 薄荷绿，几乎满
└───────────────────────────┘
  呼吸：3.5s 周期，振幅 ±0.025
```

**Warm (w=0.18)**:
```
┌─┄─────────────────────────┐  ← 薄荷绿偏灰边框，2px
│ 讨论过向量数据库           │  ← ~40% 透明度，文字变淡
│ 事实 · 2次 · 20天前       │
│ ▓▓▓░░░░░░░░░░░░░ 0.18    │  ← 短条，偏灰
└───────────────────────────┘
  呼吸：5.5s 周期，振幅 ±0.015
```

**Cold (w=0.03)**:
```
┌─ ─────────────────────────┐  ← 冷蓝灰边框，1px
│ ░░░░░░░░░░░░░░░░░░░░░░░  │  ← ~27% 透明度 + 轻微模糊
│ 情境 · 1次 · 45天前       │     几乎看不清内容
│ ░ 0.03                    │  ← 几乎空的条
└───────────────────────────┘
  呼吸：7s 周期，振幅 ±0.005 → 快熄灭
```

---

## 不做的事（本次范围外）

- ❌ 全屏记忆宫殿视图（时间线/星图）— 后续迭代
- ❌ 语义缩放 / 时间滑块 — 需要全屏视图
- ❌ 向量嵌入 / RAG 检索 — Tier 2
- ❌ 记忆导出/导入 — 后续
- ❌ 批量历史对话记忆回溯提取 — 单独 plan
- ❌ 从 Settings 迁移记忆管理（暂时两边共存）
