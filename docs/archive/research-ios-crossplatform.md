# Research: iOS 跨平台 — 一套代码同时出 macOS + iOS

> CC 深读全部 27 个 Swift 文件 + xcodegen 配置 + 依赖分析，2026-03-27

---

## 1. 现状：哪些代码能直接用

逐文件分析结果：

### 100% 可移植（零改动）— 20 个文件

**Models（全部）：**
- Conversation.swift, Folder.swift, APIProvider.swift, Memory.swift, MemoryNote.swift, ImportRecord.swift, Preset.swift

**Services（全部）：**
- ChatService.swift, PromptAssembler.swift, MemoryService.swift, ConversationImporter.swift, ClaudeImporter.swift, MarkdownExporter.swift

**Utils（大部分）：**
- Theme.swift, MarkdownTheme.swift, ContentCleaner.swift

**Views（大部分）：**
- CardFlowView.swift, CalendarPanelView.swift, ExportOptionsSheet.swift, ImportHistoryView.swift, ImportView.swift

### 需要 `#if os()` 条件编译 — 3 个文件

| 文件 | macOS 专属代码 | iOS 替代方案 |
|------|---------------|-------------|
| **FontManager.swift** | CoreText 字体注册 | `#if os(macOS)` 包裹，iOS 只用系统字体 |
| **SettingsView.swift** | `NSOpenPanel()` 一处 (L1242) | 改用 `.fileImporter()`（文件里其他地方已在用） |
| **SidebarView.swift** | 纯 SwiftUI 但布局需要适配 | iPhone 上 NavigationSplitView 自动变 push |

### macOS 专属（需要拆分或重写）— 2 个文件

| 文件 | macOS 专属代码 | 说明 |
|------|---------------|------|
| **MemoryPalaceApp.swift** | `.windowStyle()`, `.windowToolbarStyle()`, `WindowConfigurator`(NSViewRepresentable + NSWindow) | 用 `#if os(macOS)` 包裹窗口配置，iOS 不需要这些 |
| **ContentView.swift** | `WindowFullscreenObserver`(NSViewRepresentable + NSWindow notifications) | iOS 没有全屏概念，用 `@Environment(\.horizontalSizeClass)` 替代 |

---

## 2. 依赖兼容性

| 依赖 | iOS 支持 | 最低版本 |
|------|---------|---------|
| SwiftUI | ✅ | iOS 13+ |
| SwiftData | ✅ | iOS 17+ |
| MarkdownUI 2.4.1 | ✅ | iOS 15+（完整功能 iOS 16+） |
| NetworkImage 6.0.1 | ✅ | iOS 15+ |
| Foundation/NSObject | ✅ | 全版本 |

**零额外依赖问题。** 建议 iOS 最低部署目标：**iOS 17.0**（SwiftData 要求）。

---

## 3. macOS 专属 API 清单

总共只有 **5 处** macOS 专属代码：

| # | 文件 | API | iOS 替代 |
|---|------|-----|---------|
| 1 | MemoryPalaceApp.swift:393-394 | `.windowStyle()` `.windowToolbarStyle()` | 删掉（iOS 不需要） |
| 2 | MemoryPalaceApp.swift:748-779 | `WindowConfigurator` (NSWindow) | 删掉（iOS 无窗口概念） |
| 3 | ContentView.swift:265-351 | `WindowFullscreenObserver` (NSWindow) | `@Environment(\.horizontalSizeClass)` |
| 4 | SettingsView.swift:1242 | `NSOpenPanel()` | `.fileImporter()` |
| 5 | FontManager.swift:24-98 | `CTFontManager` (CoreText) | 系统字体 or 空实现 |

---

## 4. 架构方案

### 方案 A：条件编译（推荐，最简单）

不拆文件夹，在现有代码里加 `#if os(macOS)` / `#if os(iOS)`：

```yaml
# project.yml 改动
targets:
  MemoryPalace:
    type: application
    platform: macOS
    deploymentTarget:
      macOS: "14.0"
    sources:
      - path: MemoryPalace
    # ... 现有配置

  MemoryPalaceIOS:
    type: application
    platform: iOS
    deploymentTarget:
      iOS: "17.0"
    sources:
      - path: MemoryPalace        # 共享同一套源码
    dependencies:
      - package: MarkdownUI
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.susu.MemoryPalace.ios
        PRODUCT_NAME: 记忆宫殿
        INFOPLIST_VALUES:
          UILaunchScreen: {}
```

两个 target 共享同一个 `MemoryPalace/` 源码目录，用条件编译区分平台。

改动量：5 处 `#if os(macOS)` + 1 个 iOS App 入口适配 ≈ **2-3 小时核心改动**。

### 方案 B：拆共享框架

把 Models/Services/Utils 拆成独立 framework，macOS 和 iOS 各自的 Views 层分开。

优点：更干净的分离。
缺点：xcodegen 配置复杂，维护两套 Views。

**推荐方案 A。** 理由：
1. 95% 的 Views 已经是纯 SwiftUI，不需要拆
2. 只有 5 处 macOS 专属代码需要条件编译
3. 改一处两边都生效（共享源码）
4. 以后如果 Views 差异大了再拆不迟

---

## 5. iOS 需要适配的 UI 差异

| 组件 | macOS 现状 | iOS 需要 |
|------|-----------|---------|
| 导航 | NavigationSplitView（三栏） | iPhone 自动变 push 导航，iPad 保持分栏 |
| 设置页 | 弹窗式面板 | iOS 风格 Form + NavigationLink |
| hover 按钮 | `.onHover` + opacity | 改为长按菜单 or 常显 |
| 右键菜单 | `.contextMenu` | `.contextMenu` 在 iOS 也能用（长按触发） |
| 键盘快捷键 | `.keyboardShortcut` | 删掉（或改为 iPad 外接键盘支持） |
| 窗口尺寸 | `frame(minWidth: 800)` | 响应式布局 |
| 滚动条 | macOS 风格 | iOS 自动适配 |

大部分 SwiftUI 组件在 iOS 上自动适配，真正需要重写的只有：
- **设置页布局**（macOS 弹窗 → iOS Form）
- **hover 交互**（→ 长按）
- **窗口配置**（→ 删掉）

---

## 6. iCloud 同步（加分项）

SwiftData 原生支持 CloudKit 同步。如果启用：
- macOS 和 iOS 的对话数据自动同步
- 需要 Apple Developer 账号 + CloudKit container
- `ModelConfiguration` 加 `cloudKitDatabase: .automatic`

这个可以后做，不阻塞 iOS 版本上线。

---

## 7. 工作量估算

| 步骤 | 工时 | 说明 |
|------|------|------|
| project.yml 加 iOS target | 30 min | xcodegen 配置 |
| 5 处条件编译 | 1-2 hr | `#if os(macOS)` 包裹 |
| iOS App 入口适配 | 1 hr | 去掉窗口配置，调整 Scene |
| SettingsView iOS 适配 | 2-3 hr | Form 布局 + 去 NSOpenPanel |
| hover → 长按适配 | 1-2 hr | CardFlowView + SidebarView |
| 测试 + 修 bug | 3-5 hr | 模拟器 + 真机 |
| **总计** | **8-13 hr** | 核心功能可用 |

后续打磨（iPad 分屏、iPhone 专属布局、iCloud 同步）另算。

---

## 8. 结论

**非常适合做跨平台。** 27 个文件中 20 个零改动可移植，只有 5 处 macOS 专属代码需要条件编译。用方案 A（共享源码 + 条件编译），改一处两边都生效。核心工作量 8-13 小时。
