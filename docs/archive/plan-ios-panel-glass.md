# Plan: iOS 贴纸面板 Liquid Glass 材质修复

## 目标

工具栏和面板从"灰蒙蒙一坨" → 两块独立的 Liquid Glass 卡片，和输入框同款质感。

## 改动文件

只改 `StickerKeyboardPanel.swift`，3 处。

## Checklist

- [x] **1. 工具栏材质**（line 44）
  - 删 `.background(Capsule().fill(.ultraThinMaterial))`
  - 改 `.glassEffect(.regular.tint(Color.black.opacity(0.01)).interactive(), in: .capsule)`

- [x] **2. 面板卡片材质**（line 91-94）
  - 删 `.background(UnevenRoundedRectangle(...).fill(.ultraThinMaterial))`
  - 改 `.glassEffect(.regular.tint(Color.black.opacity(0.01)).interactive(), in: .rect(cornerRadii: .init(topLeading: 16, topTrailing: 16)))`

- [x] **3. 间距分离**（line 29）
  - `VStack(spacing: 8)` → `VStack(spacing: 12)`
  - 让工具栏胶囊和面板卡片视觉上明确分开

- [x] **4. Build 验证**
  - macOS BUILD SUCCEEDED（iOS simulator 未安装，StickerKeyboardPanel 在 #if os(iOS) 内，API 跨平台兼容）

## 不改的

- 布局结构不动（VStack → 工具栏 → 面板）
- 拖拽条、贴纸网格、sheet 逻辑都不动
- macOS 侧不受影响（整个文件 `#if os(iOS)`）
