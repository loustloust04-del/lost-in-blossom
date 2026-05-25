# Plan — 常用模型（E7）

> 2026-04-18。基于 research-api-favorite-models.md，粟粟批注 AAAAAA。

## 目标

底部聊天栏 model picker 只列出用户在 API 设置里打星的模型；全量模型仍在 API 设置页可见可收藏。

## 粟粟已定

| 项 | 决策 |
|----|------|
| 配置位置 | A — API 设置页模型列表每行加星 |
| 空收藏时底部 picker | A — 显示全部 + 顶部小字提示 |
| 分组 | A — 按 provider 分组 |
| 数据位置 | A — 独立 `favoriteModels: [String]`，不动 ProviderModel schema |
| 星星颜色 | A — 金黄 `Theme.favorite` |

---

## 数据模型

**新增 UserDefaults key**：`favoriteModels` — JSON 编码的 `[String]`，元素是 `"providerId/modelId"`。

**`ProviderManager` 新增**：

```swift
private(set) var favoriteModelIds: [String]   // 内存态，启动时从 UserDefaults 解

func isFavoriteModel(id: String) -> Bool
func toggleFavoriteModel(id: String)          // 添加/移除 + 写盘
func resolveStaleFavorites()                  // 启动时过滤不存在的

var favoritesByProvider: [(APIProvider, [ProviderModel])] {
    // 返回按 provider 分组的收藏 models（用于 ModelPickerPopover）
}
```

**持久化**：和 customProviders 同套路，用 `UserDefaults.standard.data(forKey:)` + JSONEncoder。

---

## 文件变动清单

| 文件 | 改动 |
|------|------|
| `Models/APIProvider.swift` | `ProviderManager` 加 `favoriteModelIds` + 4 个方法 + 持久化 |
| `Views/APISettingsTab.swift` | `apiModelRow` 加星星按钮；点星只 toggle 收藏，不触发 model 选中 |
| `Views/CardFlowView.swift` | `ModelPickerPopover` 改用 `favoritesByProvider`；空态显示全部 + 顶提示 |
| `MemoryPalaceApp.swift` 或 ContentView | 启动触发 `resolveStaleFavorites`（复用现有 onAppear）|

**不改**：ChatService / ConversationViewModel / Budget 层。

---

## 实施步骤 & Checklist

### Phase A：数据层

- [ ] **A1** `ProviderManager` 加 `private(set) var favoriteModelIds: [String] = []`
- [ ] **A2** 加持久化 key `favoriteModelsKey = "favoriteModels"` 和 `load/save` helpers（JSON）
- [ ] **A3** `init()` 里 `favoriteModelIds = loadFavoriteModels()`
- [ ] **A4** `isFavoriteModel(id:) -> Bool`
- [ ] **A5** `toggleFavoriteModel(id:)`：有则删无则加，写盘
- [ ] **A6** `resolveStaleFavorites()`：过滤 `model(byId:) != nil` 的，有变化才写盘
- [ ] **A7** `favoritesByProvider: [(APIProvider, [ProviderModel])]`：遍历 favoriteModelIds → group by providerId → 保留有 key 的 provider，按 provider 在 providers 数组里的顺序排
- [ ] **A8** macOS build

### Phase B：API 设置页模型列表加星

- [ ] **B1** `apiModelRow` 里 Spacer 后面加星星按钮：
  - `Image(systemName: isFav ? "star.fill" : "star")`
  - color：isFav ? `Theme.favorite` : `Theme.textMuted.opacity(0.4)`
  - 点击 toggleFavoriteModel；**阻止事件冒泡到 row 的选中 Button**（用 `PlainButtonStyle` + `.contentShape` 精确命中）
- [ ] **B2** 星星按钮放 `checkmark` 勾之前（或之后），用 `.frame(width:, height:)` 给固定 hit area
- [ ] **B3** macOS + iOS build

### Phase C：ModelPickerPopover 只显示收藏

- [ ] **C1** `ModelPickerPopover` body 里换数据源：
  - 从 `providerManager.favoritesByProvider`
  - 如果为空 → fallback 显示 `enabledProviders` 全部 + 顶部小字提示
- [ ] **C2** 加 `@State private var hasAnyFavorite` 或 computed，决定走哪个分支
- [ ] **C3** 空态提示 row：
  ```
  在 API 设置的模型列表点 ★ 收藏常用模型，这里就只显示它们
  ```
  小字灰色 + 星星 icon，不可点击
- [ ] **C4** iOS 和 macOS 表现一致

### Phase D：启动清理

- [ ] **D1** `ChatInputBar.onAppear` 已有 `resolveStaleSelectedModel()`；在后面加 `providerManager.resolveStaleFavorites()`
- [ ] **D2** build 验证

### Phase E：收尾

- [ ] **E1** 通读 diff
- [ ] **E2** macOS build
- [ ] **E3** iOS build
- [ ] **E4** 手动测试：
  - [ ] API 设置页给几个 model 打星 → 底部 picker 只显示这些
  - [ ] 取消所有收藏 → 底部 picker 显示全部 + 顶提示
  - [ ] 删一个 provider（custom）→ 它的收藏 models 启动后消失
- [ ] **E5** commit（按 Phase 拆或合并）：
  1. `feat: ProviderManager 加常用模型（favoriteModelIds）管理`
  2. `feat: API 设置页模型列表每行加收藏星`
  3. `feat: ChatInputBar model picker 只显示收藏模型`
  4. `docs: research + plan for 常用模型 E7`
- [ ] **E6** git push

---

## 风险速查

| 风险 | 缓解 |
|------|------|
| 星星点击触发 model 选中 | Button + `.buttonStyle(.plain)` + 在 `Button(action: ...)` 外部，避免嵌套在 model row 的 Button 里 |
| @Observable 字段变化不刷 UI | `private(set) var favoriteModelIds` 直接赋值应该触发；用 assign-new-array 不要 mutate in place |
| 收藏的 provider 没 key | `favoritesByProvider` 里 filter 掉 `hasKey == false` 的条目 |
| 老用户首次升级没收藏 → 底部空 | 正是 Phase C 的空态提示兜底：显示全部 + 小字 |

---

## 不做清单

- 收藏排序（按收藏时间/手动拖拽）
- 多设备同步收藏（跟 iCloud Keychain 开关风格联动？—— 下轮再说）
- 按模型类型过滤（chat/embedding 等）

---

*粟粟批 OK 我就进 Phase A。*
