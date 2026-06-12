# 界面逻辑优化调研（research-fable / 03-ui-flow）

> 日期：2026-06-11
> 范围：iOS 端导航结构、概念层级、设置入口
> 证据来源：MemoryPalaceApp.swift / ContentView.swift / SidebarView.swift / SettingsView.swift / MemoryPanelView.swift / ToolBarView.swift / GeneralSettingsTab.swift / AddToChatSheet.swift / WorldBookPanelView.swift / CardLibraryPanelView.swift
> 既有设计决策参照：task-sidebar-redesign.md（Claude App 风格侧边栏，已落地）、plan-right-panel-management.md（右栏工具管理，已落地）、DESIGN-MASTER-PLAN.md、design-dna.json

---

## 1. 现状分析

App 根容器是 `ContentView.iOSLayout`：侧边栏走 ZStack overlay（Claude App 风格，屏宽 80%），主区是 UIKit 三页横滑（`PagingContainerView`：0=聊天、1=右栏工具、2=记忆馆）。功能挂载点分裂为四套体系：侧边栏导航（Chats/Projects/群聊/Almond/Amber）、右栏 8 个工具、设置 sheet 18 个 tab、聊天输入区 AddToChatSheet。楼层（Profile）是数据隔离的顶层概念，切换入口却埋在设置→通用第三层；世界书的管理与绑定分散在右栏和设置两处。核心问题是层级与概念不对齐，而非单页交互。

### 1.1 页面结构树（文字版）

```
MemoryPalaceApp (.id(currentProfile.id) — 切楼层整树重建)
└─ ContentView.iOSLayout (ZStack)
   ├─ [overlay] SidebarView（侧边栏，屏宽 80%，左滑/按钮唤出）
   │   ├─ 标题行「Lost in Blossom」+ ⚙️ 按钮 → SettingsView (sheet)
   │   ├─ 搜索栏（可展开）+ AdvancedSearchPanel
   │   ├─ 导航入口（5 项，互斥切换列表内容区）
   │   │   ├─ Chats        → 对话列表（默认前 8 条 + "All Chats ›"）
   │   │   ├─ Projects     → ProjectsView（项目列表/详情）
   │   │   ├─ 群聊         → ChatroomListView → ChatroomView
   │   │   ├─ 🌰 Almond    → Claude 导入对话过滤
   │   │   └─ 🪨 Amber     → ChatGPT 导入对话过滤
   │   ├─ 标签列表（ConversationTag，swipe 删除）
   │   ├─ 统计 footer
   │   └─ 浮动「+ New chat」按钮（右下角）
   ├─ [page 0] 聊天页
   │   ├─ iOSChatTopBar：侧边栏按钮 | PinnedMessageBar | 🌿分支(BranchMapSheet) | ⋯菜单(改标签/收藏/重命名/删除) | → page1
   │   ├─ CardFlowView（对话流）/ EmptyStateView（问候语 + 开始新对话）
   │   └─ 输入区 + 号 → AddToChatSheet：照片/文件/选择模型/设置/导入聊天记录/贴纸
   ├─ [page 1] RightPanelView（MemoryPanelView.swift）
   │   └─ ToolBarView + 工具面板（RightPanelPlugin.builtInTools 注册 8 个）：
   │       日历 | 记忆 | 世界书(WorldBookPanelView) | 卡库(CardLibraryPanelView)
   │       | 贴纸 | Prompt(默认禁用, =PersonaSettingsTab) | CC终端 | 文件库
   ├─ [page 2] ArchivePageView（记忆馆：星座图/热力图统计）
   └─ [sheet] SettingsView：NavigationStack + 18 个 tab，5 个 Section
       ├─ 通用(含 楼层 ProfileSwitcher + 气泡标签 + 世界书绑定) / 数据与备份 / API / MCP / Prompt / 正则
       ├─ 右栏 / 记忆 / 健康 / 贴纸 / 通知
       ├─ 外观 / 主题
       ├─ Claude Code / 终端 / 文件库
       └─ 开发调试 / 震动测试
```

### 1.2 角色卡 / 世界书 / 楼层在 UI 上的关系

数据上（MemoryPalaceApp.swift `Profile`）：楼层 = Profile，持有 `characterCardID`、`linkedWorldBookIDs`、`regexScripts`，角色卡导入时生成楼层 + 对话 + 世界书（`ProfileEditorSheet.importCardContent`）。即 **楼层是聚合根**。

