# 任务：UI 修复第三轮

天奕真机测试截图对比。设计参考：Claude iOS App（截图在 docs/ 目录）。

## 1. 输入框缩小（最高优先级）

现在输入框占比太大，看起来笨重。改成 Claude App 风格：

- **默认状态：** 单行高度。placeholder "Reply to Caelum" 一行显示。
- **输入时：** 自动展开，最多 5 行高度，超过可滚动。
- **无输入时：** 收回单行。
- 用 TextField 而非 TextEditor 作为默认（或 TextEditor 设 `.frame(minHeight: 36, maxHeight: 120)`）
- 工具栏（+号、模型标签、发送按钮）紧贴输入框底部，间距紧凑。

## 2. 发送按钮 / 语音按钮切换

- **输入框为空时：** 右侧显示黑色圆形语音按钮（SF Symbol: `waveform.circle.fill`），占位用，点击暂不做功能
- **输入框有文字时：** 右侧切换为发送按钮（⬆ 箭头）
- 切换动画：`.transition(.scale.combined(with: .opacity))`

## 3. 侧边栏动画修复（关键）

当前的动画逻辑不对。需要完全重做，仿照 Claude iOS App：

### 打开动画
1. 聊天界面整体 **缩小** `scaleEffect(0.92)` 
2. 聊天界面 **圆角变大** `.clipShape(RoundedRectangle(cornerRadius: 30))`
3. 聊天界面 **右移** `offset(x: screenWidth * 0.78)`
4. 侧边栏从左边滑入，宽度约屏幕 80%
5. 聊天界面后方加暗色遮罩 `Color.black.opacity(0.3)`
6. 动画：`.spring(response: 0.4, dampingFraction: 0.85)`

### 关闭动画
- 反向：scale 回 1，圆角回 0，offset 回 0，遮罩消失

### 手势
- 从左边缘右滑拖动 → 跟踪手指位置 → 松手时根据位置/速度决定打开或关闭
- 点击暗色遮罩 → 关闭
- 在侧边栏打开状态下左滑 → 关闭

### 关键点
聊天界面的 **缩小 + 圆角** 是核心视觉效果——产生景深感：侧边栏在前景，聊天在背景被推远。没有这个缩小效果就会看起来怪。

## 4. 搜索按钮位置修复

搜索按钮目前跑到了状态栏底下，被系统 UI 遮挡，按不到。
确保搜索按钮在安全区域内（`safeAreaInset` 或 `.padding(.top, 安全区高度)`）。

## 5. 右滑控制台

不需要改。保持现状。

---
每项改完 commit 一次。侧边栏动画是最复杂的，单独一个 commit。

## 3a. 侧边栏动画补充说明（关键bug）

### 当前bug
拖动手势时侧边栏不在场（空白），松手后侧边栏突然跳出来。
原因：用 boolean state 控制显示/隐藏，手势只触发 state 切换。

### 正确实现
侧边栏必须 **实时跟随手指拖动**，不能用 boolean 切换。

```swift
@State private var sidebarOffset: CGFloat = -screenWidth * 0.8  // 初始在屏幕外
@GestureState private var dragOffset: CGFloat = 0

// 侧边栏 offset 绑定到拖动距离
.offset(x: sidebarOffset + dragOffset)

// 拖动手势
.gesture(
    DragGesture()
        .updating($dragOffset) { value, state, _ in
            // 实时跟踪手指——手指拉多少侧边栏就移多少
            state = max(0, value.translation.width)
        }
        .onEnded { value in
            // 松手时判断：拉过一半或速度够快 → 打开，否则关闭
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                if value.translation.width > screenWidth * 0.3 
                   || value.velocity.width > 500 {
                    sidebarOffset = 0  // 打开
                } else {
                    sidebarOffset = -screenWidth * 0.8  // 关闭
                }
            }
        }
)
```

### 核心原则
- 拖动过程中：侧边栏位置 = 初始位置 + 手指偏移量（实时跟随，无动画）
- 松手后：spring 动画弹到最终位置（打开或关闭）
- 聊天界面的 scale/offset/圆角也同步跟手势绑定

**绝对不能** 用 `if isOpen { SidebarView() }` 这种 boolean 切换方式。侧边栏始终存在，只是通过 offset 控制位置。
