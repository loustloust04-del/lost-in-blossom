# Research — API 保存/管理列表

> 2026-04-18。粟粟诉求：保存一个 API 后它**躺在列表里**；默认名字是时间戳到分钟；可以改别称；想用就用。

---

## 一、当前状态（事实）

### 1.1 "保存"现在做了什么

| 场景 | 实际发生 |
|------|----------|
| 内置 provider（如 openrouter）输入 key 点保存 | Keychain 写入 `apikey-openrouter` |
| 选择"自定义 OpenAI 兼容"填 name/URL/key 点保存 | 创建 `APIProvider(id: "custom-<uuid8>", name:..., baseURL:...)` 存 UserDefaults `customProviders`，key 写 Keychain |
| 选中已存 custom provider 修改 name/URL 点保存 | `updateProvider` = 按 id 替换 custom providers 列表 |

**保存后的可见性**：该 provider 出现在 picker 下拉菜单里 — 仅此而已。没有独立列表，没有"我已经存了几个"的感知，没有最近使用时间。

### 1.2 "切换使用"现在怎么发生

- 底部对话 bar 的模型按钮（`CardFlowView.ChatInputBar`）选 model
- `@AppStorage("selectedChatModel")` 存 `"{providerId}/{modelId}"`
- `ChatService` 按 model 回查 provider 拿 key 和 baseURL

**没有"选这个 API"的概念**，只有"选这个模型"。模型自带 provider 归属。

### 1.3 现有 APIProvider 字段

```swift
struct APIProvider {
    let id: String
    var name: String
    var type: ProviderType
    var baseURL: String
    var extraHeaders: [String: String]
    var models: [ProviderModel]
    var isBuiltIn: Bool
}
```

**缺**：`createdAt`、`lastUsedAt`（用于"最近用过"排序 / 默认命名）。

### 1.4 默认命名现状

`saveCustomProvider()` 里：`name.isEmpty ? url : name` — 用户不填时用 URL 当名字，看起来像 `https://api.example.com/v1`。丑。

---

## 二、粟粟需求拆解

> "保存一个 API，然后它就躺在列表里，默认名字是时间戳到分钟，我可以改它的别称，然后想用的时候用就是了"

| 关键词 | 我理解的意思 | 要澄清 |
|--------|------------|--------|
| **列表** | 一个**显式**的视图区域列出所有已存 API，不只靠 picker 下拉 | 列表范围：只 custom？还是含内置有 key 的？ |
| **默认名字时间戳到分钟** | 保存时 name 若空 → 自动填 `"2026-04-18 05:42"` | 是否所有"保存"都如此，还是只 custom 新建？ |
| **改别称** | 列表里 inline 改名或卡片上点编辑 | 改完立刻生效 |
| **想用就用** | 列表点一下就"切到这个 API" | "切到"的含义是什么？见下 |

---

## 三、设计决策点（等粟粟确认）

### 3.1 "列表"的范围

| 选项 | 描述 | 优劣 |
|------|------|------|
| **A. 只列 custom provider** | 内置 provider 继续靠 picker，列表纯粹是"我的收藏/中转站" | 概念最清晰，内置不占版面 |
| **B. 所有有 key 的 provider** | 内置 + custom 一起列，按"已激活"视角 | 一眼看见全貌，但内置原本名字固定，"改名"怪怪的 |
| **C. 两层**：上面内置（带 key 绿点），下面"我的 custom" | 像 SillyTavern 的 API 页 | 清晰但重 |

**我建议 A**。内置 provider 名字是品牌（OpenAI/Anthropic），不需要别称；custom 中转站/代理才真需要管理。

### 3.2 "使用"的语义

列表里点一个 API → 会发生什么？

| 选项 | 描述 |
|------|------|
| **A. 只切 picker 选中**（不动 `selectedChatModel`）| 仅让 API 页当前编辑指向这个 provider；对话 bar 模型不变 |
| **B. 切 picker + 自动选第一个 model** | 对话立即用这个 API 的第一个可用模型 |
| **C. 切 picker + 记忆"该 API 上次用过的模型"** | 每个 provider 记 lastUsedModelId，点"使用"恢复 |
| **D. 没有"使用"按钮**，只作展示管理 | 切换仍靠底部 bar 的模型 picker |

我倾向 **C**。"想用就用"更接近"一键切整个 API"——但用户上次在这个 API 选过的模型最自然。需要加 `lastUsedModelId: String?`。

### 3.3 默认命名时机