UI 上这个聚合关系被拆散在四处，互相不可见：

| 概念 | 管理入口 | 文件 |
|---|---|---|
| 楼层切换/新建/删除 | 设置 → 通用 → 「楼层」Section 的 Menu | GeneralSettingsTab.swift:18-22 → ProfileSwitcher |
| 角色卡库（增删查） | page1 右栏 → 「卡库」工具 | CardLibraryPanelView.swift |
| 角色卡 → 楼层（实际使用） | 新建楼层 sheet 内「导入自定义助手模板」 | MemoryPalaceApp.swift ProfileEditorSheet |
| 世界书 新建/导入/编辑 | page1 右栏 → 「世界书」工具（三种 scope：全局/楼层/对话） | WorldBookPanelView.swift:66-68 |
| 世界书 查看绑定/删除 | 设置 → 通用 → 「世界书」Section（只能删，不能编辑） | GeneralSettingsTab.swift:59-61 |

GeneralSettingsTab.swift:149 自己承认了这个分裂：`Text("在右栏「世界书」tab 里可以新建、导入、编辑世界书")` —— 用一行灰字提示用户去另一个体系里完成另一半操作。

---

## 2. 痛点（带证据）

### 2.1 操作路径过长

| 操作 | 路径 | 点击数 | 证据 |
|---|---|---|---|
| 切换楼层（多角色核心操作） | 聊天页 → 开侧边栏 → ⚙️ → 通用 → 楼层 Menu → 选楼层 | **5** | GeneralSettingsTab.swift:20，ProfileSwitcher 是设置二级页里的 Menu |
| 新建楼层（= 开始用一个新角色） | 同上路径到 Menu → 新建楼层 → 填表 | **5+表单** | MemoryPalaceApp.swift:498-502 |
| 编辑当前楼层系统提示词 | 同上 → 编辑当前楼层 → 滚到「系统提示词」 | **6** | ProfileEditorSheet Section("系统提示词") |
| 给当前楼层绑一本已有世界书 | 不可达——设置页只能删绑定，右栏世界书面板按 scope 新建 | **断头路** | GeneralSettingsTab.swift:117-126 只有 xmark 删除按钮 |
| 切换模型 | 聊天页 → + → 选择模型 → 选 | 3 | AddToChatSheet.swift:107-123，这是做得好的样板 |
| 新建对话 | 开侧边栏 → New chat | 2 | SidebarView.swift:772，没问题 |

对比：新建对话 2 次、换模型 3 次，而「换角色」这个同级常用操作要 5 次，且藏在「设置→通用」这种通常放低频项的位置。

### 2.2 概念对新用户不友好

实测代码中同时存在 **9 个组织性概念**：楼层、角色卡（UI 文案已改叫「自定义助手模板」，CardLibraryPanelView.swift:43，但右栏「卡库」名称未跟上）、世界书（再分全局/楼层/对话三 scope）、预设 Preset、Prompt 槽位、Projects、标签 Tag、群聊 Chatroom、Almond/Amber。问题点：

- **Almond / Amber**（SidebarView.swift:5 注释：Claude 导入 / ChatGPT 导入）用 🌰🪨 emoji + 私有代号做一级导航，与 Chats/Projects/群聊并列。对新用户是零信息量——若 App 要上 TestFlight 给外人（docs/plan-v1-testflight.md 存在），这是第一个卡点。而 task-sidebar-redesign.md §4 原计划是「导入的 ChatGPT 记录 → 自动创建 ChatGPT 历史 Project」，即导入源本应是 Project 而非一级导航——现状偏离了既有设计方向。
- **楼层 vs 角色卡 vs 预设**：三者都影响「AI 是谁」。楼层装人格字段，角色卡是楼层的模板，预设管 prompt 拼装顺序与采样参数（PersonaSettingsTab）。UI 没有任何一处把这条链画出来；「Prompt」同时出现在设置 tab（SettingsView.swift:58）和右栏禁用工具（RightPanelPlugin.swift:110），是同一个 `PersonaSettingsTab` 的两个入口。
- **右栏（page1）本身**：横滑才能发现，工具含义靠 icon 猜；「记忆」工具（右栏）与「记忆」设置（SettingsView .memory）、「记忆馆」（page2 Archive）三个"记忆"并存。
- **页面指示点**只有三个小圆点（ContentView.swift:431-439），不标注每页是什么。

