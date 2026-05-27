# 任务：侧边栏最终版 — 完整重构

参照 Claude iOS App 截图（天奕提供）。这是侧边栏的最终设计，一次性做完。

## 侧边栏结构（从上到下）

### 1. 顶部栏
```
┌──────────────────────────────┐
│  Lost in Blossom        (○)  │
└──────────────────────────────┘
```
- 左侧：App 名 "Lost in Blossom"，字号 20px，weight 700
- 右侧：圆形灰色按钮（直径 32px，背景 #E8E0D4）
  - 点击 → 弹出设置页（粟粟已有的设置页，用 `.sheet` 或 `NavigationLink`）
  - 以后可以放用户头像

### 2. 搜索栏
```
│  🔍 搜索                      │
```
- 粟粟已有的搜索组件，保持不变
- 确保在安全区域内（不被状态栏遮挡）

### 3. 导航入口
```
│  💬 Chats                  ›  │
│  📁 Projects               ›  │
```
- 两行。每行左侧图标+文字，右侧 › 箭头
- 图标用 SF Symbols：`bubble.left.and.bubble.right` / `folder`
- 颜色：图标 #A89E8E，文字 #3A332B
- 点击 Chats → NavigationLink 到聊天列表页（二级）
- 点击 Projects → NavigationLink 到项目列表页（二级）
- Chats 二级页面 = 粟粟现有的对话列表（全部对话）
- Projects 二级页面 = 新建（Phase 2，先做空页面 "Coming Soon"）

### 4. 对话列表（可滑动）
```
│  你好，我现在在测试…    May 28  │
│  测试测试！             May 27  │
│  新对话                 May 27  │
│           All Chats ›          │
```
- 显示 App 上新建的所有对话
- 最多显示 **8 条**，超过时底部出现 "All Chats ›"
- "All Chats ›" 点击 → 导航到跟 💬 Chats 一样的完整列表页
- 每行：左侧对话标题（截断），右侧日期+消息数
- 点击某条对话 → 关闭侧边栏 + 进入该对话

### 5. 底部
```
│    [  ＋ New chat  ]           │
```
- **不要全宽按钮**
- 居中的胶囊按钮，宽度约侧边栏的 60%
- 黑色背景，白色文字 "+ New chat"
- 圆角 24px
- 上下留 padding
- **删掉** 原来的 ⚙️ 设置按钮（设置入口已移到顶部圆形按钮）

## 侧边栏动画（重申）

必须跟手势实时同步。不许雷霆大跳。

打开：
- 聊天界面 scaleEffect(0.92) + cornerRadius(30) + offset(screenWidth * 0.78)
- 侧边栏从左侧滑入
- 背景暗色遮罩 opacity 0.3
- spring(response: 0.4, dampingFraction: 0.85)

手势：
- DragGesture 实时跟踪（@GestureState）
- 侧边栏 offset 绑定到拖动距离
- 松手后 spring 弹到最终位置

## 删除项
- 底部 ⚙️ 设置按钮 → 删
- 右上角原来的绿色新建按钮 → 删（已移到底部 New chat）

---

这是侧边栏的最终版。做完这个不再改侧边栏结构了。
每个区域单独 commit。
