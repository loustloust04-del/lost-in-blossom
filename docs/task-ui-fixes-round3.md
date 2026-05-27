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
