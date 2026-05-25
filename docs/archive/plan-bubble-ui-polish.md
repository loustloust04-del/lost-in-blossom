# Plan: 对话气泡 UI 打磨

> 2026-04-13

## Checklist

### 1. 设置页新增"外观"tab

文件：`SettingsView.swift`

- [ ] **1a** 在设置页 tab 列表中加入"外观"tab（位置：通用和Prompt之间）
- [ ] **1b** 新建 AppearanceSettingsView 内容：
  - 字体选择（从通用 tab 移过来）
  - 聊天字号滑块（从通用 tab 移过来）
  - "全部展开全文"开关（新增 `@AppStorage("expandAllMessages")` bool，默认 false）
- [ ] **1c** 通用 tab 中移除字体/字号相关 UI，只留楼层和气泡标签

### 2. "全部展开全文"逻辑

文件：`CardFlowView.swift` — BubbleView

- [ ] **2a** 在 BubbleView 中读取 `@AppStorage("expandAllMessages")`
- [ ] **2b** 修改截断逻辑：当 `expandAllMessages == true` 时，`shouldTruncate` 始终为 false
- [ ] **2c** 当 `expandAllMessages == true` 时，不显示"展开全文"/"收起"按钮

### 3. 编辑按钮移到 HoverButtons

文件：`CardFlowView.swift` — BubbleView + HoverButtons

- [ ] **3a** HoverButtons 增加 `onEdit` 回调参数（optional，只有用户消息传入）
- [ ] **3b** 在 HoverButtons 中，复制按钮前面加编辑按钮（pencil 图标），只在 onEdit != nil 时显示
- [ ] **3c** 从 BubbleView body 中移除原来的独立编辑按钮（lines 645-659 附近）
- [ ] **3d** 更新 BubbleView 中 HoverButtons 的调用，传入 onEdit

### 4. 按钮稍微大一点

文件：`CardFlowView.swift` — HoverButtons

- [ ] **4a** 图标 `.font(.system(size: 11))` → `.font(.system(size: 13))`
- [ ] **4b** 确认 iOS 触摸区域足够（可加 `.frame(width: 32, height: 32)` 保证触摸面积）

### 5. contextMenu 加编辑

文件：`CardFlowView.swift` — BubbleView

- [ ] **5a** 在 `.contextMenu` 中，收藏按钮上方加入"编辑"选项（pencil 图标），只在用户消息时显示
- [ ] **5b** 点击后触发 `editText = node.content; isEditing = true`（和原来编辑按钮逻辑一致）

### 6. 验证

- [ ] **6a** iOS build 通过
- [ ] **6b** macOS build 通过
- [ ] **6c** 确认：
  1. 设置页有"外观"tab，字体/字号/展开全文开关在里面
  2. 通用 tab 只有楼层和气泡标签
  3. 打开"全部展开全文"后所有长消息直接展开
  4. 编辑按钮在 HoverButtons 一排（用户消息才有）
  5. 长按气泡菜单里有编辑选项（用户消息才有）
  6. 按钮比之前大一点
- [ ] **6d** git commit + push

## 文件改动

| 文件 | 改动 |
|------|------|
| `SettingsView.swift` | 新增"外观"tab，字体/字号移入，加展开全文开关 |
| `CardFlowView.swift` | BubbleView 展开逻辑 + 编辑按钮移位 + HoverButtons 改大 + contextMenu 加编辑 |
