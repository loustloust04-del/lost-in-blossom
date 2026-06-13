# Plan：同步延迟优化（research-sync-stuttering → 实施）

日期：2026-06-13  
前置：`research-sync-stuttering.md`（5 个问题分级）

## 目标

稳态同步延迟从 ~45s 降到 <10s（最理想 ~5s），不增加 CPU/IO 负担。

## 改动范围

只动 `SyncEngine.swift`（~115 行），SyncStore 不动。

---

## L1：Mac 目录监听替代轮询（P3+P4 一并解）

**现状**：Mac 没挂 iCloud entitlement → NSMetadataQuery 聋 → 接收全靠 15s Timer 轮询。
**方案**：用 `DispatchSource.makeFileSystemObjectSource` 监听同步目录。这是纯本地 FS 事件（靠 kqueue），不需要 entitlement，iCloud Drive daemon 写入文件时触发。

```swift
// SyncEngine 新增
private var dirSource: DispatchSourceFileSystemObject?

private func startDirectoryMonitor() {
    guard let root = SyncStore.syncRoot(profileId: profileId!) else { return }
    let fd = open(root.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: .write, queue: .main
    )
    source.setEventHandler { [weak self] in
        SyncProbe.log("fs EVENT dir-write")
        self?.scheduleImport()
    }
    source.setCancelHandler { close(fd) }
    source.resume()
    dirSource = source
}
```

- Mac 上 `cloudChanged`（NSMetadataQuery）和 `dirSource` 并存——哪个先响应先触发
- iOS 上 dirSource 无意义（iCloud 文件不在本地 FS 路径），NSMetadataQuery 是主力
- debounce 复用已有 `scheduleImport()`（从 `cloudChanged` 里抽出来）

## L2：泵间隔 15s → 5s

轮询 27 个文件的 mtime 实测 <1ms，缩到 5s 无负担。这是 L1 的保底——DispatchSource 偶尔漏事件时兜底。

```swift
// 改一行
self.exportTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { ... }
```

## L3：空转检测 — 连续无变化自动降频

避免稳态下 5s 一次的 syncNow 反复 fetch+比较浪费 SwiftData context。

```swift
private var idleCount = 0

private func pump(exportOnly: Bool) {
    // ... existing busy guard ...
    busy = true
    let pid = profileId
    DispatchQueue.global(qos: .utility).async { [weak self] in
        let context = ModelContext(container)
        let result = SyncStore.syncNow(profileId: pid, context: context)
        let hadWork = result.exported.exported > 0
            || result.imported.nodesInserted > 0
            || result.imported.conversationsCreated > 0
        Task { @MainActor in
            guard let self else { return }
            self.busy = false
            if hadWork {
                self.idleCount = 0
            } else {
                self.idleCount += 1
            }
        }
    }
}
```

泵判断：`idleCount >= 6`（连续 30s 无变化）→ 跳过本轮（但 FS/cloud EVENT 立刻重置 idleCount 恢复全速）。
效果：稳态下真正的 syncNow 调用从 12 次/分钟 → ~2 次/分钟，有新数据时立刻恢复 5s 节奏。

---

## 延迟预期

| 场景 | 改前 | 改后 |
|------|------|------|
| iOS→Mac（NSMetadataQuery 正常时） | 2s debounce + iCloud 传播 | 不变 ~5s |
| iOS→Mac（NSMetadataQuery 聋时） | ≤15s 轮询 + iCloud 传播 = ~30s | DispatchSource 即时 + 2s debounce = ~5s |
| Mac→iOS | ≤15s 导出 + iCloud + 2s debounce | ≤5s 导出 + iCloud + 2s debounce = ~10s |
| 任意→任意最坏 | ~45s | ~15s |

## Checklist

- [x] 抽出 `scheduleImport()` 方法（从 `cloudChanged` 的 debounce 逻辑）
- [x] 加 `startDirectoryMonitor()`（DispatchSource.makeFileSystemObjectSource）
- [x] start() 里调 `startDirectoryMonitor()`；stop() 里 cancel source
- [x] Timer 间隔 15→5
- [x] 加 `idleCount` 空转检测 + idleCount≥6 跳过 + EVENT 驱动始终放行
- [x] 探针加 `fs EVENT` 行
- [x] build macOS + iOS 双端通过
- [x] Mac 跳过 materializeDocuments 的 startDownloadingUbiquitousItem（根因：iCloud daemon 对裸路径文件反复"重下载"改 mtime 引发死循环）
- [x] 部署三端，实测：启动后 10s 收敛安静（改前 20min churn）
- [ ] 干净延迟测量（等粟粟在一端发消息，读探针算端到端秒数）
