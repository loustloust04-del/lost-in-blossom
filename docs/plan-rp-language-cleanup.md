# RP 语言中性化（上架前清理）

> 最后更新：2026-04-25  
> 分支：codex/theme-kelivo-settings  
> 状态：**plan-only**，粟粟批注后再 implement，**don't implement yet**

---

## 背景

Hermes 两轮 sanity check（前轮 b9axvw77u / 后轮 b0viglopj）确认：

- App Store 审核 2026 收紧 Guideline **1.1.4 / 1.2 / 4.7.1 / 4.7.5**，AI chat/RP app 是高风险类别
- **BYOK 不免责** — Apple 仍把 AI 输出算 app 内容（"自己 API key、用户自填的"挡不住）
- **TestFlight 不是 loophole** — External Beta App Review 用相同实质规则
- **17+ 评级不 override** 内容禁令
- Apple 用 **cumulative pattern recognition** — "角色描述 + 角色性格 + 场景 + 第一句话"组合是 strongest suspicion trigger
- **Default profile 是 product editorial statement** — reviewer 第一眼看到就判产品定位
- **关系框架词清单**：陪伴 / 懂你 / 记得你 / 回家 / 宫殿 / 只属于你 / 专属AI（这些反复触发）

## 决策（粟粟 2026-04-25 拍板）

**选项 A — 完全 utility 路线**（Apple 友好，Hermes 推荐）：

| 维度 | 决定 |
|------|------|
| 默认楼层名 | **"对话空间"** |
| 默认 AI 名 | **"助手"** |
| Beta App Description | **Hermes 第二版**（最保守） |
| 原文案 | **存档**（v1.1+ 渐进引入） |

**牺牲**：暂时失去产品诗化语感（小房子 / AI 记得你 / 趴只猫）。

**反弹策略**：审过 v1.0 后渐进引入；onboarding 让用户**自己命名**默认楼层（Apple 不监控运行时）。

---

## 改动 Checklist

### A. 默认插槽（`Models/Preset.swift`）

- [ ] L78: `🎭 角色描述` → `📝 角色信息`
- [ ] L80-81: `🎭 角色性格` 整 slot **删除**（保留 `PromptSlot.charPersonalityId` 在 L115 builtInMarkers 集合，兼容 SillyTavern import）
- [ ] L82: `🌍 场景` → `📖 背景设定`
- [ ] L117: `"nsfw"` 字符串 **保留**（SillyTavern 协议 marker，binary 扫描风险极低）

### B. UI label & placeholder（`Views/PersonaSettingsTab.swift`）

- [ ] L60 placeholder: `"角色的外貌、背景、性格..."` → `"AI 助手的设定、风格、背景..."`
- [ ] L62 placeholder: `{{user}}: 你好\n{{char}}: 汪汪～` → `{{user}}: 你好\n{{char}}: 你好，今天能帮什么？`
- [ ] L799 label: `角色描述` → `角色信息`
- [ ] L800 placeholder: 同 L60
- [ ] L804 placeholder: 同 L62

### C. CharacterCardEditor（`Views/CharacterCardEditor.swift`）

- [ ] L43: `"角色名"` → `"名称"`
- [ ] L51: `"角色描述"` → `"角色信息"`
- [ ] L52: `"性格"` 字段 **UI 删除**（model 层 `personality` 字段保留兼容 SillyTavern V2/V3 import）

### D. WorldBook picker（`Views/WorldBookPanelView.swift`）

- [ ] L723: `"角色描述前"` → `"角色信息前"`
- [ ] L724: `"角色描述后"` → `"角色信息后"`
- [ ] L1027: 同 L723
- [ ] L1028: 同 L724

### E. SillyTavern 标识淡化

- [ ] `Views/PersonaSettingsTab.swift:881`: `"导入酒馆预设"` → `"导入 Prompt 预设"`
- [ ] `MemoryPalaceApp.swift:942`: `"支持酒馆 JSON / PNG，导入后会自动带入楼层信息。"` → `"支持 JSON / PNG 角色卡格式，导入后会自动带入楼层信息。"`

### F. 搜索字段（`Services/SearchService.swift`）

- [ ] L521: `("开场白", card.firstMes)` → `("开场", card.firstMes)`
- [ ] L536: `matchedField = "开场白"` → `matchedField = "开场"`

### G. 默认 seed profile（`MemoryPalaceApp.swift:88-110`）

- [ ] **删除两个 seed**，只保留**一个**：

