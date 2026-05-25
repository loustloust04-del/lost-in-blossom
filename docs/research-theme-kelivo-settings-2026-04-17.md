# Research: 设置页【主题】对齐 kelivo

> 时间：2026-04-17  
> 工作树：`/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings`  
> 参考仓库：`/Users/susu/Desktop/susu-project/记忆宫殿/kelivo`

---

## 0. 这次任务的理解

我当前把你的要求理解成：

1. **不动 `master`**，只在新 worktree 里推进。
2. 给记忆宫殿的设置页新增一个明确的 **「主题」能力**。
3. 参考 `kelivo` 外层仓库，把它现在已经成型的 **主题系统机制** 抄过来，而不是只做一个静态配色列表 UI。

这里有一个关键歧义，我先写死在文档里，等你批：

- **理解 A（我当前默认）**：抄的是 **功能结构和交互机制**  
  也就是：主题模式、主题列表、全局应用、持久化、设置入口组织方式。
- **理解 B（更字面）**：连 `kelivo` 现有那些 palette 颜色本身也一起照搬  
  这会直接撞上记忆宫殿现有设计约束里的“**不要蓝色、不要黄色**”。

  我当前更推荐 **A**：抄机制，不生搬 palette 本体。

---

## 1. 已读材料

### 记忆宫殿当前代码

- `MemoryPalace/Views/SettingsView.swift`
- `MemoryPalace/Views/AppearanceSettingsTab.swift`
- `MemoryPalace/Utils/Theme.swift`
- `MemoryPalace/Utils/MarkdownTheme.swift`
- `docs/design-dna.json`
- `docs/archive/research-design-dna-adaptation.md`
- `docs/PROJECT_ROADMAP.md`

### kelivo 参考代码

- `kelivo/lib/features/settings/pages/settings_page.dart`
- `kelivo/lib/features/settings/pages/display_settings_page.dart`
- `kelivo/lib/features/settings/pages/theme_settings_page.dart`
- `kelivo/lib/core/providers/settings_provider.dart`
- `kelivo/lib/theme/palettes.dart`
- `kelivo/lib/main.dart`

---

## 2. 记忆宫殿当前状态

### 2.1 设置页现在没有“主题系统”，只有“外观设置”

当前 `SettingsView` 里只有 `appearance = "外观"`，没有单独的「主题」入口。  
`AppearanceSettingsTab.swift` 当前只负责：

- 字体选择
- 导入字体
- 聊天字号缩放
- 全文展开
- 边缘模糊

也就是说，**现在的“外观”并不管理颜色主题**。

### 2.2 当前主题是编译期常量，不是运行时主题

`Theme.swift` 现在是一个 `enum Theme`，里面全是静态常量：

- `mainBg`
- `sidebarBg`
- `userBubble`
- `assistantBubble`
- `accent`
- `textPrimary / Secondary / Muted`
- `favorite / danger / branchIndicator`

这代表：

- 当前 app **只有一套主题**
- 颜色切换不是“换个选项就能生效”
- 要做主题，必须把这套“静态常量引用”改造成“运行时可切换的 token 来源”

### 2.3 颜色 token 被全项目深度耦合

我粗扫了当前 worktree，`Theme` 关键 token 被大量直接引用：

- `Theme.branchIndicator`：220 次
- `Theme.textMuted`：308 次
- `Theme.mainBg`：131 次
- `Theme.textPrimary`：101 次
- `Theme.textSecondary`：101 次
- `Theme.accent`：63 次
- `Theme.sidebarBg`：48 次

这不是设置页单文件改动，是真正的**全局主题基础设施改动**。

### 2.4 Markdown 还有一层硬编码

`MarkdownTheme.swift` 里除了引用 `Theme.textPrimary / branchIndicator` 外，还直接写了这些 hex：

- `#E7EEEC`
- `#D5DCD9`
- `#FFFBF6`

这意味着即使把主 UI 改成主题化，**Markdown 区域也会残留旧色**，除非一起改。

### 2.5 项目文档早就预告了“主题”需求，但还没落地

`docs/PROJECT_ROADMAP.md` 里已经把 `皮肤/主题切换` 列为待办。  
`docs/archive/research-design-dna-adaptation.md` 也已经明确写过：