| 选项 | 时机 |
|------|------|
| **A. 保存时 name 为空就填 `"2026-04-18 05:42"`** | 用户没填则后备 |
| **B. 一进入"自定义"就把 name 字段预填时间戳** | 用户看到就能改，不填也有值 |
| **C. 两者都做** | 预填可改，留空再后备 |

我建议 **B**。进入 custom 表单 name 已经填好时间戳，用户想改随时改、不改保存也行，心理成本低。

### 3.4 列表在 API 页的位置

| 选项 | 布局 |
|------|------|
| **A. Picker 下方新增「已保存 API」section** | 保持单页；卡片形式列 custom |
| **B. 独立的子页（iOS push/macOS 切页）** | 列表独立一页，点条目进详情 |
| **C. 把 picker 干掉，整个 API 页变成列表** | 内置也排在列表里，"+" 新建 custom；选中后展开详情编辑 |

我建议 **A**。最小破坏，用户习惯 picker 保留；列表作为补充。

### 3.5 改名交互

| 选项 | 描述 |
|------|------|
| **A. 列表卡片里 inline TextField**（点一下就可编辑，失焦保存）| 轻量 |
| **B. 长按/右键弹菜单「重命名」**（macOS 右键、iOS 长按）| 传统 |
| **C. 点铅笔图标进 sheet 编辑** | 明显但多一步 |

建议 **A**，省事。不想改的时候 TextField 也就是一个 label 样子。

---

## 四、要改的地方预估

| 文件 | 改动 |
|------|------|
| `Models/APIProvider.swift` | `APIProvider` 加 `createdAt: Date`、`lastUsedModelId: String?`（视 3.2 决策）；编码兼容老数据（Codable 加默认值）|
| `Views/APISettingsTab.swift` | 新建 section/区域展示列表卡片；custom 表单 name 默认填时间戳；保存逻辑补字段 |
| `Views/CardFlowView.swift`（`ChatInputBar`）| 模型切换时更新 provider.lastUsedModelId（如选 3.2-C）|
| `ChatService.swift` | 发消息后可能要 touch lastUsedAt（如需要"最近使用"排序）|

**不改**：ProviderManager 基础能力（addProvider/removeProvider 已够），Keychain 层，ChatService 协议层。

---

## 五、风险 / 边界

1. **老数据兼容**：`APIProvider` 是 Codable 存 UserDefaults，加字段要有默认值（`createdAt = Date()` decode fallback）。否则老用户升级就炸
2. **用户"改名"后同一 API 如果指向失效**：改名不改 id，安全
3. **lastUsedModelId 指向不存在模型**：同"死链清除"逻辑，resolve 时 fallback 到该 provider 第一个 model
4. **内置 provider 不在列表里**（选 A）会让"刚输了 openrouter key 的人"疑惑"它在哪？"——需要文案提示："内置 provider 在上方 picker 里"
5. **时间戳本地化**：`2026-04-18 05:42` 就用简洁 ISO-like 格式，别上 `DateFormatter().locale`，保证稳定

---

## 六、问粟粟的点（请在下方批注）

1. **列表范围**（§3.1）：只列 custom（A）、全部有 key（B）、两层（C）？【你是在说对话框下面的那个模型选择器吗？是的，那个就是用户放常用模型的地方。我刚刚要求你的是API管理，这个是模型选择管理？虽然有重合但是不太一样。】
2. **"使用"含义**（§3.2）：不动模型只切编辑（A）、切模型到第一个（B）、切到该 API 上次用过的模型（C）、没这按钮（D）？【c】
3. **默认命名时机**（§3.3）：保存时兜底（A）、进表单就预填（B）、两者都（C）？【c】
4. **列表位置**（§3.4）：picker 下方 section（A）、独立子页（B）、干掉 picker 全变列表（C）？【你到底在说哪个列表？1，API的列表就放在API设置里啊，这是和API管理一伙的。｜模型的列表现在不是已经有了自动拉取。｜模型选择器的编辑列表在API设置，模型选择器本身在聊天栏。
5. **改名交互**（§3.5）：inline TextField（A）、长按菜单（B）、铅笔按钮（C）？【bc】
6. **要不要最近使用时间**（`lastUsedAt`）？排序用，我没列但顺嘴问一下。【要，还要额度上限限制（用钱算，超额掐停以防用户因为我们app的不成熟烧钱。不是单次最大回复token，这个先预估，复杂分词器弄好之后弄具体的）】

我的默认建议：A / C / B / A / A / 要。

---

*粟粟批完我再写 plan。*
