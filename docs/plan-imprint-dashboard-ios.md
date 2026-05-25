# Plan: iOS 右屏幕整理 + 原生 Dashboard 接入

> 基于 `research-imprint-dashboard-ios.md`，并吸收新反馈：**“目前右屏幕一坨”**

---

## 1. 目标

把 iOS 版现在的第 3 屏 / 右屏幕，从一个功能零散、信息层级不清的“更多页”，整理成一个**原生、清爽、像宫殿自己长出来的 dashboard 页**。

这次只做这一小段，不扩散：

- 不嵌 `imprint` 的 Web dashboard
- 不接 `~/.imprint` 数据源
- 不做宿主机服务管理
- 不顺手大改整套 iOS 导航

核心目标只有一个：

**让 iOS 右屏幕不再“一坨”，而是成为稳定、好看的“日历 + 记忆”入口。**

---

## 2. 这次计划默认采用的产品判断

### 2.1 iOS 的“右边”不做几何右栏，而做第 3 屏 dashboard

当前 iOS 已经是三屏 swipe 结构：

- 左：对话列表
- 中：聊天
- 右：更多

所以这次不强行模拟 macOS 的第三列，而是把第 3 屏升级成：

- **Dashboard 页**

也就是保留现有 iOS 的导航心智，只把内容整理好。

### 2.2 设置页里的记忆 tab 保留

设置页已经有完整的记忆管理能力，适合“高级管理”：

- 提取模型
- 统计
- 编辑 / 删除
- 手动添加

右屏幕的 dashboard 负责：

- 日常浏览
- 快速切换
- 快速添加 / 快速查看

所以这次不删除设置页记忆 tab，只做分工：

- Dashboard = 日常入口
- Settings = 高级管理

### 2.3 UI 方向：轻整理，不做大翻修

遵守当前项目规则：

- 用户对 UI 变动敏感，宁可小步迭代
- 不要一次改太多

所以这次不追求“非常炫的新样式”，而是：

- 把结构整理清楚
- 把 spacing / header / tab / 操作入口整理干净
- 保留暖奶白 + 薄荷灰现有气质

---

## 3. 现状问题拆解

### 问题 A：第 3 屏的信息架构太弱

现在 Page 2 只是：

- 导入
- 设置

这不是 dashboard，只是“更多”入口。

### 问题 B：现有 `RightPanelView` 是按 macOS 侧栏尺度写的

现在的 `RightPanelView`、`CalendarPanelView`、`MemoryPanelView` 能复用，但它们的默认感觉更像：

- 窄侧栏
- inspector
- 辅助区

如果直接硬塞到 iPhone 全屏，很容易：

- 顶部太空或太挤
- tab 太小
- 卡片节奏不对
- 看起来像把边栏放大，不像真正的页面

### 问题 C：右屏幕和导入/设置入口可能互相抢位

如果只把 dashboard 接上，不重排导入/设置入口，结果会变成：

- dashboard 也想占主位
- 导入 / 设置也想占主位

最终还是“一坨”。

---

## 4. 计划中的页面结果

目标形态：

### 第 3 屏顶部

- 一个清晰的页面标题 / 头部
- 右上或头部区域保留两个轻量入口：
  - 导入
  - 设置

### 第 3 屏主体

- 主体直接是原生 dashboard 内容
- 默认展示 `RightPanelView` 的能力，但按 iOS 重新排版

### 主体内部

- 顶部 tab 清晰切换：
  - 日历
  - 记忆
- 日历模式：月历 + 当天对话
- 记忆模式：分层记忆列表 + 快速添加

### 整体体验

- 看起来像 iOS 页面，而不是 macOS 侧栏放大版
- 信息密度稳定
- 导航职责清楚

---

## 5. 文件与影响范围

### `MemoryPalace/Views/ContentView.swift`

职责：

- 改造 iOS Page 2
- 把“更多”改成真正的 dashboard 入口页
- 重新安放导入 / 设置按钮

预计改动：

- 把当前 `NavigationStack + List` 的 Page 2 改成专用 dashboard 页面
- 保留现有 `showImporter` / `showSettings` sheet 机制
- 尽量不碰 Page 0 / Page 1 行为

风险：

- iOS 页间切换逻辑不能被破坏
- 聊天页顶部按钮跳转到 Page 2 仍要直观

### `MemoryPalace/Views/MemoryPanelView.swift`

职责：

- 当前 `RightPanelView` 容器
- `MemoryPanelView` 本体

预计改动：

- 为 `RightPanelView` 增加 iOS 友好的页面级呈现
- 调整 tab 区、padding、字号、section 节奏
- 让 `MemoryPanelView` 在全屏页面里更像主内容，而不是侧栏附件

风险：

- 不能把 macOS 右栏样式改坏
- 需要用 `#if os(iOS)` 做局部适配，而不是把 shared view 搞分叉失控

### `MemoryPalace/Views/CalendarPanelView.swift`

职责：

- 日历和当天对话列表

预计改动：