- `design-dna.json` 可以升级成主题文件格式
- 运行时主题需要从 token 驱动，而不是继续只靠 `Theme.swift` 静态常量

所以这次不是“补个 tab”而已，实际上是把一项长期待办真正开始基础设施化。

---

## 3. kelivo 的主题系统，实际上由三层组成

### 3.1 顶层：Color Mode

`settings_page.dart` 顶层就有一行：

- `Color Mode`
- 可选 `System / Light / Dark`
- 通过 bottom sheet 选择
- 持久化到 `SettingsProvider.themeMode`

这层控制的是 **亮暗模式策略**，不是 palette 本身。

### 3.2 中层：Display -> Theme Settings

`display_settings_page.dart` 里有一个导航项：

- `Theme Settings`
- 右侧显示当前 palette 名
- 点进去进入独立主题页

也就是说在 kelivo 里：

- **颜色模式** 和 **主题详情** 是分开的
- “显示”页是收口页
- 主题只是 Display 下的一个子能力

### 3.3 主题详情页：Theme Settings

`theme_settings_page.dart` 里的核心功能：

- `useDynamicColor`（仅 Android 且设备支持时显示）
- `usePureBackground`
- palette 列表
- palette 选中态

palette 行长这样：

- 左侧彩色圆点
- 中间 palette 名
- 右侧勾选

这页本身是很轻的，但它背后依赖的是完整的状态系统。

### 3.4 状态层：SettingsProvider 持久化

`settings_provider.dart` 持久化了这些关键字段：

- `themeMode`
- `themePaletteId`
- `useDynamicColor`
- `usePureBackground`

并提供这些写入口：

- `setThemeMode`
- `setThemePalette`
- `setUseDynamicColor`
- `setUsePureBackground`

也就是说，kelivo 的“主题”不是 View 层状态，而是**全局设置状态**。

### 3.5 应用层：main.dart 真正把主题接进根

`main.dart` 做了真正关键的一步：

1. 从 `settings.themePaletteId` 取 palette
2. 构建 `light` / `dark` theme
3. 结合 `themeMode`
4. 把主题塞进根级 `MaterialApp`

没有这一步，前面的 settings 页只会是“看起来像能切换，实际上没接线”的假功能。

---

## 4. kelivo 里哪些东西能抄，哪些不能直接抄

### 4.1 可以直接抄的，是“机制”

这些东西在记忆宫殿里是合理的：

- `主题模式`：系统 / 浅色 / 深色
- `主题列表`
- `当前主题名称`
- 设置页中的入口分层
- 主题偏好持久化
- 根级统一应用

### 4.2 不能一比一抄的，是 Android 专属部分

`useDynamicColor` 是 Android Material You 机制。  
记忆宫殿是 **macOS + iOS**，这里没有 Android 运行时能力。

如果硬抄，只会得到：

- 一个无意义开关
- 或者需要重新定义成别的东西（比如“跟随系统强调色”）

所以它**不能原样照搬**。

### 4.3 不能直接照搬的，还有 kelivo palette 本体

`kelivo` 当前 palette 集合里明确有：

- blue
- green
- purple
- yellow
- smoky rose
- terracotta
- monochrome

而记忆宫殿现有设计 DNA 明确写了：

- **不要蓝色**
- **不要黄色**

如果你这次真要“连 palette 也照抄”，那就是主动推翻现有项目视觉约束。  
这不是技术问题，是**产品方向变更**。

---

## 5. 对记忆宫殿来说，真正的改动面

如果目标是“把 kelivo 的主题功能抄过来，并且真的可用”，那至少会波及下面几层：

### 5.1 设置层

- `SettingsView.swift`
- `AppearanceSettingsTab.swift`
- 可能新增 `ThemeSettingsTab.swift` / `ThemeModeSheet.swift`

要决定：

- 「主题」是作为一个新 tab
- 还是挂在「外观」下面

### 5.2 状态层

需要新增全局主题状态，比如：

- `themeMode`
- `themePaletteId`
- `usePureBackground`

这些很可能放在：

- `@AppStorage`
- 或单独 `ThemeManager`
- 或环境对象

### 5.3 token 层

