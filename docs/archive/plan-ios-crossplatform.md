# Plan: iOS 跨平台 — 共享源码 + 条件编译

> 基于 research-ios-crossplatform.md，CC 制定，粟粟批注
> **don't implement yet**

---

## 目标

让记忆宫殿同时出 macOS + iOS 版本。共享一套源码，改一处两边生效。分阶段交付，每个阶段结束都是一个可用的状态。

## 策略

方案 A：两个 target 共享同一个 `MemoryPalace/` 源码目录，用 `#if os()` 条件编译区分 5 处平台专属代码。不拆文件夹，不建 framework。

---

## 阶段一：能编译（iOS target + 条件编译）

> 目标：iOS target 编译通过，能在模拟器上启动看到界面。不追求完美适配。

### Step 1: project.yml 加 iOS target

- [ ] 1.1 在 `project.yml` 的 `targets` 下新增 `MemoryPalaceIOS`：

```yaml
MemoryPalaceIOS:
  type: application
  platform: iOS
  deploymentTarget:
    iOS: "17.0"
  sources:
    - path: MemoryPalace
  dependencies:
    - package: MarkdownUI
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.susu.MemoryPalace.ios
      PRODUCT_NAME: 记忆宫殿
      TARGETED_DEVICE_FAMILY: "1,2"  # iPhone + iPad
      INFOPLIST_VALUES:
        UILaunchScreen: {}
        CFBundleDisplayName: 记忆宫殿
```

- [ ] 1.2 `xcodegen generate` 验证生成两个 target
- [ ] 1.3 尝试 `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 16'` 看报什么错

### Step 2: MemoryPalaceApp.swift 条件编译

- [ ] 2.1 `.windowStyle()` 和 `.windowToolbarStyle()` 用 `#if os(macOS)` 包裹
- [ ] 2.2 `WindowConfigurator` 整个 struct 用 `#if os(macOS)` 包裹
- [ ] 2.3 `.background(WindowConfigurator())` 用 `#if os(macOS)` 包裹
- [ ] 2.4 `.commands { ... }` 键盘快捷键用 `#if os(macOS)` 包裹
- [ ] 2.5 Build iOS 验证

### Step 3: ContentView.swift 条件编译

- [ ] 3.1 `WindowFullscreenObserver` 整个 struct 用 `#if os(macOS)` 包裹
- [ ] 3.2 使用 `WindowFullscreenObserver` 的地方加 `#if os(macOS)` / `#else` 分支
- [ ] 3.3 iOS 分支里删掉全屏相关逻辑，只保留基础布局
- [ ] 3.4 `frame(minWidth: 800, minHeight: 500)` 用 `#if os(macOS)` 包裹（iOS 不限制窗口尺寸）
- [ ] 3.5 Build iOS 验证

### Step 4: FontManager.swift 条件编译

- [ ] 4.1 `registerImportedFonts()` 内的 CoreText 调用用 `#if os(macOS)` 包裹
- [ ] 4.2 iOS 分支提供空实现（`static func registerImportedFonts() {}`）
- [ ] 4.3 Build iOS 验证

### Step 5: SettingsView.swift 条件编译

- [ ] 5.1 `NSOpenPanel()` 那一处（批量导出选目录）用 `#if os(macOS)` 包裹
- [ ] 5.2 iOS 分支用 `.fileImporter()` 替代（或暂时禁用批量导出目录选择）
- [ ] 5.3 Build iOS 验证

### Step 6: 其他编译错误修复

- [ ] 6.1 逐个修复 iOS build 报出的其他编译错误（如果有）
- [ ] 6.2 macOS build 仍然通过（不能因为加 iOS 把 macOS 搞坏）
- [ ] 6.3 两个 target 都 build 通过
- [ ] 6.4 Commit + push

**阶段一产出**：iOS 模拟器上能启动 app，能看到界面（可能布局丑，但能用）。

---

## 阶段二：能用（iOS 基础适配）

> 目标：iPhone 上能导入对话、浏览、聊天。不追求完美，但核心功能可用。

