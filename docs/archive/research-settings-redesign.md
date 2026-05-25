# Research: 设置页重构

> CC 深读现有设置页代码，2026-03-25

---

## 1. 现有架构

### SettingsView.swift（553 行）

一个 `ScrollView` 里堆了所有设置，用 `Divider` 分隔：

1. **楼层**（ProfileSwitcher） — 58-66 行
2. **气泡标签**（userName/assistantName + 确认按钮） — 70-116 行
3. **字体**（preset 列表 + 导入 + 缩放提示） — 120-196 行
4. **API**（6 家提供商 API key 行内输入） — 200-246 行
5. **导出**（模式选择 + 批量导出） — 250-301 行
6. **导入历史**（ImportHistoryView，独立子视图） — 305-306 行

### 问题

- **一个长滚动列表**，没有分类结构，找设置靠滚动
- **API 区域太挤** — 6 家提供商每家一个 HStack 行，SecureField + 保存按钮挤在一行里，提供商名字只有 70pt 宽
- **固定尺寸** `.frame(width: 400, height: 560)` — 内容已经溢出底部（之前的 bug）
- **楼层切换器和气泡标签耦合** — 改了楼层应该自动切标签，但现在是独立的
- **未来会加更多设置** — temperature / max_tokens / 主题 / 快捷键 / context window 等

### 呈现方式

- 从 ContentView 以 `.sheet` 弹出
- 无 NavigationStack，纯 VStack + ScrollView

### 辅助视图

- `ExportModeRow`（选中/未选中的行）
- `FontOptionRow`（字体选择行，带预览 + 删除）
- `SettingsTextField`（标签 + 输入框）
- `ImportHistoryView`（独立文件，有自己的 @Query）

---

## 2. macOS 设置页常见模式

### 方案 A: TabView（标签栏顶部）
```
[通用] [API] [导入导出]
─────────────────────────
 内容区
```
SwiftUI 原生 `TabView`，每个 tab 是独立的 View。简单直接，macOS 原生风格（类似 Xcode Preferences）。

### 方案 B: 左侧 List + 右侧内容（系统设置风格）
```
┌──────┬──────────────┐
│ 通用  │              │
│ API  │   内容区      │
│ 数据  │              │
└──────┴──────────────┘
```
更灵活，适合设置项很多的情况。但对于当前 3-4 个分类来说过重。

### 方案 C: 保持滚动，加锚点跳转
不改结构，在顶部加 tab 按钮跳到对应 section。最小改动，但没解决根本问题。

### 推荐：方案 A（TabView）

理由：
- 当前只有 3 个分类，TabView 刚好
- macOS 原生风格，不需要自定义布局
- 每个 tab 独立 View，代码自然分离
- 未来加新 tab 直接 append

---

## 3. 拆分方案

### Tab 1: 通用
- 楼层切换（ProfileSwitcher）
- 气泡标签（userName / assistantName）
- 字体设置

### Tab 2: API
- 提供商列表（卡片式，每家一张）
  - 提供商名称 + 状态指示
  - API Key 输入（SecureField，独立行，不挤）
  - 该提供商下的可用模型列表（折叠/展示）
- 比现在的一行式宽敞很多

### Tab 3: 数据
- 导入历史（ImportHistoryView）
- 导出设置 + 批量导出

---

## 4. 影响范围

| 文件 | 改动 |
|------|------|
| SettingsView.swift | 重写：拆成 TabView + 3 个 tab 子视图 |
| ContentView.swift | 不变（仍然 .sheet 呈现 SettingsView） |
| ImportHistoryView.swift | 不变（嵌入到"数据"tab） |
| MemoryPalaceApp.swift | 不变（ProfileSwitcher 和 ProfileEditorSheet 不动） |

只改 SettingsView.swift 一个文件。辅助视图（ExportModeRow / FontOptionRow / SettingsTextField）保留，移到对应 tab 里。

---

## 5. 风险

- **TabView 在 sheet 里的表现** — macOS SwiftUI 的 TabView 在 sheet 里可能有样式问题（tab bar 跟 sheet 标题栏冲突）。需要测试。如果有问题，用手写的 tab bar（HStack 按钮 + conditional content）替代。
- **Sheet 尺寸** — 不同 tab 内容高度不同。用 `.frame(width:height:)` 固定尺寸，或让 sheet 自适应（可能导致窗口跳动）。建议固定尺寸。
- **状态保持** — 切换 tab 时不应丢失未保存的输入。@State 变量在 TabView 切换时会保持（SwiftUI 不会销毁未显示的 tab view）。
