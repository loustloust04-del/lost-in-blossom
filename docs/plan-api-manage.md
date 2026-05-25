# Plan — API 保存/管理列表

> 2026-04-18。基于 `research-api-manage.md` 粟粟已批注的版本。

## 目标

让保存的 custom provider 显式地"躺在列表里"，带时间戳默认名、可改别称、可一键切回该 API 上次用过的模型。

## 粟粟决策

| 项 | 决策 |
|----|------|
| 范围 | 只做 API 管理 #1；E7 模型选择器配置、额度上限 都留给后续 |
| §3.1 列表范围 | A — 只列 custom provider |
| §3.2 "使用"语义 | C — 切到该 API 上次用过的模型（无则用第一个 model）|
| §3.3 默认命名 | C — 进表单预填时间戳 + 保存时空串兜底 |
| §3.4 列表位置 | 在 API 设置页内（picker 下方新 section）|
| §3.5 改名交互 | B+C — 长按/右键菜单 + 铅笔按钮都要，都触发 inline 编辑 |
| §六 lastUsedAt | 要（排序 + 显示相对时间）|

---

## 数据模型变化

`APIProvider` 加三个字段（均 Codable fallback 兼容老数据）：

```swift
struct APIProvider: Identifiable, Codable {
    let id: String
    var name: String
    var type: ProviderType
    var baseURL: String
    var extraHeaders: [String: String]
    var models: [ProviderModel]
    var isBuiltIn: Bool
    // 新增
    var createdAt: Date          // 默认 = Date()（老数据 decode fallback）
    var lastUsedModelId: String? // 可空
    var lastUsedAt: Date?        // 可空
}
```

**Codable 兼容**：自定义 `init(from:)`，用 `decodeIfPresent` + 默认值。内置 provider 常量里补上 `createdAt: Date()`（编译期常量不行；改成计算属性或在 builtIn 列表初始化时填）。

**持久化**：
- `customProviders` UserDefaults key 继续用（新字段透明写入）
- `lastUsedModelId` / `lastUsedAt` 变更会触发 custom 列表重写（内置 provider 不存 — 它们的 lastUsed 仅运行时记，无所谓）

**边界**：`lastUsed` 信息**只给 custom provider 持久化**（内置 provider 运行时记即可 — 他们反正列表里不显示）。简化：ProviderManager 内部维护 dict `[providerId: (modelId, Date)]`，custom 的从 APIProvider 字段读/写并存盘，内置的只存内存 dict。决策：**直接存进 APIProvider 字段**，内置的不 persist（反正字段默认为 nil）；这样代码更统一。

---

## 文件变动清单

| 文件 | 改动 |
|------|------|
| `Models/APIProvider.swift` | APIProvider 加 3 字段 + Codable 兼容；ProviderManager 加 `renameCustomProvider`、`touchLastUsed`、`useProvider` 方法 |
| `Views/APISettingsTab.swift` | 新 section「已保存的 API」；SavedAPICard 子视图；时间戳默认命名；onChange hook |
| `Views/CardFlowView.swift`（ChatInputBar / ModelPickerPopover）| 选 model 时调 `touchLastUsed` |
| 新增 helper | `Utils/TimestampFormatter.swift`（或直接放 APIProvider 文件里一个 enum）— "2026-04-18 06:13" 稳定格式 |

**不改**：KeychainStore、ChatService、其他 settings tab。

---

## UI 规格

### 卡片布局（SavedAPICard）

```
┌──────────────────────────────────────────┐
│ 智谱中转站                    [✏️]        │  ← 名字（inline TextField 聚焦时可改）
│ api.example.com/v1 · 3 小时前             │  ← URL（省略 https://）+ 相对时间
│                          [使用]           │  ← 右下角"使用"胶囊
└──────────────────────────────────────────┘
```