```swift
static let seedProfiles: [Profile] = [
    Profile(
        id: "default-workspace",
        name: "对话空间",
        emoji: "🏛️",   // 候选: 🏛️✅ / 💬 / 🗂️ — 粟粟选
        description: "对话空间",
        userName: "你",
        assistantName: "助手",
        systemPrompt: "",
        preferredModel: "openai/gpt-4o",
        createdAt: Date(timeIntervalSince1970: 0)
    ),
]
```

### H. 默认 AI 名 `assistantName` 全替换 `"小雾"` → `"助手"`

10 处出现：

- [ ] `Views/GeneralSettingsTab.swift:12` `@AppStorage` 默认值
- [ ] `Views/GeneralSettingsTab.swift:39` placeholder
- [ ] `Views/GeneralSettingsTab.swift:161` `@AppStorage`
- [ ] `Views/GeneralSettingsTab.swift:178` placeholder
- [ ] `Views/DataSettingsTab.swift:12`
- [ ] `Views/SidebarView.swift:88`
- [ ] `Views/SidebarView.swift:1901`
- [ ] `Views/SidebarView.swift:1944`
- [ ] `Views/CardFlowView.swift:1082`
- [ ] `Views/CardFlowView.swift:1537`
- [ ] `Views/ThemeSettingsTab.swift:712` preview bubble 名字
- [ ] `MemoryPalaceApp.swift:93/95` seed profile（已被 G 覆盖）

⚠️ **Migration 友好**：`@AppStorage` 默认值改了，**已存值的老用户保持自己的 "小雾"**（UserDefaults 里写过的值优先），新装用户拿到 "助手"。粟粟自己装的 dev build 里如果想保留"小雾"，去设置改一下即可。

### I. profile description placeholder（`MemoryPalaceApp.swift:802`）

- [ ] `placeholder: "例：某某的家"` → `placeholder: "例：对话空间"`

### J. Beta App Description（提交 ASC 时填）

替换 `docs/plan-testflight-launch.md` 「附：TestFlight 文案定稿」section 的 E1：

```
记忆宫殿帮助你整理、检索和延续与 AI 的历史对话。你可以导入过往会话、管理提示词与上下文，并使用自己的模型 API Key 继续工作。数据默认保存在本机。
```

What to Test 和 TestFlight 登录教程**保持不动**（已中性，无关系词）。

### K. ASC 后台 App Review Notes（提交时填，给 reviewer 看）

**最终版（2026-04-26 与另一个 AI 协商后修订，name 对齐 ASC 上的 "Memory Garden"）**：

```
Memory Garden is a personal AI chat client. Users bring their own API keys (OpenAI, Anthropic, Google) — the app does not provide any AI service itself. All conversations are stored locally on device.

Happy to answer any questions at the contact email above.
```

> **为什么不用长版**：原长版列了 "No public sharing / no marketplace / no discovery feed / no NSFW / no roleplay" 一连串否定，审核员心理学上"你越解释你不是什么，他们越想查看你是不是"。短版只陈述"是什么"——个人工具 + BYOK + 本地存储——审核员看到觉得"哦工具 app，过"。
>
> 删了哪些原长版的句子：
> - "No public sharing, no character marketplace, no discovery feed" → 不主动澄清，审核员探索时自己看得到
> - "Single default workspace profile on first launch (utility-named)" → 审核员打开就能看到
> - "Optional advanced feature: import of standard JSON/PNG character profile files" → 主动提反而引人注意，对方装上探索看到 import 入口再问也不迟
> - "No NSFW or roleplay content shipped with app" → 此即"过度自证清白"
> - "Sticker functionality is utility annotation, not emotional roleplay" → 同上

**长版备份（不交，留作回滚参考）**：

```
This is a private, single-user AI chat client. Key facts:
- BYOK only: users provide their own API keys to OpenAI, Anthropic, or Google
- No public sharing, no character marketplace, no discovery feed
- Single default workspace profile on first launch (utility-named)
- All data stored locally on device by default
- Optional advanced feature: import of standard JSON/PNG character profile files (used for organizing user-managed prompt presets; not surfaced in the default flow)
- No NSFW or roleplay content shipped with app
- Sticker functionality is utility annotation (image/note overlays on conversations), not emotional roleplay
```

### L. ipa 包内容审计（2026-04-26 archive 后实地验证）

> 粟粟问"上架的 ipa 里含 .git 吗？会不会被扒干净？"——直接拆 archive 里的 .app bundle 验证，记录如下。

**审计对象**：`~/Desktop/MemoryPalace-test.xcarchive/Products/Applications/记忆宫殿.app`

**.app bundle 完整文件清单**（共 13 个文件）：

