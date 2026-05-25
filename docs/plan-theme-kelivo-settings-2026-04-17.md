# Plan: 设置页【主题】对齐 kelivo

> 时间：2026-04-17  
> 工作树：`/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings`  
> 依赖 research：`docs/research-theme-kelivo-settings-2026-04-17.md`

---

## 0. 已确认方向（来自 Susu 批注）

这轮 plan 以你的批注为准，不再摇摆：

1. **不抄 kelivo 的 palette 颜色本体**  
   抄的是系统结构和功能机制。颜色先走 **自定义颜色** 路线，后面再补成套主题。
2. **设置页新增独立 `主题` tab**  
   不并入 `外观`。
3. **必须做深色模式**  
   不能只停在浅色主题。
4. **优先拉满自定义自由度**  
   不先拿“守住当前设计语言”卡需求。

### 当前假设

- 你说的“我已经有色板了”，**目前不在这个 repo / worktree 里可直接读取**。  
  我这轮默认先把主题基础设施 + 自定义颜色编辑器做出来，色板后续可以无痛灌入。

---

## 1. 目标

把记忆宫殿当前“编译期单主题”升级成 kelivo 那种**真正接到根部的运行时主题系统**，并且首轮就满足：

- 设置页有独立 `主题` tab
- 支持 `系统 / 浅色 / 深色`
- 支持选择主题
- 支持一个可编辑的 **自定义主题**
- 支持分别编辑 **浅色 token** 和 **深色 token**
- 支持全局即时生效 + 持久化
- 不做假 UI，必须真的影响整个 app

---

## 2. 非目标

这轮不做：

- 主题导入 / 导出 JSON
- 多个用户自定义主题库管理（增删很多套）
- 远期的 design-dna 自动读取运行时化
- 把所有 feature-specific 的特殊色彩语言都无限细分

这轮先做“**可工作的主题底座 + 一个高自由度自定义主题**”。

---

## 3. 设计方案

## 3.1 整体结构：抄 kelivo 的三层，但换成 SwiftUI 版本

### 第一层：Theme Mode

独立控制亮暗策略：

- `system`
- `light`
- `dark`

作用：

- 控制 app 使用浅色 token 还是深色 token
- 同时驱动系统控件外观（`preferredColorScheme`）

### 第二层：Theme Selection

独立控制当前选中的主题 definition：

- `默认主题`
- `自定义主题`

首轮不做很多套成品主题，但**schema 和持久化会按“可扩多主题”设计**，避免以后推倒。

### 第三层：Theme Editor

进入 `自定义主题` 后，允许编辑两套 token：

- 浅色 token
- 深色 token

每套 token 至少覆盖：

- 背景：`mainBg`, `sidebarBg`
- 气泡：`userBubble`, `assistantBubble`
- 辅助面：`accent`
- 文字：`textPrimary`, `textSecondary`, `textMuted`
- 功能色：`branchIndicator`, `favorite`, `danger`

---

## 3.2 数据层

### 新增主题模型

计划新增一组 Codable 模型，例如：

- `AppThemeMode`
- `ThemeColorValue`
- `ThemeTokenSet`
- `AppThemeDefinition`

职责：

- `ThemeColorValue`
  - 负责颜色的可持久化表达
  - 存 hex / rgba
  - 提供 `SwiftUI.Color` 转换
- `ThemeTokenSet`
  - 一套 light 或 dark token
- `AppThemeDefinition`
  - `id / name / isBuiltIn / light / dark`

### 持久化

优先走本地持久化，和当前大量 `@AppStorage` 一致：

- `themeMode`
- `selectedThemeId`
- `usePureBackground`
- `themeDefinitions`（JSON blob）

首轮会 seed：

1. `default`  
   来自当前记忆宫殿默认浅色 token + 一套新的默认深色 token
2. `custom`
   初始复制默认主题，供用户直接改

---

## 3.3 管理层

