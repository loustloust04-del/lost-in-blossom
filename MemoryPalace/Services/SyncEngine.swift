import Foundation
import SwiftData

/// S2.5 准实时同步引擎（plan-cross-device-sync）。
/// - 导出泵：前台每 15s 跑一次指纹增量导出（无变化 = 一次轻量 fetch + 比较，近零成本）
/// - 云端监听：NSMetadataQuery 盯同步目录，对端文档一到货 debounce 自动导入
/// 上限被 iCloud 传输卡死（秒~几十秒），手动「立即同步」仍保留为强制档。
@MainActor
final class SyncEngine: NSObject {
    static let shared = SyncEngine()

    private var container: ModelContainer?
    private var profileId: String?
    private var exportTimer: Timer?
    private var metadataQuery: NSMetadataQuery?
    private var importDebounce: Timer?
    private var busy = false

    /// 幂等：楼层切换/开关重开直接重 start
    func start(profileId: String, container: ModelContainer) {
        stop()
        // 测试宿主里禁动：引擎会拿真楼层在测试期间偷跑导出（非确定性来源）
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard SyncStore.isEnabled(profileId: profileId) else { return }
        self.profileId = profileId
        self.container = container

        // ⚠️ 必须先预热容器：iOS 重启后 ubiquity URL 缓存是 nil，不预热 = 同步根为 nil，
        // 泵全程对空气抽（手机实测：听得见云事件、永远导不进）。Mac 预热是 no-op 秒回。
        FileLibraryStore.primeICloudContainer { [weak self] available in
            guard let self, self.profileId == profileId else { return }
            guard available else {
                SyncProbe.log("engine ABORT floor=\(profileId.prefix(12)) — iCloud 容器不可用")
                return
            }
            SyncProbe.log("engine START floor=\(profileId.prefix(12))")

            // 全量泵：导出推本地变化 + 导入拉云端变化（mtime 增量，闲时近零成本）。
            // Mac 没挂 iCloud entitlement，NSMetadataQuery 听不到——接收方向全靠这条轮询。
            self.exportTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pump(exportOnly: false) }
            }

            self.startMetadataQuery()
            // 启动先全量对一次（拉对端积压 + 推本地积压）
            self.pump(exportOnly: false)
        }
    }

    func stop() {
        exportTimer?.invalidate()
        exportTimer = nil
        importDebounce?.invalidate()
        importDebounce = nil
        if let query = metadataQuery {
            query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        }
        metadataQuery = nil
        profileId = nil
        container = nil
    }

    // MARK: - 云端监听

    private func startMetadataQuery() {
        guard let profileId else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // 只关心本楼层同步目录里的 json（含还没下载完的占位项——到货事件就是导入时机）
        query.predicate = NSPredicate(
            format: "%K LIKE '*.json' AND %K CONTAINS %@",
            NSMetadataItemFSNameKey, NSMetadataItemPathKey, "/sync/\(profileId)/"
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged),
            name: .NSMetadataQueryDidUpdate, object: query
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged),
            name: .NSMetadataQueryDidFinishGathering, object: query
        )
        metadataQuery = query
        query.start()
    }

    @objc private func cloudChanged(_ note: Notification) {
        SyncProbe.log("cloud EVENT \(note.name == .NSMetadataQueryDidFinishGathering ? "gathered" : "update")")
        // 自己导出也会触发（再导入一遍是指纹级 no-op），debounce 合并风暴
        importDebounce?.invalidate()
        importDebounce = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.pump(exportOnly: false) }
        }
    }

    // MARK: - 泵

    private func pump(exportOnly: Bool) {
        guard !busy, let profileId, let container else { return }
        guard SyncStore.isEnabled(profileId: profileId) else { stop(); return }
        busy = true
        let pid = profileId
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let context = ModelContext(container)
            if exportOnly {
                _ = SyncStore.exportChanged(profileId: pid, context: context)
            } else {
                _ = SyncStore.syncNow(profileId: pid, context: context)
            }
            Task { @MainActor in self?.busy = false }
        }
    }
}
