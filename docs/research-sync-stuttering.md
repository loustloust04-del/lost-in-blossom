# 排查：同步「卡卡的」到底怎么回事

日期：2026-06-13
探针数据来源：`~/Library/Caches/MemoryPalace/sync-probe.log`（三端部署）

## 时间线（探针实录）

```
09:38:04  Mac 引擎启动（旧版，无预热）
09:41:20  Mac EXPORT conv=41F5E0E3（粟粟在 Mac 发的消息，15s 泵捕获）
09:45:01  Mac 引擎重启（预热版 8261c34 部署）
09:45:16  Mac DOWNLOAD triggered — 开始从 iCloud 拉文件
09:45:23  Mac IMPORT 首批：85FA5B97, 5948A1F8（口罩机的「测试！！」终于进来了！✅）
09:46:12  口罩机 EXPORT 7 个文档（账本重置后全量重导出）
09:46:18  口罩机 IMPORT 11 个文档（Mac 和 Air 的积压全吃进）
09:46:19  口罩机连续 EXPORT 7 个文档（导入触发回环——详见问题2）
…
09:45~10:06  Mac 每 15s 循环 DOWNLOAD(5~7) → IMPORT(2~7 files)，持续 20 分钟
10:06:52  最后一条 IMPORT，循环自然停止
11:40:06  1.5 小时后确认：日志安静，不再循环
```

## 发现的问题（按严重性排序）

### P0：iOS 容器未预热 → 引擎对空气抽（已修 ✅）

**症状**：口罩机日志全是 `cloud EVENT update`（门铃狂响），但 0 条 IMPORT。
**根因**：iOS 重启后 `FileManager.url(forUbiquityContainerIdentifier:)` 缓存为 nil。引擎启动时直接跑泵，syncRoot 返回 nil → 所有操作跳过。Mac 用裸路径 `~/Library/Mobile Documents/…` 不受影响。
**修法**：引擎 start 先 `primeICloudContainer`，回调里才上岗（commit 8261c34）。
**实测结果**：修后手机立刻活了——09:46:18 自动吃进 11 个文档。

### P1：回环抑制不彻底 → 账本重置后 20 分钟 churn

**症状**：两台 iOS 设备账本重置后全量重导出，Mac 循环 DOWNLOAD → IMPORT 同一批文件 20 分钟。
**机制**：

```
手机 A 导入 → 回环抑制正常（不重导出同 updateTime）
        → 但 SwiftData 导入新节点后 conversation.nodeCount 被碰
        → nodeCount 变化不碰 updateTime，但如果用户曾浏览过该对话，
          updateTime 可能在浏览时被碰过（大于导出指纹记的值）
        → 导出器看到 updateTime > 已导出指纹 → 重导出
        → 文件 mtime 变化 → iCloud 传播到 Mac → Mac 重导入
        → 手机 B 也 cloud EVENT → 重导入 → 可能再导出
```

**后果**：
- 7 个文件反复被下载+解码（含 26MB 的 B2642792），浪费 CPU/带宽
- 用户看到同步"一直在转"
- 不是死循环：文件内容最终收敛后 mtime 停变 → 循环自然熄灭（本次 ~20min）

**但**：这是一次性代价（仅在账本重置/新设备加入时发生），日常使用不会重现。

### P2：26MB 文档（B2642792）= 大象在同步管道里

**数据**：`B2642792` 对话仅 7 个节点，但 segmentsData 内联了旧图片 base64 = 26MB JSON 文档。
**影响**：每次碰 updateTime 就全量重写 26MB + iCloud 重传 26MB。在 P1 的 churn 里，这个文件每 15s 被 Mac 重下载解码一次。
**解法**：附件外置化迁移需要覆盖旧对话（已有 AttachmentStore，但没回刷存量数据）。

### P3：Mac 泵间隔 15s → 稳态延迟上限偏高

**稳态链路**（无 churn 时）：
```
设备 A 发消息 → 15s 内泵捕获导出 → iCloud 传播（秒~几十秒）
→ 设备 B 收到：
  - iOS：cloud EVENT → 2s debounce → 导入     （总 ~20s）
  - Mac：15s 泵轮询 → DOWNLOAD → 导入          （总 ~35s）
```

Mac 最坏情况 = 15(A导出) + 15(iCloud) + 15(B轮询) = **45 秒**。
iOS 有 NSMetadataQuery，可以更快（~20s），但受限于 iCloud 传播速度。

### P4：Mac 没挂 iCloud entitlement → NSMetadataQuery 聋

Mac 非沙箱、零签名，`~/Library/Mobile Documents/` 裸路径能读写但 NSMetadataQuery 不工作（需要 com.apple.developer.ubiquity-container-identifiers）。所以 Mac 接收方向全靠 15s 轮询——比 iOS 的事件驱动慢一档。

**变通**：
- 缩短泵间隔到 5s？→ 轮询 27 个文件的 mtime 每次 ~1ms，5s 完全可接受
- 或：Mac 用 FSEvents / DispatchSource 监听 `~/Library/Mobile Documents/…` 目录变化（本地 FS 事件不需要 entitlement）

### P5：iOS 后台限制 → 锁屏同步停摆

iOS 锁屏后 app 挂起，引擎睡了。口罩机 devicectl 也连不上（锁屏后 USB 调试断开）。
这是系统行为，没法绕——只能确保前台时同步高效。

## 当前状态

| 指标 | 值 |
|------|------|
| P0 已修 | ✅（预热前置） |
| 循环已停 | ✅（10:06:52 自然熄灭，1.5h 后确认安静） |
| 稳态延迟 | 未量（被 churn 污染；需干净测试） |
| 数据正确性 | ✅（并集合并幂等，反复导入无害） |
| 资源浪费 | 仅 churn 期间（~20min）；稳态轮询开销 <1ms/次 |

## 建议优先级

1. **干净测量稳态延迟**：双端解锁 → Mac 发一条消息 → 读探针算端到端秒数
2. **P3 快赢**：Mac 泵间隔 15s→5s（轮询 mtime 极轻量，5s 对话感知更自然）
3. **P3 进阶**：Mac 用 DispatchSource 监听 Mobile Documents 目录（FSEvents 不需要 entitlement）→ 事件驱动替代轮询 → 延迟可降到 <10s
4. **P2**：存量数据洗附件外置化（去掉 26MB 大象）
5. **P1**：回环抑制加强——导入后额外比较文件内容 hash，内容不变不 bump importState（治标不治本，真正解是消灭重导出的动机）
