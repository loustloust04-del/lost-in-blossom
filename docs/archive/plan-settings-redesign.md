# Plan: 设置页重构（v2，吸收 Evaluator 批注）

> Generator 制定，基于 Evaluator review-settings-redesign.md 的 5 条批注
> 参考 design-dna.json 确保视觉一致性

---

## 目标

SettingsView 从长滚动列表改为手写 tab bar + 3 tab 内容区。API tab 用卡片式布局，跟 Phase 1.5 provider 架构对齐。

## 关键设计决策（回应 Evaluator 批注）

1. **手写 tab bar，不用 TabView** — 直接 HStack 按钮 + @State selectedTab 切换。避免系统 TabView 在 sheet 里的样式冲突。选中态用 branchIndicator 色下划线。
2. **API tab 对齐 Phase 1.5** — 直接用 ProviderManager 和 APIProvider 数据，卡片显示连接状态 + key 输入 + 模型列表折叠。
3. **Sheet 加宽** — 从 400 增到 480，给 API key 和模型列表空间。
4. **Tab 命名** — 通用 / API / 导入导出。
5. **State 管理** — @AppStorage 和 @Environment 留在 SettingsView 容器层，通过参数传给子 tab view。onAppear 初始化逻辑放容器层。

## 文件变更

| 操作 | 文件 | 说明 |
|------|------|------|
| 重写 | Views/SettingsView.swift | 手写 tab bar + 3 个 tab 子视图 |

## DNA Token 参考

从 design-dna.json 提取，实现时直接用：

| Token | 值 | 用途 |
|-------|---|------|
| surface.sidebar | #F8F4EF | 设置页背景 |
| surface.card | #F3F2EB | provider 卡片背景 |
| primary | #8EBD9F | 选中 tab 下划线、按钮 |
| border_radius.medium | 8 | 卡片圆角 |
| border_radius.small | 6 | 按钮、输入框圆角 |
| spacing.sheet_padding | 20 | 内容 padding |
| text.primary | rgb(61,54,51) | 标题文字 |
| text.secondary | rgb(128,120,112) | 副标题 |
| text.muted | rgb(173,166,158) | 说明文字 |

---

## Checklist

### Step 1: 手写 Tab Bar + 外壳

- [x] 1.1 SettingsView body 改为：header + custom tab bar + conditional content
- [x] 1.2 Tab bar: HStack 三个按钮（通用/API/导入导出），选中态 branchIndicator 下划线
- [x] 1.3 @State selectedTab 控制内容切换
- [x] 1.4 Sheet 宽度从 400→480
- [x] 1.5 Build 验证

### Step 2: GeneralTab（通用）

- [x] 2.1 作为 SettingsView 的 computed property generalTab
- [x] 2.2 内容：楼层切换 + 气泡标签 + 字体设置
- [x] 2.3 共用容器层 state
- [x] 2.4 Build 验证

### Step 3: APITab（重点）

- [x] 3.1 作为 SettingsView 的 computed property apiTab
- [x] 3.2 ProviderCard：圆角 8pt，assistantBubble 背景色
- [x] 3.3 卡片内容：provider 名称 + 类型标签 + 状态点 + SecureField + 保存
- [x] 3.4 DisclosureGroup 折叠显示可用模型列表（模型名 + API ID）
- [x] 3.5 使用 ProviderManager 数据
- [x] 3.6 Build 验证

### Step 4: DataTab（导入导出）

- [x] 4.1 作为 SettingsView 的 computed property dataTab
- [x] 4.2 内容：导出设置 + 批量导出 + ImportHistoryView
- [x] 4.3 共用容器层 state
- [x] 4.4 Build 验证

### Step 5: 清理

- [x] 5.1 旧滚动式代码已删除（完全重写）
- [x] 5.2 辅助视图保留（ExportModeRow/FontOptionRow/SettingsTextField）
- [x] 5.3 新增 ProviderCard 组件
- [x] 5.4 Build 通过
- [ ] 5.5 Commit + push

---

## 布局草图

```
┌──────────────────────────────────────┐
│  ← 返回            设置              │  header
├──────────────────────────────────────┤
│   通用    API    导入导出             │  tab bar (手写 HStack)
│   ───                                │  branchIndicator 下划线
├──────────────────────────────────────┤
│                                      │
│  [通用 tab]                          │
│  ┌ 楼层 ─────────────────────┐      │
│  │ 🌸 幽灵百合号        ▾    │      │
│  └───────────────────────────┘      │
│                                      │
│  气泡标签                            │
│  我的名字  [你        ]              │
│  AI 的名字 [小雾      ]    [确认]    │
│                                      │
│  字体                                │
│  ○ 系统默认                          │
│  ● 苹方    记忆宫殿                  │
│  ...                                 │
│                                      │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│  [API tab]                           │
│                                      │
│  ┌─ Anthropic ──────────────── ● ─┐ │  绿点=有key
│  │  [sk-ant-...                 ]  │ │
│  │                        [保存]   │ │
│  │  ▸ 可用模型 (8)                 │ │  折叠
│  └────────────────────────────────┘ │
│                                      │
│  ┌─ OpenAI ───────────────────  ○ ─┐│  灰点=无key
│  │  [API Key                    ]  ││
│  │                        [保存]   ││
│  └────────────────────────────────┘ │
│  ...                                 │
└──────────────────────────────────────┘
```

---

## 不做的事

- ❌ 模型参数（temperature/max_tokens）— 后续单独加，不塞进这次
- ❌ 连接测试按钮 — 后续
- ❌ 系统 TabView — Evaluator 已否决
- ❌ lite/advanced 切换 — tab 本身就是渐进披露
