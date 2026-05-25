# Research: design-dna 适配记忆宫殿

> **Evaluator** 研究，2026-03-25
> 来源：[zanwei/design-dna](https://github.com/zanwei/design-dna) — Agent Skill，提取/结构化/应用设计 DNA

---

## 1. design-dna 是什么

一个三维设计身份系统：

| 维度 | 内容 | 对记忆宫殿的适用性 |
|------|------|-------------------|
| **Design System**（可量化 token） | 颜色、字体、间距、圆角、阴影、组件样式 | **高** — 直接映射到 Theme.swift |
| **Design Style**（定性感知） | 情绪、视觉语言、构图、品牌调性 | **中** — 作为设计决策参考文档 |
| **Visual Effects**（特效渲染） | Canvas、WebGL、粒子、着色器、滚动效果 | **低** — 纯 Web 技术，macOS 原生无直接对应 |

核心工作流：Reference → Analyze → DNA JSON → Generate

---

## 2. 记忆宫殿可以怎么用

### 用法 A: 把现有设计编码为 DNA JSON（立即可用）

**问题：** 记忆宫殿的设计语言散落在多处 — `Theme.swift` 有颜色常量，`CLAUDE.md` 有文字描述（"暖奶白+浅灰薄荷，不要蓝色不要黄色"），`FontManager.swift` 有字体逻辑，各个 View 文件里有硬编码的间距/圆角。新的 Claude session 要理解设计语言需要读多个文件。

**方案：** 按 design-dna schema 的 Dimension 1 + 2 格式，从当前代码提取一份 `design-dna.json`，作为**设计的 single source of truth**。

好处：
- 任何 Claude session（Generator/Evaluator）一读这个文件就知道设计规范
- 做 UI 评审时有明确的对照标准（"这个圆角跟 DNA 里定义的 border_radius.medium 不一致"）
- 不用每次都在 CLAUDE.md 里写"不要蓝色"

**注意：** 这不替代 Theme.swift（运行时用的是 Swift 常量），而是一份给 agent 读的参考文档。

### 用法 B: 主题/皮肤系统的数据格式（对接待办功能）

CLAUDE.md 待办里有"皮肤/主题切换"。design-dna 的 schema 可以直接作为**主题文件格式**：

```
themes/
├── warm-ivory.json      ← 当前默认主题（暖奶白）
├── dark-mode.json       ← 深色模式
└── custom-theme.json    ← 用户自定义
```

每个 JSON 包含 design_system 里的颜色、字体、间距等 token。App 启动时加载选中的 JSON，映射到 Theme.swift 的属性。

**但这是远期功能**，当前主题只有一套，不需要过早抽象。先做用法 A 就够了。

### 用法 C: 从参考 UI 提取 DNA 指导新功能设计（Generator + Evaluator 协作用）

设计新 UI 时（比如设置页重构），可以：
1. 粟粟提供一个喜欢的参考 UI 截图
2. 用 design-dna 的 Analyze 流程提取参考 DNA
3. 跟记忆宫殿的现有 DNA 做 diff — 哪些可以借鉴，哪些跟现有设计冲突
4. Generator 按调和后的 DNA 实现，Evaluator 按 DNA 验收

---

## 3. schema 适配：Web → SwiftUI 映射

design-dna schema 是为 Web（HTML/CSS/JS）设计的。适配到 SwiftUI 需要映射：

### 直接对应

| DNA 字段 | SwiftUI 对应 | 现有代码 |
|---------|-------------|---------|
| `color.primary.hex` | `Color(hex:)` | `Theme.branchIndicator` |
| `color.surface.background` | `.background()` | `Theme.mainBg` (#FFFBF6) |
| `color.surface.card` | `.background()` | `Theme.sidebarBg` (#E7EEEC) |
| `typography.font_families.body` | `.font(.custom())` | `FontManager.font()` |
| `typography.type_scale.body.size` | `.font(size:)` | 硬编码 13.5 |
| `spacing.base_unit` | `.padding()` | 散落在各 View |
| `shape.border_radius.medium` | `.cornerRadius()` | 硬编码 8-12 |
| `elevation.levels.low` | `.shadow()` | 较少使用 |

### 需要简化（Web 概念在 macOS 里不适用）

| DNA 字段 | 处理 |
|---------|------|
| `layout.breakpoints` | 删除 — macOS 没有响应式断点 |
| `layout.columns` / `grid_system` | 简化 — NavigationSplitView 已定义布局 |
| `iconography.preferred_set` | 固定 SF Symbols |
| `motion.entrance_pattern` | SwiftUI `.transition()` + `.animation()` |

### 完全不适用（Dimension 3 的大部分）

| DNA 字段 | 理由 |
|---------|------|
| `visual_effects.background_effects` | 无 Canvas/WebGL |
| `visual_effects.particle_systems` | 可以用 CAEmitterLayer 但过度 |
| `visual_effects.3d_elements` | 不需要 |
| `visual_effects.shader_effects` | Metal shader 是另一个世界 |
| `visual_effects.cursor_effects` | macOS 不自定义光标 |

**结论：** 只取 Dimension 1（design_system）+ Dimension 2（design_style）的子集，做一个精简版 schema。

---

## 4. 建议的行动

### 立即做（跟设置页重构一起）

1. **提取记忆宫殿 Design DNA** — 从 Theme.swift + 各 View 文件提取当前设计的 token，写成 `docs/design-dna.json`（精简版 schema）
2. **作为设计评审依据** — Evaluator review 新 UI 时对照 DNA 检查一致性

### 设置页重构时参考

Generator 做 plan 时可以参考 DNA 里的 `components` 定义：
- `button_style` → 当前胶囊按钮 + branchIndicator 色
- `input_style` → 当前圆角框 + mainBg 底色
- `card_style` → 用于 API provider 卡片设计
- 这样新组件跟现有组件视觉一致

### 远期（主题系统上线时）

把 `design-dna.json` 从"参考文档"升级为"运行时配置"：
- Theme.swift 从 JSON 文件读取颜色/间距
- 设置页加"主题"tab
- 支持导入/导出主题 JSON

---

## 5. 跟 Generator 的分工

| 角色 | 做什么 |
|------|--------|
| **Evaluator（我）** | 从现有代码提取 DNA JSON；review 时对照 DNA 检查新 UI 一致性 |
| **Generator** | 在 plan 里引用 DNA token 值；实现时按 DNA 定义的组件样式写代码 |
| **粟粟** | 决定 DNA 里的主观字段（mood、personality）；提供参考 UI 截图 |

— Evaluator