### Step 7: 导航适配

- [ ] 7.1 检查 `NavigationSplitView` 在 iPhone 上的表现（自动变 push 导航）
- [ ] 7.2 如果 sidebar 在 iPhone 上不好用，加 `#if os(iOS)` 适配（比如用 `.navigationSplitViewStyle(.automatic)`）
- [ ] 7.3 iPad 上验证分栏布局正常
- [ ] 7.4 Build 验证

### Step 8: 交互适配

- [ ] 8.1 CardFlowView 的 `.onHover` 在 iOS 上无效 — 需要把 hover 按钮改为常显或长按菜单
- [ ] 8.2 用 `#if os(iOS)` 让 hover 按钮在 iOS 上始终显示（opacity=1）
- [ ] 8.3 SidebarView 的 hover 效果同理适配
- [ ] 8.4 Build 验证

### Step 9: 设置页 iOS 适配

- [ ] 9.1 检查 SettingsView 在 iPhone 上的表现
- [ ] 9.2 如果 tab bar 显示不下，用 `#if os(iOS)` 改成 `List` + `NavigationLink` 形式
- [ ] 9.3 弹窗尺寸（`.frame(width:height:)`）在 iOS 上用 `.sheet` 自适配
- [ ] 9.4 Build 验证

### Step 10: 输入栏适配

- [ ] 10.1 ChatInputBar 在 iPhone 上键盘弹出时的布局
- [ ] 10.2 检查 TextEditor 在 iOS 上的表现
- [ ] 10.3 发送按钮大小适配触摸
- [ ] 10.4 Build 验证
- [ ] 10.5 Commit + push

**阶段二产出**：iPhone/iPad 上能正常浏览对话、跟 AI 聊天、管理记忆。

---

## 阶段三：好用（打磨，可以后做）

> 目标：iOS 体验不是"macOS 的移植版"，而是原生 iOS 感觉。

### Step 11: iPhone 专属优化
- [ ] 11.1 iPhone 上 sidebar 改为底部 TabView（对话/收藏/设置）
- [ ] 11.2 对话列表全屏展示，点击进入聊天
- [ ] 11.3 返回手势
- [ ] 11.4 触摸友好的间距和按钮大小

### Step 12: iPad 专属优化
- [ ] 12.1 iPad 分屏（Multitasking）支持
- [ ] 12.2 iPad 键盘快捷键
- [ ] 12.3 Apple Pencil 支持（远期）

### Step 13: iCloud 同步
- [ ] 13.1 ModelConfiguration 启用 CloudKit
- [ ] 13.2 Apple Developer 账号 + CloudKit container 配置
- [ ] 13.3 macOS 和 iOS 数据自动同步
- [ ] 13.4 冲突解决策略

### Step 14: App Store
- [ ] 14.1 App Icon（iOS 版）
- [ ] 14.2 Launch Screen
- [ ] 14.3 隐私声明（API key 存储、网络请求）
- [ ] 14.4 TestFlight 内测
- [ ] 14.5 提交审核

---

## 风险

| 风险 | 缓解 |
|------|------|
| NavigationSplitView 在 iPhone 上表现不一致 | SwiftUI 17+ 已大幅改善，先试再说 |
| MarkdownUI 在 iOS 上渲染性能 | 先用模拟器测，大对话可能需要懒加载 |
| SwiftData iOS 17 的 bug | Apple 已修复大部分，iOS 17.4+ 稳定 |
| 加 iOS 把 macOS 搞坏 | 每步都验证两个 target 同时编译通过 |
| 设置页在小屏上不好用 | 阶段二用最简适配，阶段三重新设计 |

---

## 执行原则

1. **每一步都确保 macOS build 不坏** — iOS 是加法，不能影响现有功能
2. **阶段一只管编译通过** — 不追求好看，先让它跑起来
3. **阶段二只管能用** — 核心功能通了就行，UI 打磨放阶段三
4. **阶段一和阶段二可以一口气做完** — 总工作量 ~8 小时
5. **阶段三可以慢慢来** — 每个 Step 独立，不互相依赖
