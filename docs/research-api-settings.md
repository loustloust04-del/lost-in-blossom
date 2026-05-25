# Research — 设置 / API 页 + API 技术债

> 2026-04-17 起草。对应 roadmap 项：**T1（Keychain）** + **E16（多 provider 流程走通）** + API 页代码卫生。

---

## 一、scope 确认

**这轮要一把清的**：

| 条目 | 类型 | 来源 |
|------|------|------|
| API Key 从 UserDefaults 迁到 Keychain | 安全债 | T1 |
| 多 provider 配置/切换流程走通 | 功能债 | E16 |
| APISettingsTab.swift 死代码清理 | 代码卫生 | 无 # |
| macOS / iOS body 重复去重 | 代码卫生 | 无 # |
| 已保存自定义 provider 的可编辑性 | UX 缺陷 | 本次发现 |
| 选中模型失效时的无声 fallback | UX 缺陷 | 本次发现 |

**这轮不做（但记一笔）**：
- C4 Token 精确计数 — 新功能，不是债
- C11 API dashboard — 新功能，不是债
- E7 只显示常用模型 — Phase 0.5 单独任务，UI 改动点在 `CardFlowView.ChatInputBar`，跟 API 页无交集
- 多 profile 下的 API Key 隔离 — 当前架构是全局共享 key，改这个要动 ProfileManager，不在这轮

---

## 二、现状架构

### 2.1 数据层（APIProvider.swift）

```
APIProvider
├── id, name, type (openaiCompatible | anthropic)
├── baseURL, extraHeaders
├── models: [ProviderModel]
└── isBuiltIn: Bool

ProviderManager  @Observable
├── providers  = 内置 + 自定义（每次 reload）
├── apiKey(for:)       → UserDefaults "apikey-{id}"  ★ T1
├── setApiKey(_:for:)  → UserDefaults.set
├── hasKey(for:)
├── enabledProviders / availableModels / model(byId:)
├── addProvider / updateProvider / removeProvider
├── addModel / removeModel  （built-in → extra dict / custom → 直接改）
├── fetchModels / fetchAndMergeModels  （调 /models 端点）
└── testConnection（openai 用 GET /models，anthropic 用 POST /messages 探针）
```

**持久化 key 清单**：

| UserDefaults key | 内容 |
|------------------|------|
| `apikey-{providerId}` | 明文 API Key（★ T1 = 要迁 Keychain）|
| `customProviders` | JSON 编码的 `[APIProvider]` |
| `customModels` | JSON 编码的 `[String: [ProviderModel]]`（built-in 追加模型用）|
| `selectedChatModel` | 选中的 `"{providerId}/{modelId}"` |
| `openrouter-api-key` | 老版残留，有一次性迁移（`APISettingsTab.loadAPIKeys`）|

### 2.2 消费层

| 消费点 | 读法 |
|--------|------|
| `ProviderRouter.sendStreaming` (`ChatService.swift:534`) | `providerManager.apiKey(for: provider.id)` |
| `ProviderRouter.sendNonStreaming` (`ChatService.swift:572`) | 同上 |
| `ChatInputBar.currentModel` (`CardFlowView.swift:444`) | `providerManager.model(byId: selectedModelId)` |
| `ModelPickerPopover` (`CardFlowView.swift:700`) | `providerManager.enabledProviders` 展开所有 models |

**ChatService 里写死的 OpenAI/Anthropic 字段**（`ChatService.swift:204,242,375,413`）直接拼 key 进 header，完全不碰存储，迁 Keychain 对它们是透明的。

### 2.3 UI 层（APISettingsTab.swift, 1205 行）

**主流程 UI**（当前实际在用的）：

```
Provider Picker（built-in + ── 自定义 ── + 自定义 OpenAI/Anthropic + 已存的 custom）
  │
  ├─ 选中内置 → 显示 API Key 字段 + 测试 + 模型列表
  ├─ 选中"自定义 OpenAI/Anthropic" → +名称/URL 字段 + 手动模型 ID
  └─ 选中已存 custom → 只显示 API Key + 删除（★ 编辑不了 name/URL）
```

**布局重复**：
- `body` (L60-316, macOS VStack) 
- `iOSBody` (L320-516, iOS List)
- 两者字段、状态、回调都重复，只有容器类型和少量 padding/字号差异

**死代码**：
| struct | 行数 | 引用 |
|--------|-----|------|
| `ProviderCard` | L746-1010（265 行）| **无** |
| `AddProviderSheet` | L1014-1204（190 行）| **无** |

grep 全 repo 只匹配到自身定义，`ImportView.iOSProviderCard` 是同名局部变量不相关。合计 455 行 = 37%。

### 2.4 state 字段（APISettingsTab）

