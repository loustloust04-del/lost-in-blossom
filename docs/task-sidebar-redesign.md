# 任务：侧边栏重构 — Claude App 风格

天奕截图参照 Claude iOS App。按优先级排序。

## 1. 侧边栏滑动交互（最高优先级）

现在的侧边栏是粟粟原来的样式。改成 Claude App 风格：

### 交互
- 左滑或点击左上角按钮 → 聊天界面整体往右平移
- 侧边栏从左边滑出，占屏幕约 **五分之四** 宽度
- 聊天界面被推到右侧，露出约五分之一，背景加半透明黑色遮罩（opacity 0.3）
- 点击遮罩区域或右滑 → 侧边栏关闭，聊天界面滑回原位
- 动画：`.spring(response: 0.35, dampingFraction: 0.85)`

### 实现
使用 GeometryReader + offset 方式而非 NavigationSplitView。
侧边栏和聊天界面在同一层级，通过 offset 控制位置。

## 2. New Chat 按钮

- 从右上角的绿色小方块 → 移到侧边栏底部
- 样式：黑色圆角矩形，白色文字 "+ New chat"
- 固定在侧边栏底部（不随列表滚动）

## 3. 侧边栏结构

顶部区域（固定）：
```
┌──────────────────────────┐
│  🔍 Search               │
├──────────────────────────┤
│  💬 Chats                │  ← 当前页（对话列表）
│  📁 Projects             │  ← 导航到项目列表页
├──────────────────────────┤
```

中间区域（滚动）：
- Chats 模式下：所有对话列表（跟现在一样）
- Projects 模式下：项目列表

底部区域（固定）：
```
├──────────────────────────┤
│  ⚙️ Settings             │
│  [    + New chat     ]   │  ← 黑色圆角矩形
└──────────────────────────┘
```

## 4. Projects 系统（Phase 2，先做数据模型和空页面）

### 数据模型
```swift
@Model
class Project {
    var name: String
    var instructions: String  // 项目级提示词
    var createdAt: Date
    var conversations: [Conversation]  // 关联的对话
}
```

### 页面
- **项目列表页：** 显示所有 Project，底部 "+ New project" 按钮
- **项目详情页：** 顶部 "Add files" + "Instructions" 按钮，下面是该项目的对话列表
- **Instructions 编辑：** bottom sheet，文本编辑器
- **新建项目：** bottom sheet，name + description 两个输入框

### 导入对话归类
- 导入的 ChatGPT 记录 → 自动创建 "ChatGPT 历史" Project
- 导入的 Claude 记录 → 自动创建 "Claude 历史" Project
- Lost in Blossom 原生对话 → 默认在 Chats 根目录

---

Phase 1（侧边栏交互 + New Chat + 基本结构）先做。
Phase 2（Projects 完整功能）后面做。
每项改完 commit 一次。

---

## 5. 输入栏改造（Claude App 风格）

现在的输入栏是简单的 TextField + 发送按钮。改成 Claude App 的两层结构：

### 布局
```
┌─────────────────────────────────────────┐
│  Reply to Caelum                        │  ← placeholder
│                                         │
├────┬──────────────────┬─────────────────┤
│ +  │  DeepSeek R1  ▾  │            (⬆)  │  ← 工具栏
└────┴──────────────────┴─────────────────┘
```

### 细节
- 外层：圆角矩形卡片，浅灰色边框，背景色跟聊天背景一致
- 上半：多行 TextEditor，placeholder "Reply to Caelum"（灰色）
- 下半工具栏：
  - 左：+ 号按钮（触发 AddToChatSheet）
  - 中：模型选择标签（显示当前模型名，点击弹出模型选择器）
  - 右：发送按钮（⬆ 箭头，圆形，黑色背景白色箭头）
    - 输入框为空时：发送按钮隐藏或灰色不可点
    - 输入框有文字时：发送按钮高亮可点
- **不要** 麦克风按钮（语音功能以后做）
- 右侧麦克风位置留空

### 动画
- 发送按钮出现/消失：`.transition(.scale.combined(with: .opacity))`
- 输入框高度自适应文字量（最大高度限制 5 行）
