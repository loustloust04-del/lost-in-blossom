# Research: iOS 贴纸键盘面板（学 Telegram）

## 需求

参考 Telegram：输入框旁边有贴纸按钮，点一下**键盘区域变成贴纸面板**，再点一下切回键盘。

### 交互流程
1. 普通模式：输入框 + 左侧贴纸按钮 🎨
2. 点贴纸按钮 → 键盘收起 → 输入框消失 → 贴纸面板+工具栏弹上来（占据键盘区域高度）
3. 在贴纸面板里：浏览 Gallery + 点击放置 + 新建便签 + 画画
4. 点贴纸按钮（或输入框区域）→ 贴纸面板收回 → 输入框恢复

### 关键：不是叠加，是替换
- 贴纸模式下输入框**消失**（不是被盖住）
- 贴纸面板高度 ≈ 键盘高度（~300pt）
- 工具栏（选择/便签/画画/完成）在面板顶部

## 现有代码分析

### iOS 输入框位置
`CardFlowView.swift` — iOS 输入框通过 `.safeAreaInset(edge: .bottom)` 放在底部：
```swift
// iOS 用 safeAreaInset，不在 VStack 底部
.safeAreaInset(edge: .bottom) {
    ChatInputBar(...)
}
```

合并后的最新代码（5af9506）里 iOS 输入框用了 Liquid Glass 悬浮浮板样式。

### macOS vs iOS 区别
- **macOS**：编辑模式下 ChatInputBar 替换为 StickerToolbar（已实现）
- **iOS**：应该是贴纸按钮切换面板，不替换输入框

## 实现方案

### 方案：iOS 专用 StickerKeyboardPanel

1. `CardFlowView` 的 iOS `safeAreaInset` 里加条件判断：
   ```swift
   .safeAreaInset(edge: .bottom) {
       if showStickerPanel {
           StickerKeyboardPanel(...)  // 贴纸面板
       } else {
           ChatInputBar(...)          // 普通输入框
       }
   }
   ```

2. `StickerKeyboardPanel` 包含：
   - 顶部工具栏（选择/贴纸库按钮/便签/画画/完成）
   - 下方 Gallery 网格（缩小版，直接内嵌，不是右栏）
   - 点击贴纸 → 放到画布
   - 高度约 300pt

3. ChatInputBar 左侧加贴纸按钮（🎨图标）：
   - 点击 toggle `showStickerPanel`
   - 同时收起键盘（resignFirstResponder）

### 数据流
- `@State showStickerPanel: Bool` 在 CardFlowView
- 贴纸按钮 toggle 这个状态
- StickerKeyboardPanel 内嵌 StickerLibraryView 的缩小版（或复用 Gallery 网格）

### 注意
- 面板弹出时要收起键盘
- 面板收回时如果用户点输入框，键盘弹出
- 动画用 `.transition(.move(edge: .bottom))` 和输入框一致
