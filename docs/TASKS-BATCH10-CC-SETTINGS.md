# 第十批任务 — CC Bridge 设置页修复

> 日期：2026-06-10
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟 VPS `/root/projects/SusuPalace/MemoryPalace/Views/APISettingsTab.swift` 第 440-575 行

---

## 背景

CC Bridge 的"保存并连接"和"重新连接"按钮之前一直不工作，已被删除。
现在 CC Bridge Phase 1-4 全部重写完成，需要把设置页修好。
直接照搬粟粟的 ccBridgeStatusContent 实现。

---

## Task 1: 替换 ccBridgeStatusContent 函数

**文件**: `MemoryPalace/Views/APISettingsTab.swift`

**步骤**:
1. 用 exec_vps 读粟粟的实现：
   ```
   sed -n '440,575p' /root/projects/SusuPalace/MemoryPalace/Views/APISettingsTab.swift
   ```
2. 找到我们的 `ccBridgeStatusContent` 函数（搜索这个函数名）
3. 用粟粟的版本完整替换我们的版本
4. 同时补上缺少的 @State 变量：
   - `@State private var ccBridgeURLDraft = ""`
   - `@State private var ccBridgeURLSaved = false`
   - `@State private var ccBridgeURLBackupDraft = ""`
   - `@State private var ccBridgeURLBackupSaved = false`
5. 补上 `reconnectCCBridge()` 函数（粟粟的第 570-578 行）

**粟粟的 reconnectCCBridge 核心逻辑**:
```swift
private func reconnectCCBridge() {
    CCBridgeWebSocketClient.shared.disconnect()
    let primary = providerManager?.ccBridgeBaseURL ?? APIProvider.ccBridge.baseURL
    let backup = providerManager?.ccBridgeBaseURLBackup ?? ""
    let urls: [URL] = [primary, backup].filter { !$0.isEmpty }.compactMap(URL.init(string:))
    guard !urls.isEmpty else { return }
    let t = providerManager?.apiKey(for: "cc-bridge")
    CCBridgeWebSocketClient.shared.connect(urls: urls, token: (t?.isEmpty == false) ? t : nil)
}
```

**注意**:
- 如果 ProviderManager 没有 `ccBridgeBaseURL` / `ccBridgeBaseURLBackup` / `setCCBridgeBaseURL()` / `setCCBridgeBaseURLBackup()` 这些方法，需要补上（参考粟粟的 ProviderManager）
- 如果 CCBridgeWebSocketClient 没有 `connect(urls:token:)` 方法（支持多URL fallback），需要补上或简化为单URL版本 `connect(url:token:)`
- 检查 APIProvider.ccBridge 的默认 baseURL 是什么

**commit**: `fix(cc-settings): restore CC Bridge connection UI from susu's implementation`

---

## Task 2: 验证 CCBridgeWebSocketClient 接口

**文件**: `MemoryPalace/Services/CCBridgeWebSocketClient.swift`

**检查**:
1. 有没有 `disconnect()` 方法？
2. 有没有 `connect(urls:token:)` 或 `connect(url:token:)` 方法？
3. 有没有 `isConnected` 属性？
4. 如果缺少任何一个，参考粟粟的实现补上

**commit**: `fix(cc-bridge): ensure WebSocket client has connect/disconnect/isConnected`

---

## 规则

- 照搬粟粟的代码，不自己发明
- 如果粟粟的代码依赖我们没有的方法/属性，先补依赖再接 UI
- 每个 Task 单独 commit + push
