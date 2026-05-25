# Research — 常用模型（E7）

> 2026-04-18。roadmap E7：「底部聊天栏的模型选择按钮只显示**常用模型**，哪些是常用在设置里配」。

---

## 一、现状

### 1.1 当前底部 model picker（`CardFlowView.ModelPickerPopover`）

- 显示 `providerManager.enabledProviders`（有 key 的）旗下**所有** model
- 按 provider 分组：`Text(provider.name)` 当小标题 + model 列表
- 点一个 → `selectedChatModel` = `"{providerId}/{modelId}"`

**问题**：每个 provider 拉完 `/models` 端点后几十上百个 model（SiliconFlow / OpenRouter 更多），列表拉到底找得崩溃。

### 1.2 现在还没有"收藏"概念

- `APIProvider.models: [ProviderModel]` 是 provider 维度的全量
- `selectedChatModel`（AppStorage）只记"当前在用"
- `provider.lastUsedModelId`（本轮做的）记每个 provider 上次用的
- **没有"用户收藏 / 常用"标识**

### 1.3 API 设置页的模型列表（`modelListContent`）

- 展示 `providerManager.providers[effective].models`
- 搜索框、分组（按 vendor 前缀）、点选切 `selectedChatModel`
- 每行 model 展示 name + modelId；选中有薄荷背景 + 勾
- **没有收藏按钮**

---

## 二、目标

1. **底部聊天栏 picker** 只显示用户收藏的模型
2. **收藏/取消收藏**在"哪个位置操作"要粟粟定
3. 数据跨 provider（可以同时收藏 Anthropic 官方的 opus-4-7 和 OpenRouter 的 claude-opus-4-6）

---

## 三、设计决策点

### 3.1 收藏配置 UI 放哪

| 选项 | 描述 |
|------|------|
| **A. API 设置页的模型列表，每行加星星**✅ | 现成列表上贴个星；点一下 toggle 收藏；已收藏金黄色/薄荷填充 |
| B. 独立"常用模型" section 或 tab | 多一层菜单 |
| C. 长按 ModelPickerPopover 里某条 → 出菜单「从常用里取消」（但这是反向：不能先添加）| 不适合初次配置 |
| D. ModelPickerPopover 里每行加星星，能在选模型同时收藏 | 两个用法混一起，按钮多 |

**我推荐 A**。现成列表 + 星星，操作路径最短。

### 3.2 底部 picker 没收藏任何模型时显示啥

| 选项 | 描述 |
|------|------|
| **A. 显示全部（和现在一样）+ 顶部小字提示"在 API 设置里加星收藏常用模型"**✅ | 新用户不被挡路 |
| B. 空列表 + 大字"请先到 API 设置收藏常用模型" | 强引导但可能卡 |
| C. 自动把 `availableModels.first` 或 provider.lastUsedModelId 视为默认收藏 | 隐式魔法 |

**我推荐 A**。新用户或者从没收藏过的，不要挡路。

### 3.3 收藏分组显示

底部 picker 里收藏的 models 怎么组织？

| 选项 | 描述 |
|------|------|
| **A. 按 provider 分组（和现在一样的结构，只是条目少）**✅ | 和现有风格一致 |
| B. 不分组，一个平铺列表按收藏时间 | 快速切换最方便 |
| C. 两个 tab：常用 / 全部 | 多一层 |

**我推荐 A**。保持视觉一致。

### 3.4 数据落盘位置

| 选项 | 描述 |
|------|------|
| **A. `@AppStorage("favoriteModels")` 存 `[String]`（model.id = "providerId/modelId"）** | 不动 APIProvider schema，独立 key |
| B. `ProviderModel` 加 `isFavorite: Bool` | 要改 APIProvider 的 models 结构，Codable 全套升级 |
| C. `ProviderManager` 内存维护 + 单独 UserDefaults 序列化 | 和 A 等价，写法不同 |

**我推荐 A**。最小改动，和 `selectedChatModel` 对等风格。需要注意 `[String]` @AppStorage 要 JSON encode/decode（Swift 的 @AppStorage 原生不直接支 array；要么用自定义 wrapper，要么存 JSON string）。

### 3.5 失效清理

用户删了 provider、改了 baseURL 重拉 models → 收藏列表可能指向已不存在的 modelId。

| 选项 | 描述 |
|------|------|
| **A. 启动时 resolve，过滤掉不存在的（跟 selectedChatModel 同套路）** | 自动自愈 |
| B. 不清理，picker 里查 model(byId) nil 就不显示这条 | 懒清理 |
| C. 改 provider / 删 model 时同步清 | 多入口都要挂钩 |

**我推荐 A**（启动时扫一次）+ B 兜底（picker 渲染时即时过滤）。

---

## 四、要改的地方

| 文件 | 改动 |
|------|------|
| `Models/APIProvider.swift` | `ProviderManager` 加 `favoriteModels: [String]` 持久化 + `toggleFavorite / isFavorite / resolveStaleFavorites` 方法 |
| `Views/APISettingsTab.swift` | `apiModelRow` 加星星 icon 按钮；点击 toggle 收藏（不走 model 选中） |
| `Views/CardFlowView.swift`（ModelPickerPopover）| 数据源从 `enabledProviders.models` 改为 `favoriteProviders()` / 或过滤出收藏；加空状态提示 |
| `MemoryPalaceApp.swift` 或 ContentView | 启动 resolveStaleFavorites 调用 |

---

## 五、风险 / 边界

1. **@AppStorage [String]** — 需自定义 encode/decode。用 RawRepresentable adapter 或存 JSON string 或直接用 UserDefaults + @Observable 的 ProviderManager 管。后者简单，和 customProviders 同套路
2. **已收藏但 provider 没 key** — picker 里该显示吗？我倾向不显示（无法用）。需要 UI 提示 "已收藏但未配 key"？这轮先不做，简单过滤掉
3. **收藏动作触发 UI 刷新** — @Observable ProviderManager 改字段就触发
4. **iOS ModelPickerPopover 是 sheet，macOS 是 popover** —— 一视同仁
5. **星星样式**：SF Symbol `star` / `star.fill`，颜色用 `Theme.favorite` (金黄) 还是 `Theme.branchIndicator`（薄荷绿）？favorite 已经用在对话收藏星了，和这里冲突吗？—— 不冲突（语义一致：收藏），用 favorite 金黄色

---

## 六、问粟粟的点

1. **配置位置**（§3.1）：A API 模型列表加星（推荐）/ B 独立 tab / C 长按菜单 / D ModelPicker 里每行加星？
2. **空收藏时底部 picker**（§3.2）：A 显示全部 + 顶提示（推荐）/ B 空 + 强引导 / C 自动收藏第一个？
3. **分组方式**（§3.3）：A 按 provider 分组（推荐）/ B 平铺 / C 双 tab？
4. **数据位置**（§3.4）：A 独立 favoriteModels 列表（推荐）/ B 给 ProviderModel 加字段 /其他？
5. **星星颜色**：A 金黄色 `Theme.favorite`（和对话收藏同色，语义一致）/ B 薄荷绿 `branchIndicator`（和其他交互同色）？

我的默认推荐：A / A / A / A / A。✅

---

*粟粟批完我写 plan。*