- 优化 iOS 全页场景下的 header / 卡片边距 / 空状态
- 检查是否需要更稳的内容留白和底部安全区处理

风险：

- 不能破坏 macOS 当前右栏的视觉平衡

### 可能波及：`MemoryPalace/Views/SettingsView.swift`

默认不做大改，但可能需要非常小的文案/入口协调，避免用户不知道：

- 快速看记忆去右屏幕
- 深管理还在设置

如果没有必要，这个文件不改。

---

## 6. 具体执行步骤

### Step 1: 先把 iOS 第 3 屏从“更多”改成 dashboard 容器

做法：

- 在 `ContentView.swift` 中为 Page 2 建一个更明确的 dashboard 页面
- 保留 `NavigationStack`
- 页面主标题从“更多”调整为更像功能页的标题
- 导入 / 设置作为头部轻量入口，不再占整屏主体

结果：

- 第 3 屏先从信息架构上摆脱“一坨”

### Step 2: 把 `RightPanelView` 接进 iOS 第 3 屏

做法：

- 让 Page 2 的主体直接承接 `RightPanelView`
- 保持 tab 逻辑继续用现有 `rightPanelTab`
- 不复制一套新业务逻辑

结果：

- iOS 与 macOS 共用同一套“右侧功能”
- 业务上不分叉

### Step 3: 给 `RightPanelView` 做 iOS 页面级适配

做法：

- 调整 iOS 下 tab 区视觉重量
- 让上部切换器更像页面 segment，而不是细小 inspector pill
- 重新看 padding、顶部间距、底部留白

结果：

- 从“边栏放大版”变成“完整页面”

### Step 4: 分别微调 `CalendarPanelView` / `MemoryPanelView`

做法：

- iOS 下增大关键点击区
- 优化卡片与容器的节奏
- 处理空状态与底部区域
- 检查记忆输入区域在 iPhone 上是否挤压内容

结果：

- 日历模式和记忆模式都在 iOS 全屏下成立

### Step 5: 做入口去重与职责收口

做法：

- 导入 / 设置留在右屏幕头部或轻量操作区
- 设置里的记忆 tab 保持“高级管理”角色
- 不在 dashboard 再重复放太多“管理型”文案

结果：

- 页面职责清晰，不再所有东西堆一起

### Step 6: 验证共享代码两边都没坏

必须验证：

- `xcodegen generate`
- `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- `xcodebuild -scheme MemoryPalace build`

如果 iOS 好了但 macOS 被共用视图拖坏，这次就不算完成。

---

## 7. 实施时的具体约束

### 约束 1：不新开大分支架构

这次不拆新模块，不搞一堆抽象层。  
够用就好。

### 约束 2：优先 `#if os(iOS)` 的小范围适配

共享视图仍然保持共享。  
只在确实需要时做 iOS 局部样式差异。

### 约束 3：不把 Imprint 的宿主管理能力混进来

这次只借鉴 dashboard 的“信息组织方式”，不接：

- service status
- process control
- remote tools
- paired devices
- allowed commands

### 约束 4：不要让 UI 变花

不为了“像 dashboard”就塞很多卡片和图标。  
先把右屏幕变干净、明确、稳定。

---

## 8. 风险与回退策略

### 风险 1：共用视图改动影响 macOS

策略：

- 优先局部条件编译
- 每步后都 build macOS

### 风险 2：iOS 页面层级变复杂

策略：

- 只改 Page 2
- 不动整体三屏架构

### 风险 3：记忆模式底部输入区把列表挤坏

策略：

- 先保守调整 spacing / safe area
- 不同时引入大样式改造

---

## 9. 验证标准

完成这一轮后，我认为至少要满足：

1. iOS 第 3 屏不再是只有“导入/设置”的空壳页
2. 第 3 屏主体是清晰的 dashboard，而不是零碎功能堆叠
3. 日历 / 记忆切换在 iPhone 上看起来像完整页面
4. 导入 / 设置入口仍然存在，但不抢主位
5. `MemoryPalaceIOS` build 通过
6. `MemoryPalace` macOS build 也通过

---

## 10. Todo Checklist

- [x] 1. 把 iOS Page 2 从“更多 List”重构为 dashboard 容器页
- [x] 2. 为 iOS Page 2 安排清晰的头部与导入/设置轻量入口
- [x] 3. 把 `RightPanelView` 接入 iOS Page 2 主体
- [x] 4. 为 `RightPanelView` 增加 iOS 页面级样式适配
- [x] 5. 微调 `CalendarPanelView` 在 iOS 全屏下的节奏与留白
- [x] 6. 微调 `MemoryPanelView` 在 iOS 全屏下的节奏与底部区域
- [x] 7. 检查并处理 dashboard 与 Settings 记忆入口的职责分工（本轮保留 Settings 作为高级管理，dashboard 负责日常入口，无需额外改 `SettingsView`）
- [x] 8. `xcodegen generate`
- [x] 9. `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- [x] 10. `xcodebuild -scheme MemoryPalace build`

---

## 11. 暂停线

已按这份 plan 执行完当前范围，并完成双端 build 验证。