```swift
@State apiKeys: [String: String]     // 编辑中的 key 缓存（pre-save）
@State savedProvider: String?        // "OK" 气泡 1.5s 倒计时
@State connectionTestResults: [String: Result<String, Error>]
@State testingProvider: String?
@AppStorage("apiSelectedProvider") apiSelectedProviderId = "openrouter"
@State apiFetchedModels: [ProviderModel]    // 本次 fetch 的结果
@State apiIsFetchingModels, apiFetchError, apiModelSearch
@AppStorage("selectedChatModel") selectedChatModelId      // 底部 bar 共用
@State customName, customBaseURL, customSavedId, customManualModelId

// 未使用（死代码遗留）
@State showAddProvider, editingProvider, apiShowAdvanced
```

三个 `@State` 明显废弃，跟死代码一起清掉。

---

## 三、要改什么

### 3.1 T1 — API Key → Keychain

**方案**：新建 `Utils/KeychainStore.swift`，提供

```swift
enum KeychainStore {
    static func set(_ value: String?, for account: String)
    static func get(for account: String) -> String?
    static func remove(_ account: String)
}
```

用 `Security.framework` 原生 `SecItemAdd/Copy/Delete`（不引入第三方依赖）。Service 统一用 `"com.susu.MemoryPalace.apikey"`，account 用 `providerId`。

**ProviderManager 改动**：
- `apiKey(for:)` 改读 Keychain
- `setApiKey(_:for:)` 改写 Keychain
- `removeProvider(id:)` 里的 UserDefaults 清理改成 Keychain 清理

**一次性迁移**：`ProviderManager.init` 里扫一遍老 `apikey-{id}` UserDefaults key，搬到 Keychain 然后删掉 UserDefaults 明文。迁移后的 key 如果读取失败不阻断（fallback 为空）。

**风险**：
- Keychain 在 macOS/iOS 行为略不同，但 `kSecClassGenericPassword + kSecAttrService + kSecAttrAccount` 两端通用
- macOS Keychain 首次写入可能弹权限对话框 — 由于 Bundle ID 是签名过的 app，entitlements 正确应该无弹窗（需验证）
- iCloud Keychain 默认不同步（`kSecAttrSynchronizable` 默认 false），跟"必须纯本地"策略一致
- 沙盒：检查 project.yml entitlements，确保 keychain-access-groups 没限制

### 3.2 E16 — 多 provider 流程走通

**现在的坑**：
1. **已保存自定义 provider 不能编辑 name/URL** — L96 的 `if isCustomSelection` 只在 picker 选中 `__custom_openai__` / `__custom_anthropic__` 时为真。选中已存 custom (`id: "custom-xxxxxxxx"`) 时 `isCustomSelection=false`，字段被藏起来。
2. **选中模型失效 fallback 静默** — `ChatInputBar.currentModel` 找不到时直接用 `availableModels.first`，再不行 hardcode Claude Sonnet 4。用户以为自己选的还在用，其实在悄悄切。
3. **切 provider 后模型列表感知不对齐** — `onChange(apiSelectedProviderId)` 清 `apiFetchedModels`，再读时优先读 fetched（空） → fallback 到 provider.models，但 UI 上会闪一下"请先输入 API Key"（如果没 key）。非阻断但观感差。

**修法**：
1. **已存 custom 可编辑**：
   - 新增判断 `isEditableCustom = selectedProvider 存在 && !isBuiltIn`
   - 当 `isEditableCustom` 为 true 时也显示 name/URL 字段，预填 `selectedProvider.name / .baseURL`
   - "保存" 按钮路径：判断是否已存在同 id → 调 `updateProvider` 而非 `addProvider`
2. **死链提示**：
   - `ChatInputBar.currentModel` fallback 时，如果原选的 id 找不到且非空，弹 toast（或切到 fallback 时打 debug log）。简化做法：加一个方法 `modelOrFallback(id:)` 返回 `(ProviderModel, wasFallback: Bool)`，UI 层决定怎么提示。不想改 UI 的话至少打 `print` 警告 + 把 `selectedChatModel` 清空让用户下次打开 picker 看到没选中。
3. **切换 provider 的 UX**：
   - picker 选到有 key 的 provider → 自动 fetchModels（已有）
   - picker 选到没 key 的 provider → 不 fetch，显示"请先输入 API Key"（已有）
   - 输完 key 点保存后 → `apiAutoFetchModels()`（已有）
   - 这块其实合理，不改

### 3.3 死代码清理

直接删 `ProviderCard` (L746-1010) 和 `AddProviderSheet` (L1014-1204)。同步删未使用的 `@State showAddProvider, editingProvider, apiShowAdvanced`。

### 3.4 macOS/iOS body 去重

**现在**：`body`（macOS VStack）和 `iOSBody`（iOS List）两套，各自 250+ 行。

**方案**：抽出 per-section subview（都是 SwiftUI struct View 或 computed property），两端引用。关键分歧：
- macOS 用 `VStack(spacing: 16)` + `Divider().opacity(0.15)`
- iOS 用 `List { Section { } .listRowBackground/.listRowSeparator(.hidden) }`

