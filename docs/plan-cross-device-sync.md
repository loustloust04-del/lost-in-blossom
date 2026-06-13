# Plan：跨设备同步 — 文件态同步层（S1 导出 + S2 导入合并）

日期：2026-06-13  
Research：`research-cross-device-sync.md`（方案 C 已批：体积✅ / 墓碑+回收站✅ / 单楼层试点✅）

## 总设计

```text
sync/{profileId}/conversations/{convId}.json     ← 每对话一文档（对话元数据 + 全部 nodes）
sync/{profileId}/.export-state.json              ← 本机导出指纹（convId → 已导出 updateTime）
```

- 同步根 = iCloud 容器 Documents/sync/（复用刀1 容器；容器不可用 → 同步暂停亮状态）
- **单楼层试点**：开关按楼层存（`syncEnabledProfiles` 集合），设置页只对当前楼层开关
- **互斥**：本地模式 ON → 同步模式强制禁用
- v1 永不删除（S4 墓碑再说）；iCloud 冲突副本文档照常被扫到并集合并（天然幂等，越合越全）

## 合并语义（核心，测试钉死）

- 对话元数据：updateTime 新者赢（LWW）
- nodes：**只插本地缺失的 id，绝不重插已有 id**（unique=upsert 教训：重插会改写本地状态）；
  已有 parent 的 childrenIds 与文档版取并集（分支两端共存）
- segmentsData 附件 ref：跨设备解析依赖文件库 iCloud 开关同开（设置文案提示，不强耦合）
- 回环抑制：导入后把导出指纹直接记到导入版 updateTime，不触发回声导出

## 触发点（v1 粗粒度，够用）

- 「立即同步」按钮（导入→导出，全手动可控）
- app 进前台 / 退后台时各跑一轮（debounce）
- 楼层开关初开：全量导出（后台+进度）

## Checklist

### S1+S2 ✅（2026-06-13）
- [x] SyncStore：文档编解码 / 指纹增量导出 / 导入扫描+并集合并（冲突副本天然幂等聚合）
- [x] 同步根可注入；日期编码 .secondsSince1970（ISO8601 截秒导致指纹永远过期——测试抓出）
- [x] XCTest 双容器：roundtrip/分支并集/幂等/已有节点不被改写/指纹跳过，全绿
- [x] 设置-数据与备份「同步」区：按楼层开关 + 立即同步 + 状态行 + 本地模式互斥
- [x] 前后台 scenePhase 钩子（进前台拉/退后台推）
- [x] 双端 build + 部署；双机实测等粟粟统一账号
### 双机实测 ✅（2026-06-13 早，Mac ↔ 口罩机/同账号）
- [x] 楼层接入 → 26 对话拉取 → 手机回话 → 双向合并，全程手动按钮验通 🎉
- 实战修出三个路障：①初次全量导出卡死主线程（搬后台+进度）②iOS 不自动下载 iCloud 文档
  （materializeDocuments 触发下载+轮询）③接入按钮没预热容器（顺带完成账号侧容器立户）
- 已知噪音：浏览对话会碰 updateTime → 幂等重导出几个文档，无害
- **S2.5 准实时 ✅（2026-06-13 早）**：SyncEngine——前台 15s 导出泵（指纹无变化≈零成本）+
  NSMetadataQuery 盯同步目录（对端到货 2s debounce 自动导入）+ 退后台最后一推；楼层切换/开关幂等重启。
  测试守卫两枚：XCTest 宿主下文件库强制本地根 + 引擎禁动（测试曾把 4 个 xctest 楼层生进真 iCloud 容器，已清）。
  118 测试 0 失败。实时上限受 iCloud 传输调度（秒~几十秒）。

### 自动同步排障 ✅（2026-06-13 早，探针实测）
- [x] 探针 SyncProbe（Caches/sync-probe.log）三端部署，engine/EXPORT/IMPORT/DOWNLOAD/cloud EVENT 全打点
- [x] **根因 1**：状态账本曾放共享 sync 目录被 iCloud 跨设备互相覆盖 → 搬 App Support/sync-state（b9c4823）
- [x] **根因 2**：iOS 重启后 ubiquity 容器缓存 nil，引擎泵全程对空气抽（听得见 cloud EVENT、永远导不进）
  → 引擎 start 先 primeICloudContainer 再上岗（8261c34）。修后实测：手机卡了半天的「测试！！」
  09:45:25 自动进 Mac（+conv=1 +nodes=3，零按钮）；手机 09:46:18 自动吃进 11 文档
- 已知噪音：账本重置后两台 iOS 全量重导出 27 文档 churn ~4 分钟后自愈（一次性，非死循环）
- ⚠️ 技术债：B2642792 对话 7 节点 26MB（segmentsData 内联 base64 旧图），每碰 updateTime 全量重写+重传；
  等附件外置化迁移把旧对话也洗一遍才解
- [ ] 干净延迟测量：双端醒着发一条单消息，读探针算端到端数字

### S3（扩面）
- [ ] 记忆池/画像/preset/世界书文档化
### S4（删除与冲突）
- [ ] 墓碑 + 回收站缓冲 + 冲突可见化
