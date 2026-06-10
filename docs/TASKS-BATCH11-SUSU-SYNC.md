# 第十一批任务 — 粟粟代码同步（8个文件）

> 日期：2026-06-10
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟 VPS `/root/projects/SusuPalace/MemoryPalace/`
> 原则：照搬，不自己发明

---

## 搬运清单（按优先级）

### Task 1: PushNotifications.swift（推送通知注册）
**源**: `/root/projects/SusuPalace/MemoryPalace/Services/PushNotifications.swift`
**目标**: `MemoryPalace/Services/PushNotifications.swift`
- 注册远程推送权限
- 获取 deviceToken
- 发给 CC Bridge hub（通过 WebSocket）
- 在 MemoryPalaceApp.swift 里注册 delegate
**commit**: `feat: add PushNotifications service from susu`

### Task 2: CCSettingsView.swift（CC专属设置页）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/CCSettingsView.swift`
**目标**: `MemoryPalace/Views/CCSettingsView.swift`
- nudge 参数配置（CC 主动消息的频率）
- 系统提示词编辑
- 休眠模式开关
- 推送名配置
- 在 SettingsView.swift 里加入口
**commit**: `feat: add CCSettingsView from susu`

### Task 3: CCSessionPickerSheet.swift（CC会话选择器）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/CCSessionPickerSheet.swift`
**目标**: `MemoryPalace/Views/CCSessionPickerSheet.swift`
- 选择 CC tmux session
- 绑定会话到当前聊天
**commit**: `feat: add CCSessionPickerSheet from susu`

### Task 4: FileLibraryTools.swift（文件库MCP工具）
**源**: `/root/projects/SusuPalace/MemoryPalace/Services/FileLibraryTools.swift`
**目标**: `MemoryPalace/Services/FileLibraryTools.swift`
- CC 可以通过 MCP 工具读写文件库
- 对接 FileLibraryStore
**commit**: `feat: add FileLibraryTools (CC MCP file access) from susu`

### Task 5: AttachmentPreviewSheet.swift（附件预览）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/AttachmentPreviewSheet.swift`
**目标**: `MemoryPalace/Views/AttachmentPreviewSheet.swift`
- 点击图片/文件放大查看
- 对接 BubbleAttachmentStrip
**commit**: `feat: add AttachmentPreviewSheet from susu`

### Task 6: CCSlashCommandSuggestions.swift（斜杠命令）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/CCSlashCommandSuggestions.swift`
**目标**: `MemoryPalace/Views/CCSlashCommandSuggestions.swift`
- /help /model /session 等命令建议
- 输入栏集成
**commit**: `feat: add CCSlashCommandSuggestions from susu`

### Task 7: TerminalSettingsTab.swift（终端设置页）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/TerminalSettingsTab.swift`
**目标**: `MemoryPalace/Views/TerminalSettingsTab.swift`
- 终端字体/颜色配置
- 在 SettingsView.swift 里加入口
**commit**: `feat: add TerminalSettingsTab from susu`

### Task 8: FileLibrarySettingsTab.swift（文件库设置页）
**源**: `/root/projects/SusuPalace/MemoryPalace/Views/FileLibrarySettingsTab.swift`
**目标**: `MemoryPalace/Views/FileLibrarySettingsTab.swift`
- 文件库路径配置
- 在 SettingsView.swift 里加入口
**commit**: `feat: add FileLibrarySettingsTab from susu`

---

## 规则

- 每个文件用 exec_vps 从粟粟目录读取，在本地创建
- 照搬，不改逻辑。只改必须改的（如硬编码路径、粟粟专用变量名）
- 如果搬过来的文件依赖我们没有的类/方法，先检查是否已有类似的，没有就补上
- 每个 Task 单独 commit + push
- 搬完后检查 SettingsView.swift 的入口是否都加了