- 铅笔按钮 → 名字 TextField 聚焦 → 失焦保存
- 长按（iOS）/ 右键（macOS） → 菜单：「重命名」「使用」「删除」
- "使用"：调 `providerManager.useProvider(id:)` 切 `selectedChatModel` 到 lastUsedModelId（若空或失效 → 用 models.first；若 models 空 → 弹 toast "请先拉取模型"）
- 卡片若对应 provider 没 key → "使用"按钮 disable + 灰色提示"请先配置 API Key"

### Section 位置

**macOS body**：
```
Provider Picker
  ↓
【已保存的 API】  ← 新 section（只在有 custom 时显示）
  ↓
（如果 picker 选的是 custom）自定义字段
  ↓
API Key
  ↓
Connection status
  ↓
Model list
  ↓
iCloud sync toggle
```

**iOS body**：同样逻辑，List 的 Section("已保存的 API")。

如果一条 custom 都没有 → 整个 section 隐藏（不占版面）。

### 默认时间戳命名

- 当 `apiSelectedProviderId` 切到 `__custom_openai__` / `__custom_anthropic__` 时，`customName` 自动预填 `TimestampFormatter.minuteStamp(Date())` = `"2026-04-18 06:13"`
- 用户可清空 + 改写
- 保存时若 trim 后 name 仍为空 → 再兜底一次 minuteStamp

---

## 实施步骤 & Checklist

### Phase A：数据模型

- [ ] **A1** `APIProvider` 加 `createdAt: Date`、`lastUsedModelId: String?`、`lastUsedAt: Date?`
- [ ] **A2** 自定义 `init(from decoder:)` 兼容老数据（fallback createdAt = Date(), others = nil）
- [ ] **A3** 内置 `builtIn` 列表里所有 provider 初始化时填 `createdAt: Date()`、其他 nil
- [ ] **A4** `APIProvider` 加 coding keys 列全新字段
- [ ] **A5** 新建 `Utils/TimestampFormatter.swift`，`minuteStamp(_ date: Date) -> String` 返回 `"yyyy-MM-dd HH:mm"`（固定 POSIX locale，避免本地化 flip）
- [ ] **A6** `ProviderManager` 方法：
  - `customProviders: [APIProvider]` — filter `!isBuiltIn`，按 `lastUsedAt` 降序（nil 排最后）
  - `renameCustomProvider(id: String, newName: String)` — 只改 name
  - `touchLastUsed(providerId: String, modelId: String)` — 更新 lastUsedModelId + lastUsedAt；custom → 存盘；内置 → 仅内存（虽然不显示但调用不报错）
  - `useProvider(id: String) -> String?` — 按 lastUsedModelId fallback 到 first model，写入 `UserDefaults "selectedChatModel"`，返回 model.id 供 caller 反馈；若 provider 没 models 返回 nil
- [ ] **A7** macOS build pass

### Phase B：UI 列表 + 卡片

- [ ] **B1** 新建 `SavedAPICard` 内部 struct（写在 APISettingsTab.swift 里，只此处用）
  - 输入：`provider`、`providerManager`、回调 onUse / onRename / onDelete
  - 内部 `@State isEditing`、`@State editingName`
- [ ] **B2** 卡片布局：名字 row + URL/时间 row + "使用"按钮 row
- [ ] **B3** 铅笔按钮 → `isEditing = true` → TextField 聚焦；失焦调 onRename(editingName)
- [ ] **B4** 长按（iOS） / contextMenu（两端）菜单：「重命名」「使用」「删除」
- [ ] **B5** "使用"按钮 disable 条件：`!providerManager.hasKey(for: provider.id) || provider.models.isEmpty`
- [ ] **B6** APISettingsTab 里加 `savedAPIListContent` subview
  - 仅在 `providerManager.customProviders.isEmpty == false` 时渲染
  - 内容：标题「已保存的 API」+ VStack 列所有 SavedAPICard
- [ ] **B7** macOSBody / iOSBody 都把 `savedAPIListContent` 接上（位置见"UI 规格"）
- [ ] **B8** 相对时间格式化：自己写简单函数 `relativeTimeDescription(_:)`，返回 "刚刚 / N 分钟前 / N 小时前 / N 天前 / yyyy-MM-dd"（不靠 RelativeDateTimeFormatter 的本地化）

