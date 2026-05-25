# Plan — 设置 / API 页 + API 技术债

> 2026-04-17。基于 `research-api-settings.md` 粟粟已批注的版本。

## 目标

一把清完 API 相关所有技术债和 UX 缺陷，让多 provider 配置/切换真正能用、key 安全存 Keychain、代码干净、两端复用。

## 粟粟的决策（取自 research 批注）

| 问题 | 决策 |
|------|------|
| Keychain iCloud 同步 | **本地 + iCloud 两种都做，API 设置页加开关** |
| 死链 fallback | 静默清空 `selectedChatModel`，下次 picker 未选中态 |
| body 去重 | 提炼 4 个 subview，两端各自拼装 |
| E7 只显示常用模型 | 这轮不做 |
| C8 搜索扩展 | 跟 API 页无关 |

---

## 文件变动清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `MemoryPalace/Utils/KeychainStore.swift` | 新建 | Security.framework 薄封装，支持可选 iCloud 同步 |
| `MemoryPalace/Models/APIProvider.swift` | 改 | `ProviderManager` 的 key 读写走 Keychain；启动迁移 UserDefaults → Keychain；提供同步开关切换 API |
| `MemoryPalace/Views/APISettingsTab.swift` | 大改 | 删死代码、加 iCloud Keychain 开关、已存 custom 可编辑、拆 4 subview |
| `MemoryPalace/Views/CardFlowView.swift` | 小改 | `ChatInputBar.currentModel` fallback 时清空 `selectedChatModel`，打印 warning |
| `MemoryPalace/MemoryPalaceApp.swift` | 小改 | 启动时一次性 resolve selectedChatModel，失效清空（也可放 ContentView）|

**不改**：ChatService / ConversationViewModel / SettingsView 容器 / ImportView。

---

## 数据模型变化

**新增 UserDefaults key**：
- `apiKeyCloudSync: Bool`（默认 false，控制后续写入和读取时是否同步到 iCloud Keychain）

**Keychain 条目**：
- Service: `"com.susu.MemoryPalace.apikey"`
- Account: `providerId`（如 `"openrouter"`, `"custom-abc12345"`）
- Value: API Key utf8 data
- `kSecAttrSynchronizable`: 按 `apiKeyCloudSync` 的值

**淘汰的 UserDefaults key**：
- `apikey-{providerId}` → 启动时迁移到 Keychain 后删除
- 老 `openrouter-api-key` 迁移仍保留（和原本一致）

---

## 实施步骤 & Checklist

每一项完成后在此文件里打 `✅`。每改完一小块就 `xcodegen generate && xcodebuild -scheme MemoryPalace build` 验证。

### Phase A：Keychain 基建

- ✅ **A1** 新建 `MemoryPalace/Utils/KeychainStore.swift`
  - API：
    ```swift
    enum KeychainStore {
        static let service = "com.susu.MemoryPalace.apikey"
        static func set(_ value: String?, account: String, sync: Bool) -> Bool
        static func get(account: String) -> String?             // 用 SynchronizableAny
        static func remove(account: String)                      // 用 SynchronizableAny
        static func allAccounts() -> [String]                    // 用 SynchronizableAny, MatchLimitAll
    }
    ```
  - `set(nil, ...)` 等价于 `remove`
  - 写入：先 `SecItemDelete`（Any）把本机+云条目都删掉，再 `SecItemAdd` 按 sync 写一份。避免同 account 重复
  - 读取：`SecItemCopyMatching` 带 `kSecAttrSynchronizable: kSecAttrSynchronizableAny`
  - 返回值：set 成功/失败、get 成功/nil（日志打 `OSStatus` 方便排查）
- ✅ **A2** project.yml 确认：无 sandbox、无 keychain-access-groups，generic password 直接可用
- ✅ **A3** macOS build 通过（iOS build 在 E2 统一验）

### Phase B：ProviderManager 迁移

- ✅ **B1** `ProviderManager.apiKey(for:)` 改读 Keychain
- ✅ **B2** `setApiKey(_:for:)` 按 `cloudSyncEnabled` 写 Keychain
- ✅ **B3** `removeProvider(id:)` 改用 `KeychainStore.remove`
- ✅ **B4** `migrateLegacyKeysIfNeeded()` 在 init 调用，搬完清 UserDefaults
- ✅ **B5** `reencryptAllKeys(sync:)` 同步开关切换后统一重写
- ✅ **B6** macOS build 通过；手动验证留到 E2/E3 一起跑

