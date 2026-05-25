# Plan: 设置页 iOS 端重构

> 2026-04-14
> 依赖：`/Users/susu/Downloads/设置页重构spec.md`

## 方案

保持 sheet 呈现，sheet 内部改为全屏列表 + push 子页面。Mac 端不动。

## Checklist

### Phase 1：导航结构改造

#### 1. Sheet 改全屏 + 列表入口

文件：`SettingsView.swift`

- [ ] **1a** `iOSSettingsBody` 改为：NavigationStack > List，6 个 section 作为 NavigationLink
- [ ] **1b** 每个 NavigationLink push 到独立子页面（generalTab / appearanceTab / personaTab / apiTab / memoryTab / dataTab）
- [ ] **1c** 去掉横向 tab 选择器（capsule buttons ScrollView）
- [ ] **1d** 列表每行：图标 + 标题 + 右箭头，风格参考 iOS 系统设置
- [ ] **1e** sheet 加 `.presentationDetents([.large])` 全屏展开

文件：`ContentView.swift`

- [ ] **1f** `.sheet` 呈现 SettingsView 时加 `.presentationDetents([.large])` + `.presentationDragIndicator(.hidden)`

#### 2. 各子页面包装

文件：`SettingsView.swift`

- [ ] **2a** 每个 tab 内容包装为独立的子页面 view（加 `.navigationTitle`）
- [ ] **2b** 子页面用 ScrollView 包裹内容（已有的 generalTab 等直接复用）
- [ ] **2c** macOS 路径完全不动（`#if os(iOS)` 隔离）

### Phase 2：Prompt 子页面结构

#### 3. 预设选择器样式

- [ ] **3a** 预设 Picker 去掉系统蓝色，改为自定义样式（暖奶白 + branchIndicator 绿）
- [ ] **3b** 复制/分享按钮保留

#### 4. 插槽点击改 push

- [ ] **4a** 插槽折叠态改为卡片样式（圆角 + 微弱背景色差 + 内 padding）
- [ ] **4b** 折叠态一行：开关 toggle + 名称 + 角色 badge
- [ ] **4c** 点击卡片 → NavigationLink push 到全屏插槽编辑页（不再原地展开）
- [ ] **4d** 插槽编辑页：名称 + 角色选择器 + 深度输入 + 大文本编辑区

#### 5. 采样参数可折叠 + 单列紧凑

- [ ] **5a** 默认收起，section header "采样参数 ▶" 点击展开
- [ ] **5b** 展开后单列布局：`参数名 .............. 数值`
- [ ] **5c** 数值可点击弹出输入框精确输入（自建控件）
- [ ] **5d** 不再使用原生 Slider

### Phase 3：验证

- [ ] **6a** iOS build 通过
- [ ] **6b** macOS build 通过（不受影响）
- [ ] **6c** 真机测试：
  1. 齿轮 → sheet 全屏 → 设置列表
  2. 点每个入口 → push 子页面 → 侧滑返回
  3. Prompt 页：预设选择 + 五 tab + 插槽卡片 → push 编辑
  4. 采样参数折叠/展开
- [ ] **6d** git commit + push

## 实施顺序

先做 Phase 1（导航结构），这是最大的改动。Phase 2（Prompt 细节）在 Phase 1 稳定后做。

## 文件改动

| 文件 | 改动 |
|------|------|
| `SettingsView.swift` | iOS body 重构为列表 + push 子页面 |
| `ContentView.swift` | sheet presentationDetents 调整 |
