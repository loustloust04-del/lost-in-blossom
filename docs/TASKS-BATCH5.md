# 第五批任务 — 文件导入器 + 右滑页

> 日期：2026-06-09
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟原版在 VPS `/root/projects/SusuPalace/`

---

## Task 1: 文件导入器恢复（UIDocumentPicker）

**背景**: App 现在有 Apple Development 签名了，文件访问权限解锁。之前为了绕过无签名限制，文件导入改成了复制粘贴。现在改回正路。

**要做的事**:
1. 找到当前的文件导入绕路代码（搜索 `paste`、`clipboard`、`UIPasteboard`、`复制粘贴`、`导入` 相关）
2. 替换为 UIDocumentPickerViewController（或 SwiftUI 的 `.fileImporter`）
3. 支持导入的文件类型：`.json`（ChatGPT/Claude 导出）、`.txt`、`.md`、`.png`/`.jpg`（图片）
4. 参考粟粟的实现：`/root/projects/SusuPalace/MemoryPalace/Services/ClaudeImporter.swift` 和 `ChatGPTImporter.swift`

**查找路径**:
- `MemoryPalace/Views/SidebarView.swift` — 可能有导入按钮
- `MemoryPalace/Services/ClaudeImporter.swift` — 导入逻辑
- 搜索：`fileImporter`、`documentPicker`、`UIPasteboard`、`importFrom`

**commit**: `feat: restore UIDocumentPicker file import (signed build unlocks file access)`

---

## Task 2: 右滑页（右栏插件系统）搬回来

**背景**: 我们之前把右栏功能移到了软件之外（设置页等）。粟粟的右栏插件系统非常完善——8 个可拖拽排序的工具面板，注册制。现在搬回来。

**要搬的文件（从粟粟 `/root/projects/SusuPalace/MemoryPalace/` 复制）**:

模型层：
- `Models/RightPanelPlugin.swift` — 插件注册制（RightPanelTool + RightPanelToolManager）

视图层（按优先级搬，先搬框架再搬面板）：
- `Views/MemoryPanelView.swift` — 右栏容器 + 工具路由
- `Views/ToolBarView.swift` — 工具栏（橡皮绳动画）
- `Views/RightPanelSettingsView.swift` — 右栏设置页（拖拽排序、启用/禁用）
- `Views/CalendarPanelView.swift` — 日历面板
- `Views/WorldBookPanelView.swift` — 世界书面板
- `Views/CardLibraryPanelView.swift` — 卡库面板

**步骤**:
1. 先复制上述文件到我们的项目（注意不要覆盖我们已有的同名文件，如果有的话先 diff）
2. 在 ContentView.swift 里恢复右栏显示（NavigationSplitView 的 detail 或 trailing sidebar）
3. 在 SettingsView.swift 里加右栏设置入口
4. 确认 Theme 颜色变量跟我们的匹配（粟粟用的 Theme.sidebarBg 等我们可能也有）

**不搬的（后续单独做）**:
- CCTerminalPanelView — 等 CC Bridge 重写后再加
- FileLibraryPanelView — 等写作系统设计后再加

**commit**: 每搬一个文件 commit 一次，格式 `feat(right-panel): add XXX`

---

## 规则

- 每个 Task/文件完成后单独 commit + push
- 从 VPS 复制文件时注意路径：`/root/projects/SusuPalace/MemoryPalace/`
- 如果遇到编译错误（缺少依赖、Theme 变量不存在等），先尝试修复，卡住 30 分钟跳过并标注
- 搬文件前先 diff 确认我们没有同名文件，有的话先看差异再决定覆盖还是合并