### 新增 `ThemeManager`

计划新增一个全局主题管理对象，建议放在 `MemoryPalace/Utils` 或 `MemoryPalace/Services`：

- 读取持久化
- 暴露当前 mode / selectedTheme / currentTokenSet
- 修改 mode / selected theme / custom theme token
- 负责通知 SwiftUI 刷新

### 为什么不用一堆散落的 `@AppStorage`

因为这次不是 1-2 个开关，而是：

- mode
- selected theme
- pure background
- 自定义 light/dark token 整体更新

继续散落在 View 层会很快失控。

---

## 3.4 `Theme.swift` 改造策略

### 当前问题

`Theme.swift` 现在是固定 `static let`，无法运行时切换。

### 计划

保留 `Theme.xxx` 这个调用面，避免全项目 200+ 处 API 大改，但把实现改成：

- `static var mainBg: Color { ThemeManager.shared.current.mainBg }`
- 其他 token 同理

也就是：

- **调用面尽量不变**
- **底层从固定常量改为动态读取**

### 风险点

只把 `Theme` 改成 computed property 还不够，**View 必须真的重绘**。

### 解决策略

不把 `ThemeManager` 塞到每个 leaf view，而是：

1. 在 `MemoryPalaceApp` 根部注入 `ThemeManager`
2. 让几个**大根视图**显式观察它，保证整棵 subtree 会刷新：
   - `ContentView`
   - `SettingsView`
   - `ImportView`
   - `ProfileEditorSheet`
   - 其他独立 sheet / panel root

这样能避免每个小组件都加环境依赖。

---

## 3.5 App 根接线

### `MemoryPalaceApp.swift`

要做的不是只加 environment：

1. 新建 `@State private var themeManager = ThemeManager()`
2. 注入 `.environment(themeManager)`
3. 在 `WindowGroup` 根上接：
   - `preferredColorScheme(themeManager.preferredColorScheme)`
4. 保证切换 mode 时：
   - 系统控件
   - sheet
   - navigation
   - titlebar
   一起走正确浅/深模式

### `WindowConfigurator`

现在 `WindowConfigurator` 里有硬编码 `NSColor` 背景。  
这会在主题切换后滞后甚至直接错色。

所以这里也要改：

- 从当前 token 读取背景色
- 在主题变化时重新配置 window 背景

---

## 3.6 设置页结构

### `SettingsView.swift`

新增：

- `case theme = "主题"`

并接入：

- macOS tab
- iOS 设置列表入口

位置建议：

- `外观` 后面，`Prompt` 前面  
  让“字体/字号”等留在 `外观`，而“颜色主题”成为独立概念。

### 新增 `ThemeSettingsTab.swift`

这个文件负责主题总页，分成：

#### Section A：显示模式

- 系统
- 浅色
- 深色

交互参考 kelivo：

- 行式选择
- 当前项有勾选 / 选中态

#### Section B：主题列表

- 默认主题
- 自定义主题

每行展示：

- 小色板预览（多色圆点/条）
- 名称
- 当前是否选中
- 若是自定义主题，可进入编辑

#### Section C：背景策略

保留 `usePureBackground`

原因：

- kelivo 有
- 用户要自由度
- 这是一个很便宜但有效的“极简背景”控制项

但实现上会作为**运行时 override**，不是单独一套主题。

---

## 3.7 自定义主题编辑器

### 新增 `ThemeEditorView.swift` 或 `ThemeEditorSheet.swift`

支持编辑：

- Light
- Dark

两个分段或两个 section。

### 编辑项分组

#### 表面

- 主背景
- 侧栏背景
- 用户气泡
- AI 气泡
- 辅助底色

#### 文字

- 主文字
- 次文字
- 弱文字

#### 功能色

- 分支色 / 强调色
- 收藏色
- 危险色

### 控件

优先使用系统 `ColorPicker`。