### 2.3 设置项分散

**设置入口有 3 个**：① 侧边栏 ⚙️（SidebarView.swift:117）② AddToChatSheet「设置」行（AddToChatSheet.swift:128-142，经 `.requestShowSettings` 通知）③ 搜索结果/右栏经 `RightPanelNavigator` 间接跳转。入口多本身无害，问题在 sheet 内部：

- **18 个 tab 平铺**（SettingsView.swift SettingsTab enum，18 个 case），其中「开发调试」「震动测试」是开发工具，「终端」「Claude Code」「文件库」是 CC 桥接专属，与「外观」「通知」混在同一层。
- **同名异处**：文件库既是设置 tab（FileLibrarySettingsTab）又是右栏工具（FileLibraryPanelView）；贴纸、记忆、Prompt 同理各有两处。
- **楼层相关设置被劈开**：楼层身份在「通用」，楼层 prompt 在「Prompt」，楼层正则在「正则」，楼层世界书绑定在「通用」末尾——全是 Profile 的字段（MemoryPalaceApp.swift:17-30），却要跑四个 tab。

---

## 3. 方案对比

| 维度 | A. 小修小补 | B. 导航重构（TabView/统一容器化） | C. 渐进式信息架构调整 |
|---|---|---|---|
| 做法 | 楼层切换器加进侧边栏；设置 tab 重新分组收纳；Almond/Amber 加说明文案 | 推翻三页横滑 + overlay 侧边栏，改原生 TabBar 或单一 NavigationStack | A 的全部 + 分阶段建「楼层详情页」聚合角色/世界书/prompt，导入源降级为 Project，最后补 onboarding |
| 解决路径过长 | ✅ 切楼层 5→2 次 | ✅ | ✅ 切楼层 5→2 次 |
| 解决概念分裂 | ❌ 四套体系仍各自为政 | ⚠️ 重构容器不自动解决概念问题 | ✅ 楼层成为 UI 上的聚合根，与数据模型对齐 |
| 风险 | 低 | **极高**：PagingContainerView 是踩了十几个坑换来的（docs/plan-uikit-paging-container、postmortem-kelivo-keyboard-wallpaper、plan-tabview-to-scrollview——历史上 TabView 方案就是被迁移走的）；键盘/壁纸/safe area/手势全要重趟 | 中：不动 Paging 容器与侧边栏交互（两者是 task-sidebar-redesign 刚落地的成果） |
| 工作量 | 1-2 个 PR | 数周 + 回归风暴 | 5-7 个 PR，可随时停在任意阶段 |
| 与既有设计决策冲突 | 无 | **冲突**：DESIGN-MASTER-PLAN 明确「聊天UI、侧边栏——全部不动」；tabview→scrollview 迁移文档证明 TabView 路线已被否决 | 无；Projects 归类正是 task-sidebar-redesign §4 的原计划 |

## 4. 推荐方案：C（渐进式信息架构调整）

理由：
1. **病根是信息架构不是容器**。三页横滑 + overlay 侧边栏的交互本身是刚按 Claude App 风格重做的（task-sidebar-redesign，2026-04 系列 postmortem 收尾），手感已打磨过；痛点证据全部指向「东西放错层级」而非「滑动方式不对」。
2. **B 的风险收益比极差**。docs 里至少 6 篇 paging/键盘/壁纸 postmortem 证明这个容器动一次要还几周的债；且与 DESIGN-MASTER-PLAN「UI 不动」的决策直接冲突。
3. **C 每一步独立可发布**，符合仓库现有「research → plan → 单任务 PR」的工作流，且把 task-sidebar-redesign §4 没做完的 Projects 归类顺手收尾。

## 5. 实施步骤（单次 PR 粒度）

