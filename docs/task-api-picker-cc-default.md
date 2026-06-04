# "当前使用的 API" 加空选项 → CC + 收藏模型

> Bunny 的需求：提供商选了 CC 后，"当前使用的 API" 里没有 CC 可选。
> 加一个默认空选项，选了它之后聊天页显示 CC 本地模型 + 收藏模型。
> ⚠️ OR 收藏模型功能不要改坏。

---

## 现状问题

- "当前使用的 API" Picker 数据源是 `pm.savedAPIProviders`
- `savedAPIProviders` 只返回 `hasKey` 的 provider（`providers.filter { hasKey(for: $0.id) }`）
- CC 是本地的不需要 API key → 不在列表里 → 选不到
- 聊天页的模型列表根据 `selectedChatModelId`（格式 `providerId/modelId`）决定显示哪个 provider 的模型

## 需求

1. "当前使用的 API" Picker 里始终有一个空/默认选项（比如"（默认）"或空白）
2. 选了这个空选项后，聊天页的模型选择器显示：CC 本地模型 + 所有 provider 的收藏模型
3. **OR 收藏模型功能保持不变** — 当选了 OR 作为当前 API 时，模型列表显示收藏的 OR 模型，这个逻辑不碰

## 涉及文件

### 1. `APISettingsTab.swift` — Picker UI

位置：`activeAPIPickerContent`（约 251 行）

现在的逻辑：
```swift
Picker("", selection: binding) {
    ForEach(pm.savedAPIProviders, id: \.id) { p in
        Text(p.name).tag(p.id)
    }
    // 占位 tag（只在 activeProviderId 不匹配时显示）
    if !pm.savedAPIProviders.contains(where: { $0.id == activeProviderId }) {
        Text("（未选择）").tag("")
    }
}
```

改为：
```swift
Picker("", selection: binding) {
    // 默认/空选项 — 始终可选
    Text("（默认）").tag("")

    ForEach(pm.savedAPIProviders, id: \.id) { p in
        Text(p.name).tag(p.id)
    }
}
```

binding 的 set 里去掉 `!newId.isEmpty` 的检查：
```swift
set: { newId in
    if newId != activeProviderId {
        if newId.isEmpty {
            // 选了空选项 → 清除 selectedChatModelId，让聊天页回退到 CC + 收藏
            selectedChatModelId = ""
            apiSelectedProviderId = ""
        } else {
            handleUseProvider(newId)
        }
    }
}
```

### 2. 聊天页模型列表 — 当 `selectedChatModelId` 为空时

⚠️ 这是最关键的改动。需要找到聊天页模型选择器的数据源。

当 `selectedChatModelId == ""` 时，模型列表应该返回：
- CC provider（`APIProvider.ccBridge`）的模型
- 所有 provider 的收藏模型（`favoritesByProvider` 或 `favoriteModelIds` 过滤后的列表）

具体位置需要猫在聊天页的模型 Picker / Sheet 里找。可能在 `ChatView.swift` 或 `ModelPickerView.swift` 或类似文件。

逻辑伪代码：
```
if activeProviderId.isEmpty {
    models = ccBridge.models + allFavoriteModels
} else {
    models = currentProvider.models  // 现有逻辑不变
}
```

### 3. ProviderManager — 可能不需要改

`savedAPIProviders` 的过滤逻辑不动。CC 不需要出现在 saved 列表里。空选项在 Picker 层面解决，不在数据层。

---

## ⚠️ 不要碰的东西

- `savedAPIProviders` 的过滤逻辑
- OR 收藏模型的显示逻辑 — 当选了 OR 时，模型列表只显示收藏的 OR 模型，这个行为保持
- `favoriteModelIds` 的存储和读取
- `handleUseProvider` 的现有逻辑（选了非空 provider 时的行为）

---

## 测试

1. 设置页选 CC 提供商 → "当前使用的 API" 里应该能看到"（默认）"选项
2. 选"（默认）" → 聊天页模型选择器应该显示 CC 模型 + 收藏的 OR/DS 模型
3. 切回 OR → 聊天页应该只显示 OR 的收藏模型（验证收藏功能没被改坏）
4. 切回"（默认）" → 确认能正常切换