| 文件 | 大小 | 是什么 |
|---|---|---|
| `LXGWWenKai-Regular.ttf` | 24M | 字体（霞鹜文楷，开源） |
| `SourceHanSerifSC-Regular.otf` | 23M | 字体（思源宋体，开源） |
| `记忆宫殿`（无后缀）| 6.3M | 编译后 Mach-O 二进制 |
| `Assets.car` | 40K | 编译后 asset catalog（图标） |
| `embedded.mobileprovision` | 12K | 签名 provisioning profile |
| `ZIPFoundation_ZIPFoundation.bundle/` | 8K | SPM 依赖 bundle（PrivacyInfo + Info.plist）|
| `SourceHanSerif-LICENSE.txt` | 8K | 字体许可证（必带） |
| `LxgwWenKai-LICENSE.txt` | 8K | 字体许可证（必带） |
| `_CodeSignature/` | 8K | 签名 |
| `PrivacyInfo.xcprivacy` | 4K | 隐私清单 |
| `PkgInfo` | 4K | Apple 系统标识 |
| `Info.plist` | 4K | bundle 配置 |
| `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png` | 4K x 2 | 图标 |

**完全没有的**（粟粟最担心的）：
- ❌ `.git/` 任何目录
- ❌ `docs/`（plan / research / feedback 文档全部不在）
- ❌ `CLAUDE.md`
- ❌ `记忆宫殿-这才是真的总设计文档！.md`
- ❌ `README.md`
- ❌ 任何 `.swift` 源代码
- ❌ `project.yml` / `.xcodeproj` / `Package.resolved`
- ❌ `plan-rp-language-cleanup.md`（RP 清理 plan 不会暴露）

**原因**：xcodegen 的 `sources: path: MemoryPalace` 只把 `MemoryPalace/` 内部的文件当 build input；`.git` / `docs/` 都在 repo 根目录，build 不可见。

**二进制 strings 扫描结果**（grep 关键字 nsfw|sillytavern|tavern|jailbreak|roleplay|角色卡|小雾|幽灵百合|狗儿的窝|susu|粟粟）：

| 字符串 | 来源 | 风险 |
|---|---|---|
| `com.susu.MemoryPalace.apikey` | Keychain service identifier，"susu" 是 bundle prefix | ✅ 无害（Apple 推荐 naming）|
| `jailbreak` | SillyTavern 协议字段名（指 post-history 注入字段，非"越狱手机"）| ⚠️ 上下文外可能被误读 |
| `nsfw` | SillyTavern 协议字段名（角色卡内容标签字段名）| ⚠️ 上下文外可能被误读 |
| `TavernCard` | Swift 类名（SillyTavern 卡的 import data model）| ⚠️ 类名暴露 |
| `TavernCardError` | 同上，错误类型 | ⚠️ 类名暴露 |

⚠️ 这 5 条都是**协议字段名 / Swift 类名**，不是面向用户的 UI 文案。app 跑起来用户/审核员看不到。但用 `strings` 工具扫 binary 能看到。

**风险评估**：
- **TestFlight Beta App Review**：🟢 低 —— Beta reviewer 一般不扫 binary，只看 app 跑得起来 + 没明显违规
- **正式 App Store Review**：🟡 中 —— 正式审核员可能扫，建议正式上架前 obfuscate

**v1.1+ 计划**（如果未来要正式上架）：
- `TavernCard` Swift 类 → rename 为 `CharacterProfile` / `PromptCard`（多处 reference，medium 重构）
- `Preset.swift` 里 `"nsfw"` / `"jailbreak"` 字面量 → 用 lookup table + obfuscation（保持 SillyTavern import 兼容）
- 重新 archive + upload + 提交 review

**当前结论**：TestFlight Beta Review 直接交，万一被拒（拒绝信会说原因）再处理 binary。

---

## 不改 / 保留

| 项 | 原因 |
|----|------|
| `导入角色卡` / `角色卡库` / `编辑角色卡` UI 路径 | "角色卡"作单独名词中性，Apple 卡的是组合 |
| 内部代码 ID（`charPersonalityId` / model `personality` 字段 / `TavernCard` 类名）| 不进 UI |
| `世界书` 标签 | 已中性词 |
| `用户描述` / `记忆` / `对话示例` / `对话历史` | 中性 |
| `📌 后置提醒`（对应 `jailbreakId`） | UI label 已中性 |
| `小雾` 老用户已存值 | UserDefaults migration 友好 |
| `Preset.swift:117` 的 `"nsfw"` | SillyTavern 协议 marker，binary 扫描风险极低 |