| # | PR | 内容 | 涉及文件 | 验收 |
|---|---|---|---|---|
| 1 | sidebar-floor-switcher | 侧边栏标题行（「Lost in Blossom」位置）替换为当前楼层 emoji+名，点击弹 ProfileSwitcher 同款 Menu（复用现组件，加 style 参数） | SidebarView.swift:110-131、MemoryPalaceApp.swift ProfileSwitcher | 切楼层 2 次点击；设置→通用入口保留 |
| 2 | settings-regroup | SettingsView 分组改为：楼层与对话（通用/Prompt/正则/记忆）、外观（外观/主题/贴纸）、数据（数据与备份/API/MCP/通知/健康）、高级（右栏/Claude Code/终端/文件库）、开发者（开发调试/震动测试，DEBUG only 或折叠） | SettingsView.swift:50-81 | 不改任何子页，只动 Section 归属；开发项 release 不可见 |
| 3 | floor-detail-page | 新建 FloorDetailView：聚合当前楼层的 身份字段 + 系统提示词 + 绑定世界书（可绑可解，补上 2.1 的断头路）+ 来源角色卡 + 正则。入口：PR1 的 Menu 加「楼层详情」、设置「通用」的楼层 Section 改为 NavigationLink | 新文件 Views/FloorDetailView.swift；GeneralSettingsTab.swift；WorldBookPanelView 抽出 scope 选择子视图复用 | 楼层全部字段一页可达；世界书绑定双向可操作 |
| 4 | import-source-to-projects | 按 task-sidebar-redesign §4 原案：Almond/Amber 从一级导航降为自动 Project（「Claude 历史」「ChatGPT 历史」），侧边栏一级导航收敛为 Chats / Projects / 群聊。保留 memoryFilter 逻辑作为 Project 查询 | SidebarView.swift:5-10、192-249、ProjectsView.swift、导入管线打 Project 标 | 老用户数据自动归类，无数据迁移（只是查询视图变化） |
| 5 | page-labels | 三个分页指示点加文字标签（聊天/工具/记忆馆），首次滑到 page1 时给工具栏 icon 显示一次性文字气泡 | ContentView.swift:431-439、ToolBarView.swift | 不改手势，只加标注 |
| 6 | onboarding-first-run | 首启流程：欢迎页 → 选择「直接开聊（默认楼层）/ 导入角色卡建楼层 / 导入聊天记录」三选一，复用 ProfileEditorSheet 与 ImportView；用 UserDefaults flag 控制只出现一次 | 新文件 Views/OnboardingView.swift；ContentView.autoCreateFirstConversationIfNeeded 改为 onboarding 完成后触发 | 跳过即等同现状（autoCreate 兜底不删） |
| 7 |（可选）concept-rename-sweep | 统一文案：「卡库」→「助手模板」（对齐 CardLibraryPanelView 已用文案）、三个「记忆」入口加副标题区分 | RightPanelPlugin.swift:104-112、SettingsView.swift | 纯文案，零逻辑 |

依赖关系：1→3（详情页入口挂在切换器上）；2、4、5、6、7 相互独立，可并行。

## 6. 风险点

1. **ContentView.id(currentProfile.id) 整树重建**（MemoryPalaceApp.swift:450）：PR1 把切楼层入口提到侧边栏后切换频率会上升，profile-switch 的历史 race（docs/plan-profile-switch-atomic、todo-profile-switch-race、`.profileWillSwitch` 六处 observer）被触发的概率随之上升。PR1 必须在切换前关侧边栏动画完成后再 switchTo，并回归测试快速连续切换。
2. **SidebarView 2825 行单文件**：PR1/PR4 都动它，先后顺序要排开，避免双 PR 冲突；动 nav entry 区时注意 `debouncedNavAction` 与 `showAllChats` 重置链（SidebarView.swift:829）。
3. **设置重排打破肌肉记忆**：当前唯一重度用户对 18 tab 的位置已有习惯，PR2 上线前给她看分组草图确认，避免「优化」变成扰动。
4. **PR4 涉及导入管线**：ImportView/ImportRecord 给历史对话补 Project 归属时只能做查询层映射，不要写迁移脚本动 unified.store（迁移已有 fail-safe 包袱，见 UnifiedContainerMigration 注释「粟粟可查 .backup 手动恢复」）。
5. **右栏 Prompt 工具默认禁用**（RightPanelPlugin.swift:110）说明设置/右栏的双入口已有收敛意图，PR7 改名时勿把禁用态改回启用，避免再造一个重复入口。
6. **设计 DNA 约束**：新页面（FloorDetailView/Onboarding）配色遵守 design-dna.json（暖奶白 #FFFBF6 体系、禁蓝禁黄、薄荷绿 #8EBD9F 做强调）。