仓库里已经在 `DrawingBoardSheet.swift` 用过 `ColorPicker`，说明平台能力没问题。

### 预览

编辑页里加小预览区，不然颜色编辑会很盲：

- 设置行预览
- 两个气泡预览
- 标题 / 次级文字预览
- branch 按钮 / link 色预览

### 辅助动作

首轮建议带上：

- `重置为默认`
- `用浅色生成深色初稿` 或 `重置深色`

这样深色不会一开始全靠手调。

---

## 3.8 深色模式方案

### 必做

这轮必须把 dark 路线做通。

### 默认深色 token

不会简单反相，也不会照抄 kelivo。  
会给记忆宫殿补一套自己的默认 dark seed，目标是：

- 主背景更深
- 侧栏 / 气泡有层次
- 薄荷强调色在 dark 下不刺眼
- 文字对比足够

### mode 与 theme 的关系

- 主题定义里同时有 `lightTokens` / `darkTokens`
- `themeMode` 决定当前取哪套
- `system` 时跟随系统浅/深

---

## 3.9 Markdown 和硬编码颜色清扫

### `MarkdownTheme.swift`

这轮必须一起改，不然后果是：

- UI 换了
- Markdown 代码块 / 表格 / 引用条还停留在旧色

计划：

- 把里面直接写死的 hex 改成主题 token 或 token 推导色

### 其余硬编码颜色

会做一轮扫：

- `Color(hex:)`
- 直接 `Color(...)`

筛出用户肉眼会看到、且应跟随主题的颜色。

处理原则：

- 跟 app chrome / 主要阅读体验强相关的，主题化
- 明显 feature 专用且语义独立的，先不强拉进全局主题

---

## 3.10 影响范围

### 必改文件

- `MemoryPalace/MemoryPalaceApp.swift`
- `MemoryPalace/Views/SettingsView.swift`
- `MemoryPalace/Views/AppearanceSettingsTab.swift`
- `MemoryPalace/Utils/Theme.swift`
- `MemoryPalace/Utils/MarkdownTheme.swift`

### 高概率新增文件

- `MemoryPalace/Utils/ThemeManager.swift`
- `MemoryPalace/Models/AppTheme.swift`
- `MemoryPalace/Views/ThemeSettingsTab.swift`
- `MemoryPalace/Views/ThemeEditorView.swift`

