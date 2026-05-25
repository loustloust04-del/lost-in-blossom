# Review: 设置页重构 Research

> **Evaluator** 批注，2026-03-25
> 评审对象：`docs/research-settings-redesign.md`（Generator, 同日）

---

## 总体评价

Research 质量不错，对现有代码的梳理准确，方案选择（TabView）合理。以下是需要补充或修正的点。

---

## 批注

### 1. [重要] API Tab 设计需要跟 Phase 1.5 对齐

Research 提到 API tab 会用"卡片式，每家一张"，但没有跟 `docs/phase-1.5-research.md` 的需求对接：

- Phase 1.5 要求 **ChatService 重构成 protocol**，Anthropic 和 OpenAI 走不同实现
- 模型列表需要 **按提供商分组 + 友好名称**，部分提供商支持动态 `/models` 端点
- API tab 不是只放 key 输入框，还需要：
  - 每个 provider 的**连接状态**（key 是否有效，能否拉取模型列表）
  - **默认模型选择**（当前用 `UserDefaults["selectedChatModel"]`，应该绑定到 provider）
  - **模型参数**（temperature / max_tokens）— research 在"问题"section 提到了但 tab 设计里没给位置

**建议：** Plan 阶段把 API tab 拆成两个子区域 — "提供商管理"和"模型参数"，或者干脆 API 和模型参数分成两个 tab（变成 4 tab）。

### 2. [确认] TabView 在 sheet 里的风险是真实的

我查了 SwiftUI 行为：macOS 的 `TabView` 在 `.sheet` 里默认会用系统 tab bar 样式，跟 sheet 的圆角和标题栏可能冲突。特别是我们的 sheet 已经有自定义 header（返回按钮 + "设置"标题），加上 TabView 自己的 tab bar 会出现双标题栏。

**建议：** 直接用手写 tab bar（HStack 按钮 + 条件内容切换），这样：
- 视觉跟现有设计语言一致（暖奶白配色，不用系统蓝色高亮）
- 避免 TabView 在 sheet 里的样式兼容问题
- 更容易控制切换动画

Generator 自己也提到了这个 fallback 方案，我的判断是：**不要先试 TabView 再 fallback，直接用手写 tab bar**。省一轮调试。

### 3. [小] Sheet 尺寸策略

Research 建议固定尺寸。当前是 `400x560`，内容已经溢出过（之前的 bug）。加了 tab 后每个 tab 内容量变少，高度可以不变，但 **宽度建议从 400 增加到 480-500**，给 API key 输入框和模型列表更多空间。

### 4. [小] Tab 命名

"数据"这个 tab 名有点模糊。建议：
- Tab 1: 通用（保持）
- Tab 2: API（保持）
- Tab 3: 导入导出（更明确）

### 5. [缺失] 没有提到迁移策略

现有的 `@AppStorage` 变量散落在 SettingsView 里，重构后这些 binding 要传给子 tab view。Plan 里需要明确：
- 哪些 state 提升到 SettingsView（容器），哪些留在子 view
- `onAppear` 里的初始化逻辑（特别是 API key 加载和旧 key 迁移）放在哪一层

---

## 结论

Research 方向正确，可以进入 Plan 阶段。Plan 需要：
1. 把 API tab 跟 Phase 1.5 provider 架构对齐
2. 确定用手写 tab bar 而非系统 TabView
3. 明确 state 管理策略
4. 给每个 tab 画个简单的布局草图（文字版即可）

— Evaluator
