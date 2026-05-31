import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// + 号功能面板（Claude App 风格底部 sheet）
/// 内容：添加文件/照片、选择模型、设置、导入聊天记录、贴纸
struct AddToChatSheet: View {
    /// 点击「贴纸」后回调——由 CardFlowView 传入，负责打开 StickerKeyboardPanel
    let onOpenSticker: () -> Void
    /// 选中照片后写入此 Binding，由 CardFlowView 持有并传给 ChatInputBar
    @Binding var pendingImageData: Data?
    /// 选中 PDF 文件后写入，由 CardFlowView 持有并传给 ChatInputBar
    @Binding var pendingFileData: Data?
    @Binding var pendingFileName: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?

    @AppStorage("selectedChatModel") private var selectedModelId = ""

    @State private var showModelPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    /// 控制 staggered 入场动画
    @State private var appeared = false

    private func compressImage(_ uiImage: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        var img = uiImage
        let maxSide = max(uiImage.size.width, uiImage.size.height)
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            img = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        if let data = img.jpegData(compressionQuality: 0.8), data.count <= 1_048_576 {
            return data
        }
        return img.jpegData(compressionQuality: 0.5)
    }

    private var currentModelName: String {
        guard let pm = providerManager else { return "未选择" }
        if !selectedModelId.isEmpty, let model = pm.model(byId: selectedModelId) {
            return model.name
        }
        return pm.availableModels.first?.name ?? "未选择"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // 间距
                Spacer().frame(height: 20)

                // ── 行 0：添加文件 / 照片 ──────────────────────────────
                PhotosPicker(
                    selection: $photoPickerItems,
                    maxSelectionCount: 1,
                    matching: .images
                ) {
                    addToChatRow(
                        icon: "paperclip",
                        iconColor: Theme.branchIndicator,
                        title: "添加文件 / 照片",
                        trailing: nil
                    )
                }
                .onChange(of: photoPickerItems) { _, newItems in
                    guard let item = newItems.first else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data),
                           let compressed = compressImage(uiImage) {
                            await MainActor.run {
                                pendingImageData = compressed
                            }
                        }
                        await MainActor.run {
                            photoPickerItems = []
                            dismiss()
                        }
                    }
                }
                .rowEntrance(index: 0, appeared: appeared)

                rowDivider

                // ── 行 1：PDF 文件 ──────────────────────────────────────
                Button {
                    showFilePicker = true
                } label: {
                    addToChatRow(
                        icon: "doc.fill",
                        iconColor: Color.red.opacity(0.8),
                        title: "发送 PDF",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
                .rowEntrance(index: 1, appeared: appeared)

                rowDivider

                // ── 行 2：选择模型 ─────────────────────────────────────
                Button {
                    showModelPicker = true
                } label: {
                    addToChatRow(
                        icon: "cpu",
                        iconColor: Color.purple.opacity(0.85),
                        title: "选择模型",
                        trailing: AnyView(
                            Text(currentModelName)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        )
                    )
                }
                .buttonStyle(.plain)
                .rowEntrance(index: 2, appeared: appeared)

                rowDivider

                // ── 行 3：设置 ─────────────────────────────────────────
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .requestShowSettings, object: nil)
                    }
                } label: {
                    addToChatRow(
                        icon: "gearshape",
                        iconColor: Theme.textMuted,
                        title: "设置",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
                .rowEntrance(index: 3, appeared: appeared)

                rowDivider

                // ── 行 4：导入聊天记录 ─────────────────────────────────
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .memoryPalaceRequestImport, object: nil)
                    }
                } label: {
                    addToChatRow(
                        icon: "square.and.arrow.down",
                        iconColor: Color.orange.opacity(0.85),
                        title: "导入聊天记录",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
                .rowEntrance(index: 4, appeared: appeared)

                rowDivider

                // ── 行 5：贴纸 ─────────────────────────────────────────
                Button {
                    dismiss()
                    // 短暂延迟让 sheet dismiss 动画完成后再展开贴纸面板
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onOpenSticker()
                    }
                } label: {
                    addToChatRow(
                        icon: "face.smiling",
                        iconColor: Color.pink.opacity(0.85),
                        title: "贴纸",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
                .rowEntrance(index: 5, appeared: appeared)

                Spacer()
            }
            .background(Theme.sidebarBg)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sidebarBg)
        .onAppear {
            withAnimation(.easeOut(duration: 0.1)) {
                appeared = true
            }
        }
        // 模型选择器 sub-sheet
        .sheet(isPresented: $showModelPicker) {
            if let pm = providerManager {
                ModelPickerPopover(
                    providerManager: pm,
                    selectedModelId: selectedModelId
                ) { model in
                    selectedModelId = model.id
                    pm.touchLastUsed(providerId: model.providerId, modelId: model.modelId)
                    showModelPicker = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.sidebarBg)
            }
        }
        // PDF 文件选择器
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard let url = (try? result.get())?.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count <= 10_485_760 else { return }
            let name = url.lastPathComponent
            pendingFileData = data
            pendingFileName = name
            dismiss()
        }
    }

    // MARK: - Row layout

    @ViewBuilder
    private func addToChatRow(
        icon: String,
        iconColor: Color,
        title: String,
        trailing: AnyView?
    ) -> some View {
        HStack(spacing: 14) {
            // 图标圆形底
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            if let trailingView = trailing {
                trailingView
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.25))
            .frame(height: 0.5)
            .padding(.leading, 70)
    }
}

// MARK: - 入场动画 ViewModifier

private struct RowEntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(
                .easeOut(duration: 0.22).delay(Double(index) * 0.05),
                value: appeared
            )
    }
}

private extension View {
    func rowEntrance(index: Int, appeared: Bool) -> some View {
        modifier(RowEntranceModifier(index: index, appeared: appeared))
    }
}