`Theme.swift` 不能继续只是一组固定 `static let`。  
要么：

- 变成“从当前 palette 解析颜色”的动态访问层

要么：

- 引入新的 `ThemePalette / ThemeTokens / ThemeResolver`
- 再让旧 `Theme.xxx` 作为兼容 facade

### 5.4 根注入层

需要从 app 根把当前主题带到全局，不然只能局部换色。  
这轮至少要审：

- `MemoryPalaceApp.swift`
- `ContentView.swift`
- 任何顶层 sheet / panel 的背景来源

### 5.5 消费层

所有直接读 `Theme.xxx` 的视图，未来都要跟着走动态 token。  
如果主题改成运行时状态，最难的不是设置页，而是**消费端统一接上**。

### 5.6 Markdown / 辅助样式层

`MarkdownTheme.swift` 也要一起主题化。  
否则会出现：

- 页面底色已切换
- Markdown 代码块、表格、引用条还停留在旧主题

看起来会非常碎。

---

## 6. 当前我认为最需要你确认的点

### 6.1 你要的是“机制照抄”，还是“颜色也照抄”

我当前推荐：

- **抄 kelivo 的系统结构**
- **不用 kelivo 的蓝/黄/purple palette**
- 改成 Memory Palace 自己的 theme family

  这是最不撕裂产品 DNA 的做法。
  {{当然不抄颜色，它颜色那么丑。。我们先搞一个自定义颜色，到时候再做出成套的主题。其实我已经有色板了}}

### 6.2 「主题」是独立 tab，还是并入「外观」

从当前信息看，两种都说得通：

- **独立 tab：主题**
  
  - 更贴近你这次的明确指令“做一个【主题】”
  - 结构更像 kelivo 那种单独能力
- **并入外观**
  
  - 改动更小
  - 但“外观”会越来越胖

    我当前偏向：**独立 tab：主题**。
    {{独立}}

### 6.3 是否真的要做深色模式

kelivo 的顶层能力里，`ThemeMode` 是很核心的一环。  
但对记忆宫殿来说，深色模式不是一个免费附赠项，因为：

- 当前所有 token 都是暖浅色系
- 很多表面层次靠“浅色之间的细微差异”建立
- 直接反相会很难看

所以：

- 如果你说“抄 kelivo 全部主题功能”，那深色模式大概率必须做
- 但它会明显放大这次工作量
  {{当然要做深色模式，不是抄不抄颜色的问题}}

### 6.4 `usePureBackground` 要不要保留

kelivo 的 `usePureBackground` 是：

- 强制纯白 / 纯黑背景

记忆宫殿的设计本体恰恰是：

- 暖奶白
- 浅灰薄荷
- 微妙层次

  如果把这个开关原样带过来，等于允许用户一键“去掉设计语言”。  
  这未必是你想要的。
  {{先别管设计语言，先把自定义自由度拉满，我的主题好看用户自然会选我的。}}

---

## 7. 我的当前判断

如果这次要做得正确，而不是做一个空壳页面，我建议把目标定成：

### 推荐理解（我建议按这个方向 plan）

**给设置页新增独立「主题」tab，借 kelivo 的主题系统结构，但主题 palette 使用记忆宫殿自己的 token 家族；先做真正可工作的全局主题切换基础设施，再决定是否扩到深色模式和更多 palette。**

这样做的好处：

- 符合你说的“抄 kelivo 的功能”
- 不会把 Memory Palace 现有气质直接抹掉
- 技术上能形成可持续扩展的主题底座

---

## 8. 明确不建议的做法

### 不建议 1：只做一个主题 tab UI，不接全局

这会变成：

- 设置页里能选
- app 实际没切

属于假功能。

### 不建议 2：直接把 `Theme.swift` 改成一坨 `if palette == ...`

短期能跑，但很快会失控。  
这轮如果真的开主题，应该顺手把 token 入口整理清楚。

### 不建议 3：把 kelivo 所有 palette 原色直接搬进来

这会跟当前设计 DNA 冲突太大，尤其蓝 / 黄。

---

## 9. 进入 plan 前，我会默认等你批这个 research

我当前不会直接写实现计划。  
等你在这份文档上确认方向后，我再进入下一轮 plan，并把执行 todo 写出来。

