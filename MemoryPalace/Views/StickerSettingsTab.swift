import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StickerSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    @State private var stickerAssetCount: Int = 0
    @State private var placedStickerCount: Int = 0
    @State private var stickerDiskUsage: String = ""
    @State private var isExportingStickers = false
    @State private var isImportingStickers = false
    @State private var stickerImportExportMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 统计
            VStack(alignment: .leading, spacing: 12) {
                Text("贴纸库")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                HStack(spacing: 20) {
                    statItem(label: "贴纸资产", value: "\(stickerAssetCount)")
                    statItem(label: "已贴数量", value: "\(placedStickerCount)")
                    statItem(label: "磁盘占用", value: stickerDiskUsage)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.mainBg.opacity(0.6)))

            // 导入导出
            VStack(alignment: .leading, spacing: 12) {
                Text("贴纸数据")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text("导出包含贴纸资产（图片+描边）和画布布局（位置/旋转/缩放）。导入后贴纸归位。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)

                    HStack(spacing: 12) {
                        Button(action: exportStickerPack) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11))
                                Text(isExportingStickers ? "导出中..." : "导出贴纸包")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.branchIndicator))
                        }
                        .buttonStyle(.plain)
                        .disabled(isExportingStickers)

                        Button(action: importStickerPack) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 11))
                                Text(isImportingStickers ? "导入中..." : "导入贴纸包")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(Theme.branchIndicator)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().stroke(Theme.branchIndicator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingStickers)
                    }

                    if let msg = stickerImportExportMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.branchIndicator)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.mainBg.opacity(0.6)))
            }
            .onAppear { loadStickerStats() }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
    }

    private func loadStickerStats() {
        guard let pid = profileManager?.currentProfile.id else { return }
        let pidCopy = pid

        let assetDesc = FetchDescriptor<StickerAsset>(
            predicate: #Predicate<StickerAsset> { a in a.profileId == pidCopy }
        )
        stickerAssetCount = (try? modelContext.fetch(assetDesc))?.count ?? 0

        let placedDesc = FetchDescriptor<PlacedSticker>(
            predicate: #Predicate<PlacedSticker> { s in s.profileId == pidCopy }
        )
        placedStickerCount = (try? modelContext.fetch(placedDesc))?.count ?? 0

        let dir = StickerFileManager.stickerDirectory(profileId: pid)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            let totalBytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            if totalBytes < 1024 * 1024 {
                stickerDiskUsage = "\(totalBytes / 1024) KB"
            } else {
                stickerDiskUsage = String(format: "%.1f MB", Double(totalBytes) / 1024 / 1024)
            }
        } else {
            stickerDiskUsage = "0 KB"
        }
    }

    private func exportStickerPack() {
        guard let pid = profileManager?.currentProfile.id else { return }
        isExportingStickers = true
        stickerImportExportMessage = nil
        Task {
            do {
                let url = try await StickerPackExporter.export(profileId: pid, context: modelContext)
                await MainActor.run {
                    isExportingStickers = false
                }
            } catch {
                await MainActor.run {
                    isExportingStickers = false
                    stickerImportExportMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func importStickerPack() {
        guard let pid = profileManager?.currentProfile.id else { return }
    }
}

// MARK: - iOS Sticker Settings Page

struct IOSStickerPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?

    @State private var stickerAssetCount: Int = 0
    @State private var placedStickerCount: Int = 0
    @State private var stickerDiskUsage: String = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var statusMessage: String? = nil

    var body: some View {
        List {
            Section("贴纸库") {
                HStack(spacing: 20) {
                    stickerStat("贴纸资产", value: "\(stickerAssetCount)")
                    stickerStat("已贴数量", value: "\(placedStickerCount)")
                    stickerStat("磁盘占用", value: stickerDiskUsage)
                }
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)

            Section("贴纸数据") {
                Text("导出包含贴纸资产（图片+描边）和画布布局。导入后贴纸归位。")
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)

                HStack(spacing: 12) {
                    Button(action: exportPack) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: Theme.F.caption))
                            Text(isExporting ? "导出中..." : "导出贴纸包")
                                .font(.system(size: Theme.F.secondary, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.branchIndicator))
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)

                    Button(action: { showFileImporter = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: Theme.F.caption))
                            Text(isImporting ? "导入中..." : "导入贴纸包")
                                .font(.system(size: Theme.F.secondary, weight: .medium))
                        }
                        .foregroundColor(Theme.branchIndicator)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(Theme.branchIndicator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.branchIndicator)
                }
            }
            .listRowBackground(Theme.mainBg)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBg)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("贴纸")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadStats() }
        .sheet(isPresented: $showFileImporter) {
            DocumentPickerView(contentTypes: [UTType(filenameExtension: "stickerpack") ?? .data]) { urls in
                importPack(result: .success(urls))
            } onCancel: {}
        }
    }

    private func stickerStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
        }
    }

    private func loadStats() {
        guard let pid = profileManager?.currentProfile.id else { return }
        let pidCopy = pid

        let assetDesc = FetchDescriptor<StickerAsset>(
            predicate: #Predicate<StickerAsset> { a in a.profileId == pidCopy }
        )
        stickerAssetCount = (try? modelContext.fetch(assetDesc))?.count ?? 0

        let placedDesc = FetchDescriptor<PlacedSticker>(
            predicate: #Predicate<PlacedSticker> { s in s.profileId == pidCopy }
        )
        placedStickerCount = (try? modelContext.fetch(placedDesc))?.count ?? 0

        let dir = StickerFileManager.stickerDirectory(profileId: pid)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            let totalBytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            if totalBytes < 1024 * 1024 {
                stickerDiskUsage = "\(totalBytes / 1024) KB"
            } else {
                stickerDiskUsage = String(format: "%.1f MB", Double(totalBytes) / 1024 / 1024)
            }
        } else {
            stickerDiskUsage = "0 KB"
        }
    }

    private func exportPack() {
        guard let pid = profileManager?.currentProfile.id else { return }
        isExporting = true
        statusMessage = nil
        Task {
            do {
                let url = try await StickerPackExporter.export(profileId: pid, context: modelContext)
                await MainActor.run {
                    isExporting = false
                    // iOS 分享面板
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = root.view
                            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
                        }
                        root.present(activityVC, animated: true)
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    statusMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func importPack(result: Result<[URL], Error>) {
        guard let pid = profileManager?.currentProfile.id else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            statusMessage = nil
            Task {
                do {
                    let counts = try await StickerPackImporter.importPack(url: url, profileId: pid, context: modelContext)
                    await MainActor.run {
                        isImporting = false
                        statusMessage = "导入成功！\(counts.assets) 个贴纸，\(counts.placements) 个布局"
                        loadStats()
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        statusMessage = "导入失败：\(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            statusMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }
}