两种容器无法共用，但**各 section 内容**可以。提炼：
- `providerPickerView`
- `customFieldsView`（name + URL + 手动 modelId）
- `apiKeyFieldView` + `connectionStatusView`
- `modelListSection`（已经是 computed property `apiModelListView`，两端复用 ✅）

改完后 `body` 和 `iOSBody` 都只负责容器拼装，每个 section 单独测。

**风险**：字号常量 `Theme.SettingsFont.*` vs `Theme.F.*` 两端命名不一致（iOS 用 `Theme.F`）。需确认两套常量对应关系（或这轮顺手统一到一套）。需查 Theme.swift 看差异。

### 3.5 可选增强（看 plan 阶段粟粟决定）

- **E7 常用模型**（独立任务，Phase 0.5 已排）— 底部 bar 只显示 favorites。API 页需要加"收藏"按钮。单独做就好。
- **多 profile API Key 隔离** — 当前所有楼层共享 key。工作量大，不在这轮。
- **fetch 模型的分类/过滤**（chat vs embedding）— `fetchModels` 已经过滤 embed/tts/whisper，OK。

---

## 四、受影响范围

| 文件 | 改动面 |
|------|--------|
| `MemoryPalace/Models/APIProvider.swift` | `ProviderManager.apiKey/setApiKey/removeProvider/init`（Keychain 迁移）|
| `MemoryPalace/Views/APISettingsTab.swift` | 大改：删死代码、去重 body、加可编辑 custom |
| `MemoryPalace/Utils/KeychainStore.swift` | 新建 |
| `MemoryPalace/Views/CardFlowView.swift` | 小改：`ChatInputBar.currentModel` fallback 改成显式清空 `selectedChatModel` |
| `project.yml` entitlements | 确认无需 keychain-access-groups 额外配置（本地 keychain 默认 OK）|

**不改的**：
- `ChatService.swift`（只消费 apiKey 字符串，迁移透明）
- `SettingsView.swift`（只作为 tab 容器）
- `ImportView.swift`（`iOSProviderCard` 是无关同名）
- `ConversationViewModel.swift`（只通过 ProviderRouter 用 key）

---

## 五、风险 & 未解之事

### 5.1 Keychain 沙盒/签名
- 第一次写入需要确认 macOS 不弹授权框。如果弹，要么改 entitlement，要么接受弹一次（用户自己的 keychain，合理）。
- 如果调试版签名跟 release 签名不一致，keychain 条目不互通（都是 macOS 习惯的事）。这轮不修，只记。

### 5.2 老 key 迁移幂等
- 迁移逻辑放 `ProviderManager.init`：扫 UserDefaults 所有 `apikey-*` key，拷到 Keychain，清 UserDefaults。只做一次的幂等做法：成功写 Keychain 后才删 UserDefaults。如果 Keychain 写失败（非常罕见），保留 UserDefaults 让下次启动重试。

### 5.3 selectedChatModel 死链清除时机
- 启动时检查 `selectedChatModel` 是否还能 resolve，失效就清空 + 打 warning。这样用户打开 picker 就看到"没选"，再手动挑。比悄悄 fallback 好。

### 5.4 macOS Keychain 跨实例访问
- 粟粟自己机器上开发 + TestFlight 版（不同签名）会各自独立 keychain 条目，这是正常行为，不是 bug。

### 5.5 build 验证
- 每次 implement 步骤改完 `xcodegen generate && xcodebuild -scheme MemoryPalace build`，确保 macOS + iOS 两端都编过（iOS 用 xcodebuild -destination 'generic/platform=iOS Simulator'）。

---

## 六、问粟粟的点

1. **Keychain 同步策略**：`kSecAttrSynchronizable` 默认 false（只存本机），符合"必须纯本地"原则吗？还是你希望 iCloud Keychain 同步 key（换机后不用重输）？【两个功能都做，设置里开关】
2. **死链 fallback 处理**：用户发现选中模型失效时，
   - A. 静默清空 `selectedChatModel`，下次打开 picker 是未选中态（**建议**）✅
   - B. 顶部加 toast "xx 模型已失效，已切到 yy"
   - C. 不处理，保留现行静默 fallback
3. **macOS/iOS body 去重**：要做到什么程度？
   - A. 提炼 4 个 subview，两端各自拼装（**建议**）✅
   - B. 彻底统一（写一个 adaptive 容器），工作量大
4. **E7（底部只显示常用模型）** 要不要顺手做？我倾向不做，它是 UI 习惯问题不是债。【等会再弄】
5. **预设/世界书搜索扩展**（C8）里有"API 管理完善"的影子吗？我理解 C8 跟 API 页无关，确认下。【是左栏搜索的问题和API无关】

---

*粟粟审完在这份文件上批注，我再进 Plan 阶段。*
