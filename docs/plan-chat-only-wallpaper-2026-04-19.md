# Plan: wallpaper 缩到聊天页（iOS）

日期：2026-04-19
分支：`codex/theme-kelivo-settings`
状态：**Draft，等粟粟批注**

---

## 1. 目标

为了把上架测试优先级让出来，暂停追查 iOS 全局 wallpaper safe-area 漏白 bug（存档见 `handoff-ios-wallpaper-safearea-pending-2026-04-19.md`）。

缩范围：**只有 iOS 聊天页**可以看到背景图，其它页面（列表 / 右页 / 设置 / 主题页 / 主题编辑器）统一用 `Theme.sidebarBg` 实底。macOS **完全不动**。

粟粟选择（已确认）：
- 聊天页 wallpaper **漫满屏**（漫到 status bar + home indicator）
- macOS **不同步**，保持现状
- ThemeEditor 的"预览 / 透明度 / 偏移"UI **保留**
- debug 模式代码**保留**（上架前再删）

---

## 2. 具体改动

### 2.1 `ContentView.swift` body

**删**：
```swift
.background {
    ThemeBackgroundView(
        fill: Theme.mainBg,
        imageURL: manager.currentBackgroundImageURL,
        scheme: manager.activeScheme,
        backgroundStyle: manager.currentBackgroundStyle
    )
    .ignoresSafeArea()
}
```

**和 iOS 下相关的 `zstackLayer` mode 分支**：iOS 下那条 debug 路径也要跟着调整，让 zstackLayer mode 在 iOS 下不再把全局 wallpaper 挂到 root（因为现在**就是没有全局 wallpaper**）。为简单起见，这条 debug mode 在 iOS 下什么都不做，继续保留代码不 revert（粟粟可能以后回来调）。

**加（iOS）**：
```swift
#if os(iOS)
.background(Theme.sidebarBg.ignoresSafeArea())
#endif
```

纯色 `.ignoresSafeArea()` 不经过 GeometryReader，漫整屏是可靠的，没漏白问题。

macOS 下的 `.background { ThemeBackgroundView ... }` 保留（macOS 不动）。

### 2.2 `ContentView.iOSChatPage`

加底层 wallpaper：
```swift
private var iOSChatPage: some View {
    ZStack(alignment: .top) {
        // Wallpaper bottom layer (聊天页专属)
        ThemeBackgroundView(
            fill: Theme.mainBg,
            imageURL: (themeManager ?? ThemeManager.shared).currentBackgroundImageURL,
            scheme: (themeManager ?? ThemeManager.shared).activeScheme,
            backgroundStyle: (themeManager ?? ThemeManager.shared).currentBackgroundStyle
        )
        .ignoresSafeArea()

        if viewModel.selectedConversation != nil {
            CardFlowView(viewModel: viewModel, stickerVM: stickerVM)
        } else {
            EmptyStateView(showImporter: $showImporter)
        }

        // Top nav buttons
        HStack { ... }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}
```

聊天页内部可能依然有 safe-area 漏白 bug，但粟粟接受这个（选 B "漫满屏"的代价）。**debug 代码保留**，如果她以后切 A/B/C 模式试，依然能覆盖到聊天页的 ThemeBackgroundView。

### 2.3 `SettingsView.swift` iOSSettingsBody

**把**：
```swift
.background {
    ThemeBackgroundView(
        fill: Theme.sidebarBg,
        ...
    )
    .ignoresSafeArea()
}
```

**改为**：
```swift
.background(Theme.sidebarBg.ignoresSafeArea())
```

macOS 的 `macOSSettingsBody` 不动。

### 2.4 其它 surface 不动

- `SidebarView.swift:332` 的 `Theme.sidebarBg`（不 ignore）保留现状 —— root 的 sidebarBg 已经铺满 safe area，Sidebar 内部不用再 ignore，也不会切割
- `MemoryPanelView.swift` 的 `.background(Theme.sidebarBg)` 保留
- `CardFlowView.swift` 里聊天页的顶底 VariableBlur + 渐变保留 —— 聊天页 wallpaper 生效后这些渐变帮助收尾
- `ThemeManager / AppTheme / ThemeAssetStore / ThemeBackgroundView / ThemeEditor / ThemeSettingsTab` **全部不动**

---

## 3. 验证

```bash
xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build
xcodebuild -scheme MemoryPalace build  # macOS
```

simulator 里手动看：

1. **列表页**：status bar + home indicator 区都是 `Theme.sidebarBg` 浅紫/浅薄荷，**无切割线无白条无 wallpaper**。
2. **聊天页**：wallpaper 漫满屏（可能有粟粟以前吐槽的 safe-area 漏白现象——本轮接受，debug 开关后续再搞）。
3. **右页**：和列表页一样，sidebarBg 铺满，无 wallpaper。
4. **设置页**：sidebarBg 铺满，无 wallpaper。
5. **主题编辑器**：背景图预览/调节 UI 还在，功能不坏。
6. **无 wallpaper 主题**：聊天页是 mainBg 实底，和之前一样。

---

## 4. Checklist

- [ ] 粟粟批此 plan
- [ ] `ContentView.body` 删 root wallpaper + iOS 补 sidebarBg.ignoresSafeArea()
- [ ] `ContentView.iOSChatPage` 加 ThemeBackgroundView bottom layer
- [ ] `SettingsView.iOSSettingsBody` 改用 sidebarBg 实底
- [ ] `xcodebuild -scheme MemoryPalace build` 通过
- [ ] `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build` 通过
- [ ] simulator 手动验证 6 条（列表页 / 聊天页 / 右页 / 设置页 / 主题编辑器 / 无 wallpaper 主题）
- [ ] git commit + push

---

## 5. 不做的事

- 不删 debug 代码（Utils/DebugRenderSettings / Views/DebugSettingsTab / ThemeBackgroundView 的 mode switch / ContentView 的 zstackLayer 和 page indicator mode switch）
- 不动 macOS
- 不删 ThemeEditor / ThemeSettingsTab 的背景图调节 UI
- 不修聊天页自己 wallpaper 的 safe-area 漏白（handoff 里讲了，以后再说）
