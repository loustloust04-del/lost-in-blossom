#if os(iOS)
import SwiftUI
import UIKit
import QuickLook

struct AttachmentPreviewSheet: View {
    let items: [BubbleAttachmentItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showSaveConfirm = false
    @State private var tempURLs: [URL] = []
    @State private var quickLookURL: URL?

    init(items: [BubbleAttachmentItem], initialIndex: Int) {
        self.items = items
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var isCurrentImage: Bool {
        guard currentIndex < items.count else { return false }
        if case .image = items[currentIndex] { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    previewContent(item)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 顶部渐变遮罩
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.88), .black.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea()

            // 按钮层
            VStack {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))

                    Spacer()

                    Menu {
                        if isCurrentImage {
                            Button {
                                saveToPhotos()
                            } label: {
                                Label("保存到相册", systemImage: "photo.badge.arrow.down")
                            }
                        }
                        Button {
                            saveToFiles()
                        } label: {
                            Label("保存到文件", systemImage: "folder.badge.plus")
                        }
                        Button {
                            openInQuickLook()
                        } label: {
                            Label("用系统预览打开", systemImage: "eye")
                        }
                        Button {
                            shareItem()
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .compositingGroup()
                .padding(.horizontal, 16)
                .padding(.top, 19)

                Spacer()
            }
        }
        .alert("已保存", isPresented: $showSaveConfirm) {
            Button("好") {}
        }
        .quickLookPreview($quickLookURL, in: tempURLs)
        .onAppear { prepareTempFiles() }
        .onDisappear { cleanupTempFiles() }
    }

    @ViewBuilder
    private func previewContent(_ item: BubbleAttachmentItem) -> some View {
        switch item {
        case .image(_, let data):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        case .file(let name, let type, _):
            fileCard(name: name, type: type)
        case .fileData(let name, let mime, _):
            fileCard(name: name, type: mime)
        }
    }

    @ViewBuilder
    private func fileCard(name: String, type: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
            Text(name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            if let type {
                Text(type)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            Button("用系统预览打开") { openInQuickLook() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
        }
    }

    private func prepareTempFiles() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preview_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURLs = items.map { item in
            switch item {
            case .image(let name, let data):
                let url = dir.appendingPathComponent(name)
                try? data.write(to: url)
                return url
            case .file(let name, _, let content):
                let url = dir.appendingPathComponent(name)
                if let content, let data = content.data(using: .utf8) {
                    try? data.write(to: url)
                }
                return url
            case .fileData(let name, _, let data):
                let url = dir.appendingPathComponent(name)
                try? data.write(to: url)
                return url
            }
        }
    }

    private func cleanupTempFiles() {
        if let first = tempURLs.first {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
        }
    }

    private func openInQuickLook() {
        guard currentIndex < tempURLs.count else { return }
        quickLookURL = tempURLs[currentIndex]
    }

    private func saveToPhotos() {
        guard currentIndex < items.count else { return }
        if case .image(_, let data) = items[currentIndex],
           let image = UIImage(data: data) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            showSaveConfirm = true
        }
    }

    private func saveToFiles() {
        guard currentIndex < tempURLs.count else { return }
        let url = tempURLs[currentIndex]
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url])
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(picker, animated: true)
        }
    }

    private func shareItem() {
        guard currentIndex < items.count else { return }
        var shareItems: [Any] = []
        switch items[currentIndex] {
        case .image(_, let data):
            if let image = UIImage(data: data) { shareItems.append(image) }
        case .file(let name, _, _):
            shareItems.append(name)
        case .fileData:
            if currentIndex < tempURLs.count { shareItems.append(tempURLs[currentIndex]) }
        }
        guard !shareItems.isEmpty else { return }
        let ac = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(ac, animated: true)
        }
    }
}
#endif
