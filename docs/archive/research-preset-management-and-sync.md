# Research: 预设管理 + 跨设备同步

> 2026-04-12，第一性原理分析

## 一、预设管理

### 预设是什么

一个配置包：`prompts[]` + `SamplingParams` + 格式模板（characterFormat / personaFormat / scenarioFormat）。是"AI 的性格菜谱"。

### 用户真正需要什么

- **安全实验** — 改坏了能回去
- **分享** — 导出给别人 / 从社区导入
- **组织** — 多个预设快速切换

### 当前状态

| 能力 | 状态 | 说明 |
|------|------|------|
| 导入酒馆 JSON | ✅ | `Preset.fromSillyTavernJSON()` |
| 删除 | ✅ | 内置不可删 |
| 热编辑 | ✅ | 改了立刻写 `preset.prompts[]`，无保存键 |
| 复制/另存为 | ❌ | |
| 重命名 | ❌ | |
| 导出 | ❌ | `toSillyTavernJSON()` 已有代码，没 UI |
| 撤销/回滚 | ❌ | |

### 核心矛盾

热编辑 + 没有撤销 = 改坏了没法回去。

### 检查点方案对比

| 方案 | 复杂度 | 体验 | 结论 |
|------|--------|------|------|
| A. 手动检查点 — "复制一份再改" | 低 | 够用，用户要自己记得 | **先做这个** |
| B. 自动快照 — 每次打开时存一份 | 中 | 像 Time Machine | 后续 |
| C. 完整版本历史 | 高 | Git 式 diff + revert | 不需要 |

**结论**：复制 + 重命名 + 导出 = 手动检查点。复制一份叫"实验版"，改坏了删掉回到原版。

### 预设管理 MVP（本次实现）

酒馆的基础预设管理就三个操作：
1. **保存为新预设**（当前预设另存为，新名字新 ID）
2. **复制预设**（等同于另存为）
3. **重命名预设**

加上已有的导入和删除，总共 5 个操作：

| 操作 | 当前 | 实现 |
|------|------|------|
| 导入 | ✅ NSOpenPanel | 不动 |
| 删除 | ✅ 垃圾桶按钮 | 不动 |
| 复制 | ❌ | 预设 Picker 旁加按钮 |
| 重命名 | ❌ | 双击预设名 / 小编辑按钮 |
| 导出 | ❌ | 预设 Picker 旁加按钮，NSSavePanel |

### UI 方案

不搞二级界面，直接在预设 Picker 旁加操作按钮：

```
预设 [平衡 ▾] [📋复制] [✏️重命名] [📤导出] [🗑️删除]     简单 插槽 JSON 组装 请求
```

## 二、跨设备同步

### 需要同步什么

| 数据 | 大小 | 敏感 | 同步难度 |
|------|------|------|---------|
| 预设 (Preset) | 小 (~100KB/个) | 否 | 低 |
| 楼层配置 (Profile) | 小 (~1KB/个) | 否 | 低 |
| API Key | 小 | **高** | 中 — Keychain 同步 |
| 记忆 (Memory) | 中 (~几 MB) | 中 | 中 — SwiftData CloudKit |
| 对话 (MessageNode) | **大 (200k+)** | 中 | 中-高 — 需架构改动 |

### 做到大规模消息同步的 app

| App | 方案 | 规模 |
|-----|------|------|
| iMessage | CloudKit (NSPersistentCloudKitContainer) | 百万条消息 |
| Apple Notes | CloudKit + Core Data | 大量笔记 |
| Bear / Day One | CloudKit | 笔记/日记同步 |
| Obsidian | iCloud Drive 文件级同步 | 数千文件 |
| Telegram | 服务端存储，设备只是视图 | 无限 |
| ChatGPT 官方 | 服务端 | 所有对话 |

### 关键发现：SwiftData 原生支持 CloudKit

Apple 提供了 `NSPersistentCloudKitContainer`：
1. 开启 CloudKit capability
2. SwiftData store 配置改一行
3. Apple 自动处理增量同步 + 冲突解决

200k 条 MessageNode 不是不可能同步 — iMessage 就是这么干的。

### 我们的架构难点

| 问题 | 说明 | 解法 |
|------|------|------|
| 多 store | 每个楼层独立 `.store` 文件 | 改成单 store + profileId 过滤 |
| Apple Developer | 需要付费账号 + CloudKit container | 注册 |
| 首次同步 | 200k 首次同步慢 | 只需一次，后续增量 |
| 冲突策略 | 消息是 append-only | last-writer-wins 够了 |

### 分层实施路线

| 阶段 | 内容 | 难度 | 依赖 |
|------|------|------|------|
| Phase 0 | 预设手动导入/导出 | ✅ 已完成 | 无 |
| Phase 1 | 预设 + Profile iCloud 文件同步 | 低 | Apple Developer 账号 |
| Phase 2 | 记忆 CloudKit 同步 | 中 | Phase 1 |
| Phase 3 | 对话 CloudKit 同步 | 中-高 | 多 store → 单 store 架构重构 |

### Phase 3 的关键决策

对话同步需要把"每楼层一个 .store"改成"单 store + profileId"。这是架构改动：

```
之前：
  ~/Library/Application Support/MemoryPalace/profile-1.store
  ~/Library/Application Support/MemoryPalace/profile-2.store

之后：
  单个 CloudKit-enabled store
  MessageNode 加 profileId 字段
  查询时用 #Predicate { $0.profileId == currentProfileId }
```

好处：CloudKit 只需配一个 container。
代价：迁移脚本 + 性能验证（200k 条单 store 是否影响查询速度）。

## 三、本次执行计划

先做预设管理 MVP（复制 / 重命名 / 导出），不碰同步。