### Phase C：默认时间戳命名

- [ ] **C1** `handleProviderChanged()` 里，当切到 `customOpenAIId / customAnthropicId` 时，`customName = TimestampFormatter.minuteStamp(Date())`
- [ ] **C2** `saveCustomProvider()` 里保存前若 `name` 空 → 再填一次 minuteStamp（保底）
- [ ] **C3** 编辑已存 custom（`isEditableSavedCustom`）时 customName 仍预填 provider.name（不覆盖用户自己的名字）

### Phase D：lastUsed 追踪

- [ ] **D1** `ChatInputBar` 的 `ModelPickerPopover` onSelect：
  - 原本：`selectedModelId = model.id`
  - 加：`providerManager.touchLastUsed(providerId: model.providerId, modelId: model.modelId)`
- [ ] **D2** SavedAPICard "使用"按钮点击：
  - 调 `providerManager.useProvider(id: provider.id)`
  - 返回 nil 时 → 弹行内文字"请先拉取模型"
  - 返回非 nil → 隐式触发 lastUsedAt 更新（useProvider 内部做）

### Phase E：收尾

- [ ] **E1** 通读 diff：Codable 兼容老数据测试点（手动：改 customProviders UserDefaults 去掉新字段，看 decode 是否崩）
- [ ] **E2** macOS build
- [ ] **E3** iOS Simulator build
- [ ] **E4** git status 确认只动预期文件
- [ ] **E5** commit 策略：
  1. `feat: APIProvider 加 createdAt/lastUsed 字段 + ProviderManager 管理方法`
  2. `feat: API 设置页新增「已保存的 API」列表卡片 + 默认时间戳命名`
  3. `feat: ChatInputBar 选模型时记录 provider.lastUsedModelId`
  4. `docs: research + plan for API 管理`
- [ ] **E6** git push

---

## 验证清单（宣布完成前）

- [ ] macOS + iOS build 过
- [ ] 手动跑：
  - [ ] 新建"自定义 OpenAI" → name 字段预填 `"2026-04-18 HH:mm"`
  - [ ] 清空 name 直接保存 → name 变回 timestamp（兜底生效）
  - [ ] 保存后列表里出现卡片
  - [ ] 卡片铅笔 → inline 改名 → 失焦保存 → picker 下拉里也同步新名字
  - [ ] 长按/右键卡片 → 看到「重命名/使用/删除」三项
  - [ ] 在聊天栏选该 provider 的某个 model 发消息 → 回 API 设置 → 卡片时间更新为"刚刚"
  - [ ] 点"使用" → 聊天栏底部模型按钮切到该 provider 记住的那个 model
  - [ ] 卡片上 URL 若很长要截断不换行
- [ ] Codable 兼容：老数据（无 createdAt 字段的 customProviders JSON）decode 不崩

---

## 风险速查

| 风险 | 缓解 |
|------|------|
| Codable 新字段让老用户崩 | 自定义 init 用 decodeIfPresent + 默认值 |
| `touchLastUsed` 频繁写盘 | 每次 model 切换才写，频率低，可接受 |
| `useProvider` 时 provider.models 为空 | 返回 nil + UI 提示"请先拉取模型" |
| 改名触发 UserDefaults 写入 | 失焦 onChange 才写，可接受 |
| 内置 provider 的 lastUsedModelId 不 persist | 设计如此，内置本来不进列表 |
| 相对时间 "N 天前" 跨 timezone 算错 | 用 Calendar.current，系统时区 OK |

---

## 不做清单

- 额度上限 / 超额掐停（下一轮；要 C4 tokenizer 或定价表支持）
- 模型选择器配置（E7，roadmap 里单独排期）
- 最近使用时间"排序方向"选项（默认 lastUsedAt 降序，无选项）
- 拖拽排序 / 置顶
- 跨 provider 的全局默认 provider 概念（仍通过 selectedChatModel 间接切换）

---

*粟粟批个"OK 执行"我就进 Phase A。*