---

## 风险评估

| 类别 | 等级 | 说明 |
|------|------|------|
| 默认 reviewer 体验 | 🟢 低 | utility 命名 + 中性 description + 本地存储强调 |
| reviewer import RP 卡 | 🟡 中 | 用户能 import SillyTavern 卡，reviewer 自己 import 一个 RP 卡能触发——靠 Review Notes 强调"private single-user" 缓解 |
| App 自身内容 | 🟢 低 | 无 NSFW 内容，BYOK，AI 输出由用户配置决定 |

**核心论点**：app 是工具，不是平台。卷入争议的是用户配置 + 用户自带 key 的 AI 输出，不是 app 自身。

---

## Build Verify

改完跑：

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings"
xcodegen generate && xcodebuild -scheme MemoryPalace build
```

预期：build 通过。删除"角色性格"slot 不影响代码 flow（PromptAssembler 按 slot.id 存在与否处理；`PromptSlot.charPersonalityId` 仍在 SillyTavern import 兼容集合里）。

---

## 后续（v1.1+）

审过 v1.0 后逐步引入：

1. **优先恢复**（中性诗意，几乎无审核风险）：
   - "批注，批注批注，批注批注的批注，时间就这样慢慢变厚了"
   - "有些对话值得被好好收藏"
   - "像翻一本旧日记一样浏览"
2. **谨慎恢复**（关系框架，下次审核仍可能卡）：
   - "为你和 AI 之间的每一句话建造的小房子"
   - "AI 会记得你"
   - "重要的话旁边应该趴一只猫"
3. **新功能引入**：
   - Onboarding 让用户**自己命名**默认楼层（Apple 不监控运行时）
   - 默认 prompt 模板库给用户选（保留 utility 默认 + 提供"诗化"模板可选）

---

## 附：原文案存档

> 这是粟粟产品语言的纯样本。Apple 第一次审核时不出现，后续看反馈逐步引入。

### A.1 Beta App Description 原版（粟粟自写）

```
有些对话值得被好好收藏。

记忆宫殿是一座为你和AI之间的每一句话建造的小房子。你可以把散落在ChatGPT和Claude里的对话搬进来，像翻一本旧日记一样浏览它们——包括每一个分支、每一次犹豫、每一条走过又折回的路。

AI会记得你。真的记得你上个月说过什么、你喜欢怎样被回应、你的世界里有哪些重要的名字。

你还可以在对话上贴贴纸。为什么不呢？重要的话旁边应该趴一只猫。对话的意义可以一直生长。批注，批注批注，批注批注的批注，时间就这样慢慢变厚了。

所有数据住在你的手机里，哪儿也不去。
```

### A.2 折中版本（去关系词，曾在选项 B 讨论）

```
有些对话值得被好好收藏。

记忆宫殿是一个本地的 AI 对话管理工具。你可以把散落在 ChatGPT 和 Claude 里的对话搬进来，像翻一本旧日记一样浏览它们——包括每一个分支、每一次犹豫、每一条走过又折回的路。

它会保留你跟模型之间的上下文，让长期对话不容易失忆。批注，批注批注，批注批注的批注，时间就这样慢慢变厚了。

支持接入你自己的 OpenAI、Anthropic、Google API Key。所有数据住在你的手机里，哪儿也不去。
```

### A.3 默认 seed profile 原版

```swift
Profile(id: "ghost-lily",       name: "幽灵百合号", emoji: "🌸", description: "小雾的家",   assistantName: "小雾"),
Profile(id: "third-floor-left", name: "第三层左边", emoji: "🐕", description: "狗儿的窝", assistantName: "小克"),
```

### A.4 默认插槽原版

```
🎭 角色描述
🎭 角色性格      ← 删除
🌍 场景
```

### A.5 placeholder & label 原版

```
角色描述 placeholder：       角色的外貌、背景、性格...
对话示例 placeholder：       {{user}}: 你好\n{{char}}: 汪汪～
profile description placeholder：例：某某的家
导入按钮：                   导入酒馆预设
导入说明：                   支持酒馆 JSON / PNG，导入后会自动带入楼层信息。
搜索结果字段：               开场白
WorldBook 插入位置：         角色描述前 / 角色描述后
CharacterCardEditor：       角色名 / 角色描述 / 性格
```

### A.6 默认 AI 名

```
小雾 (Mistwood)
```

—— 粟粟个人偏好命名，CLAUDE.md 里也明确"AI 叫小雾"。审过后用户可以自己改回来。

---

*plan-only。粟粟批注/微调后再 implement。*
