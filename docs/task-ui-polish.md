# 任务：UI 打磨 — 动画 + 功能面板

## 问题
天奕反馈：UI 思路对了但非常生硬。没有动画。+号按钮功能不对。

## 一、+ 号功能面板（最高优先级）

现在的 + 号点击后是"添加便签"。需要改成 Claude App 风格的功能面板：

### 交互
- 点击 + 号 → 底部弹出 sheet（半屏高度）
- 手指往上拉 → sheet 变大（接近全屏，顶部留安全区）
- 手指往下拉或点灰色区域 → sheet 关闭
- 使用 SwiftUI 的 `.sheet` + `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`

### 内容
面板里放这些（Phase 1 先做简单的）：
```
┌─────────────────────────────┐
│  ─── (拖拽指示条)            │
│                              │
│  📎 添加文件/照片             │
│  🤖 选择模型    [DeepSeek v] │
│  ⚙️ 设置                    │
│  📝 导入聊天记录             │
│                              │
└─────────────────────────────┘
```

每一行是一个按钮/导航链接。点击后执行对应功能或跳转到对应页面。

## 二、动画（全局）

### 原则
- **没有任何 UI 元素应该"突然出现"或"突然消失"**
- 所有状态变化都用 `withAnimation(.easeInOut(duration: 0.25))` 包裹
- 弹性效果用 `.spring(response: 0.35, dampingFraction: 0.8)`

### 具体位置

1. **侧边栏**
   - 左滑打开：`.transition(.move(edge: .leading))` + spring 动画
   - 背景遮罩：opacity 从 0 到 0.3 过渡

2. **消息气泡**
   - 新消息出现：`.transition(.opacity.combined(with: .move(edge: .bottom)))` 
   - duration: 0.2

3. **功能面板（+ 号）**
   - 系统 sheet 自带动画，不需要额外加
   - 但面板内的选项行可以用 staggered animation（依次出现，每行延迟 0.05s）

4. **空状态 → 有消息**
   - 问候语淡出 + 第一条消息淡入

5. **发送按钮状态切换**
   - 输入框空 ↔ 有文字时按钮图标切换用 `.transition(.scale.combined(with: .opacity))`

6. **设置页打开/关闭**
   - 使用 `.fullScreenCover` 或 `.sheet` 自带动画

### 通用规则
- 在所有 `@State` 变量变化的地方检查：是否需要 `withAnimation` 包裹
- 在所有 `if/else` 条件渲染的地方检查：是否需要 `.transition()`
- 不要过度动画——简单的淡入淡出比花哨的弹跳更好

## 三、删除 macOS target

在 project.yml 中删除 `MemoryPalace`（macOS target）。只保留 `MemoryPalaceIOS`。
删除后所有 `#if os(macOS)` 的代码块可以安全移除（不急，后面慢慢清理）。

## 约束
- 每次改一个区域，commit 一次。小步前进。
- 动画参数先用上面的默认值，后续天奕在真机上看效果再微调。