### 可能需要补观察的 root view

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/ImportView.swift`
- `MemoryPalace/Views/CharacterCardEditor.swift`
- `MemoryPalace/Views/RegexScriptEditor.swift`
- `MemoryPalaceApp.swift` 里的 `ProfileEditorSheet`

---

## 4. 实施步骤

## Step 1：主题模型与持久化底座

- [x] 新增主题数据模型（mode / token set / theme definition）
- [x] 新增 `ThemeManager`
- [x] 加本地持久化
- [x] seed 默认主题 + 自定义主题
- [x] seed 默认深色 token

完成标准：

- 主题状态能独立读写
- App 重启后能恢复 mode / selected theme / custom theme

## Step 2：改造 `Theme.swift` 为运行时 token 入口

- [x] 保留 `Theme.xxx` 调用面
- [x] 底层改成从 `ThemeManager.shared` 读取
- [x] 增加必要的颜色推导辅助

完成标准：

- 不需要全项目重命名颜色 API
- 旧调用点可以继续工作

## Step 3：根部接线 + 主题刷新机制

- [x] `MemoryPalaceApp` 注入 `ThemeManager`
- [x] `WindowGroup` 接 `preferredColorScheme`
- [x] 调整 `WindowConfigurator`
- [x] 给关键根视图加 theme 观察，保证子树刷新

完成标准：

- 切主题时 app 不用重启
- 浅/深切换时系统控件外观正确

## Step 4：设置页新增独立 `主题` tab

- [x] `SettingsView.SettingsTab` 新增 `.theme`
- [x] macOS tab 接入
- [x] iOS 列表入口接入
- [x] 新建 `ThemeSettingsTab`

完成标准：

- 设置页存在独立“主题”入口
- 不挤进“外观”

## Step 5：实现主题总页

- [x] mode 选择
- [x] 主题列表
- [x] 当前主题预览
- [x] `usePureBackground` 开关
- [x] 进入自定义编辑页

完成标准：

- 主题页结构和 kelivo 同级别，不是空壳

## Step 6：实现自定义主题编辑器

- [x] Light token 编辑
- [x] Dark token 编辑
- [x] 预览区
- [x] 重置能力
- [x] 深色初稿辅助动作

完成标准：

- 用户能真改颜色
- 保存后全局即时生效

## Step 7：Markdown 与关键硬编码颜色同步主题化

- [x] `MarkdownTheme.swift` 去硬编码
- [x] 扫描关键 UI 硬编码色
- [x] 补到主题 token 或语义色

完成标准：

- 切换主题时，聊天阅读区不碎

## Step 8：验证

- [x] `xcodebuild -scheme MemoryPalace build`
- [ ] macOS 手动验证：
  - [ ] 系统 / 浅色 / 深色
  - [ ] 默认主题 / 自定义主题
  - [ ] 编辑浅色 token 即时生效
  - [ ] 编辑深色 token 即时生效

## Step 9：主题保存 / 主题选择 / 背景图片扩展

- [x] 主题支持另存为新主题
- [x] 已保存主题支持选择 / 编辑 / 删除
- [x] 主题支持绑定背景图片并持久化到本地
- [x] 主题预览卡显示背景图氛围
- [x] 根视图与设置页背景跟随当前主题背景图

完成标准：

- 主题不再只有“默认 / 自定义”两种状态
- 用户保存后的主题可以像真正主题库一样切换
- 背景图跟主题一起切换，不是单独的临时开关
  - [ ] 重启后持久化
  - [ ] window/titlebar/全屏顶部背景正确
- [ ] iOS 手动验证：
  - [ ] 设置入口正常
  - [ ] sheet / navigation 背景跟主题走
  - [ ] 深色模式下可读性正常

---

## 5. 风险与防守

### 风险 A：主题变化后局部 view 不刷新

防守：

- 让关键 root view 观察 `ThemeManager`
- 优先验证 `ContentView / SettingsView / Chat / Sidebar / sheets`

### 风险 B：深色 token 第一版很丑

防守：

- 默认 dark seed 手工定一版
- 同时给用户开放 custom dark 编辑

### 风险 C：`usePureBackground` 和自定义颜色互相打架

防守：

- 明确它是 runtime override
- UI 上写清楚优先级

### 风险 D：Markdown / titlebar 留旧色

防守：

- `MarkdownTheme.swift` 必进本轮
- `WindowConfigurator` 必进本轮

---

## 6. 本轮结束定义

这一轮完成后，应达到：

1. 主题不再是写死常量，而是运行时系统。
2. 设置页里有独立 `主题` tab。
3. `系统 / 浅色 / 深色` 跑通。
4. 有一个可编辑的自定义主题。
5. 自定义主题可分别编辑 light / dark。
6. 主题切换能真正影响全 app，而不是只改设置页。

---

## 7. Todo Tracker

- [ ] 1. 新增主题模型与 `ThemeManager`
- [ ] 2. 改造 `Theme.swift` 为运行时 token
- [ ] 3. App 根接入 theme mode / preferredColorScheme / window 背景
- [ ] 4. 设置页新增独立 `主题` tab
- [ ] 5. 实现主题总页（mode / list / pure background）
- [ ] 6. 实现自定义主题编辑器（light / dark / preview）
- [ ] 7. 改造 `MarkdownTheme.swift` 与关键硬编码色
- [ ] 8. 跑 build + 手动验证 macOS / iOS

---

## 8. 状态

⚠️ **DON'T IMPLEMENT YET — 等粟粟批注**
