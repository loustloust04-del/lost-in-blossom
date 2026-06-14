# Plan：S4 对话删除同步（墓碑机制）

日期：2026-06-13
前置：`research-sync-deletion.md`
决策（粟粟已拍）：① 只做对话级，节点级 backlog　② 墓碑缓冲 90 天　③ 永久删赢

## 设计总览

删除分两条路，分别对应「可恢复」和「不可逆」：

```
软删除（进回收站）  → 状态同步，走 LWW（updateTime 新者赢）→ 对端也进回收站，可恢复
永久删除（彻底删）  → 墓碑文档，无条件优先 → 对端永久删本地+附件，不可逆
```

```text
sync/{pid}/conversations/{convId}.json   ← 软删对话照常在这（带 isDeleted=true）
sync/{pid}/tombstones/{convId}.json      ← 永久删的墓碑（convId+deletedAt），90 天后清
```

## 关键改动点

### 1. 文档结构（零迁移：Codable optional 默认值）
- `ConversationDocument` 加 `isDeleted: Bool = false` / `deletedAt: Date? = nil`
- 新 `TombstoneDocument { schemaVersion, convId, profileId, deletedAt }`

### 2. 导出侧
- **softDeleteConversation 补碰 updateTime**（ViewModel:1121）——当前漏了，不碰则 LWW 不传播
  - restoreConversation 同样补碰 updateTime（恢复也要传播）
- **导出器去掉 `isDeleted == false` 过滤**（SyncStore:208）——软删对话照常导出，带 isDeleted 字段
- **内容去重加 isDeleted 判据**（SyncStore:251 那段）——软删状态变化要能触发重导出，否则去重把它吞了
- **永久删写墓碑**：permanentlyDeleteConversation（ViewModel:1135）调新方法
  `SyncStore.recordPermanentDeletion(convId:profileId:)`：
  - 检查 isEnabled（本地模式/同步关 → 不写）
  - 写 tombstones/{convId}.json
  - 删 conversations/{convId}.json（光删不够，但配合墓碑防复活）
  - 清本机 export/import 指纹里该 conv 记录

### 3. 导入侧（importAll 开头先处理墓碑，再合并文档）
- **先扫 tombstones/**：每个墓碑 → 本地有该 conv 就永久删（context.delete + 节点 + 附件 + 清指纹）
  - **无条件执行 = 永久删赢**：即使本地副本 updateTime 比墓碑 deletedAt 新（对端恢复过），墓碑照删
- **对话 LWW 含软删状态**：文档 updateTime 新 → 更新 existing.isDeleted/deletedAt（现有 LWW 分支里加两行）
- **墓碑缓冲清理**：顺扫 tombstones，deletedAt 距今 > 90 天 → 删墓碑文件（防无限堆积，又保证慢设备能收到）

## 赛跑语义验证（永久删赢）

| 时序 | 结果 |
|------|------|
| A 软删 → B 进回收站 | ✅ LWW 传播 |
| A 软删 → B 恢复 → 同步 → A 也恢复 | ✅ LWW（B 的 updateTime 新） |
| A 软删 → B 恢复 → A 永久删 | ✅ 墓碑无条件，两端都永久删（永久删赢） |
| 墓碑 > 90 天，慢设备才上线 | 墓碑已清 → 该设备副本存活（缓冲期设计意图，可接受） |

## Checklist

### 数据结构
- [ ] T1 ConversationDocument 加 isDeleted/deletedAt（optional 默认值）
- [ ] T2 定义 TombstoneDocument + tombstones 目录 helper（syncRoot 同级）

### 导出侧
- [ ] T3 softDeleteConversation + restoreConversation 补 `updateTime = Date()`
- [ ] T4 导出器 fetch 去掉 isDeleted==false 过滤；文档带 isDeleted/deletedAt
- [ ] T5 内容去重判据加 isDeleted（状态变化不被去重吞掉）
- [ ] T6 SyncStore.recordPermanentDeletion（写墓碑+删云文档+清指纹，含 isEnabled 守卫）
- [ ] T7 permanentlyDeleteConversation 调 T6

### 导入侧
- [ ] T8 importAll 开头扫 tombstones → 无条件永久删本地（节点+附件+指纹）
- [ ] T9 对话 LWW 分支加 isDeleted/deletedAt 更新
- [ ] T10 墓碑 90 天缓冲清理

### 验证
- [ ] T11 测试：软删传播 / 恢复传播 / 永久删墓碑 / 赛跑(永久删赢) / 墓碑过期清理
- [ ] T12 双端实测：Mac 删对话 → 手机进回收站；Mac 清空回收站 → 手机也没了
- [ ] T13 build 双端 + 部署 Mac+口罩机 + 探针确认无新循环

## 边界与风险

1. **首次去过滤 churn**：回收站历史软删对话全量导出一次（一次性，可接受）
2. **墓碑触发的本地永久删要删附件**：与本地 permanentlyDeleteConversation 对齐（调 AttachmentStore.deleteConversationAttachments）
3. **永久删时同步没开**：不写墓碑（之后开同步该删除丢失，acceptable——没开就不同步）
4. **墓碑写入失败**：尽力而为，光删云文档可能导致对端复活——但下次本端永久删的对话已不在 SwiftData，不会重导出；对端复活的副本下次本端不会再发墓碑（已删）→ 边界遗留，概率低，记 backlog
5. **回环抑制**：导入软删后指纹记文档 updateTime，不回声导出（现有机制覆盖）

## 不在本次范围（backlog）
- 节点级删除（软删+永久删）——架构张力需开「已有节点 LWW 口子」，单独评估
- 墓碑写入失败的最终一致性兜底

**DON'T IMPLEMENT YET — 等粟粟批注**