### Phase C：API 设置页重构

- ✅ **C1** 删死代码（ProviderCard / AddProviderSheet / 3 个无用 @State）
- ✅ **C2** 提炼 subview：providerPickerContent / customFieldsContent / apiKeyContent / connectionStatusRow / modelListContent / cloudSyncContent
- ✅ **C3** macOS `body` 拼 subview + Divider
- ✅ **C4** iOS `iOSBody` 用 Section 包 subview
- ✅ **C5** 已存 custom 可编辑 name/URL；保存路径按 `isEditableSavedCustom` 走 update
  - 新 computed：`isEditableSavedCustom = selectedProvider.map { !$0.isBuiltIn } == true`
  - `customFieldsView` 在 `isCustomSelection || isEditableSavedCustom` 时显示
  - `onChange(apiSelectedProviderId)` 切到已存 custom 时预填 `customName = selectedProvider.name`, `customBaseURL = selectedProvider.baseURL`, `customSavedId = selectedProvider.id`
  - "保存" 按钮：`isEditableSavedCustom` 时调 `updateProvider`（内部已是 replace by id）
- ✅ **C6** iCloud Keychain 同步开关 + `reencryptAllKeys` + 状态反馈文字
- ✅ **C7** macOS + iOS build 全过（手动交互验证留 E2/E3）

### Phase D：死链清除

- ✅ **D1+D2** `ProviderManager.resolveStaleSelectedModel()` 统一处理；`ChatInputBar.onAppear` + API 页删除后立即触发
- ✅ **D3** macOS + iOS build 通过（实际删除验证留 E2/E3）

### Phase E：收尾

- ✅ **E1** 通读改动清爽
- ✅ **E2** iOS build 通过
- ✅ **E3** macOS build 通过
- ✅ **E4** git status：只动 API 相关文件，没碰粟粟的 WIP
- ✅ **E5** 3 个 commit（feat Keychain / refactor API 页 / docs）
- ✅ **E6** push origin master

---

## 验证清单（宣布完成前）

- [ ] macOS build 通过
- [ ] iOS Simulator build 通过
- [ ] 手动跑过：
  - [ ] API 页：切 built-in provider → 输 key → 保存 → 测试 → 拉模型 → 选模型
  - [ ] API 页：加自定义 OpenAI → 保存 → 再次选中能看到 name/URL 且可改
  - [ ] API 页：删除自定义 → 底部选模型显示 fallback
  - [ ] API 页：开/关 iCloud Keychain 开关，看日志有无错
  - [ ] 实际用当前 key 发一条消息，收到响应
- [ ] 钥匙串 app（macOS）里看得到 `com.susu.MemoryPalace.apikey` 条目
- [ ] UserDefaults 里 `apikey-*` 条目已迁移并清空（`defaults read com.susu.MemoryPalace | grep apikey`）

---

## 风险速查

| 风险 | 缓解 |
|------|------|
| Keychain 首次写入弹授权框 | 正常用户自己 keychain，允许一次即可；开发期可能会有 |
| 开/关 iCloud 同步切换失败（部分 key 迁成功部分失败） | `reencryptAllKeys` 返回失败列表，UI 上显示；下次启动迁移兜底会修复遗留 UserDefaults 条目但 Keychain 不会自愈 — **简化：失败只打日志，用户重新输一遍** |
| 迁移时 Keychain 写失败 | 不删 UserDefaults，下次启动重试 |
| macOS 沙盒签名 ≠ TestFlight 签名，keychain 互不通 | 已知行为，不修 |
| ContentView 启动 resolve 时 providerManager 未 ready | 放 onAppear 而非 init，providerManager 注入后触发 |

---

## 不做清单（再次申明）

- C4 Token 精确计数
- C11 API dashboard
- E7 常用模型底部 bar 过滤
- 多 profile API Key 隔离
- 字号常量重构（`Theme.SettingsFont` 和 `Theme.F` 已是 typealias，不是两套）

---

*粟粟批个"OK 执行"我就进 Phase A。*
