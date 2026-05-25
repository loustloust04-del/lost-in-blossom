import SwiftUI
import UniformTypeIdentifiers

/// 画布贴纸叠加层 — 作为 ZStack sibling 挂在 LazyVStack 旁边。
/// 自己计算 minHeight = max sticker maxY + buffer，让 ZStack 自然 layout 时
/// height = max(LazyVStack.h, sticker overlay 声明 h)，保证覆盖所有 sticker
/// 实际位置（包括用户拖到 LazyVStack 之外的）。不再依赖外部 contentHeight 参数。
struct StickerCanvasLayer: View {
    var stickerVM: StickerViewModel
    let profileId: String
    @Environment(\.modelContext) private var modelContext
    @State private var editModeStartTime: Date = .distantPast

    /// 所有 sticker 中最远 maxY（覆盖到的 y 位置）+ 50pt buffer。
    /// 让 overlay 至少撑这么大，确保拖到 LazyVStack 外的 sticker 也能接 touch。
    private var stickerExtent: CGFloat {
        let maxY = stickerVM.placedStickers.map { sticker -> CGFloat in
            let size = stickerVM.stickerSizes[sticker.id] ?? CGSize(width: 80, height: 80)
            return sticker.positionY + size.height * sticker.scale / 2
        }.max() ?? 0
        return maxY + 50
    }

    var body: some View {
        #if os(iOS)
        let _ = PROBE("[PROBE 贴纸 layer.body] editing=\(stickerVM.isEditingStickers) selectedId=\(stickerVM.selectedPlacedStickerId?.uuidString ?? "nil") stickerCount=\(stickerVM.placedStickers.count) stickerExtent=\(stickerExtent)")
        #endif
        return ZStack(alignment: .topLeading) {
            // 透明底板撑满整个 overlay 区域 + 声明最小高度 = stickerExtent
            // ZStack 自然 layout 后整个 overlay 至少 stickerExtent 高，覆盖所有 sticker。
            // 点击空白 → 取消选中（不退出编辑模式，只有"完成"按钮退出）
            // coordinateSpace 让旋转手势在固定坐标系计算角度
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(stickerExtent, 1))
                .contentShape(Rectangle())
                .allowsHitTesting(stickerVM.isEditingStickers)
                .onTapGesture {
                    // 防抖：进入编辑模式 0.4 秒内忽略（防止长按松手误触）
                    guard Date().timeIntervalSince(editModeStartTime) > 0.4 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        stickerVM.selectedPlacedStickerId = nil
                    }
                }

            // 贴纸
            ForEach(stickerVM.placedStickers, id: \.id) { sticker in
                stickerItem(sticker)
            }

            // 选中贴纸的选框 + 手柄（独立于贴纸，在画布坐标系）
            if stickerVM.isEditingStickers,
               let selectedId = stickerVM.selectedPlacedStickerId,
               let sticker = stickerVM.placedStickers.first(where: { $0.id == selectedId }) {
                StickerSelectionOverlay(
                    sticker: sticker,
                    contentSize: stickerVM.stickerSizes[sticker.id] ?? CGSize(width: 80, height: 80),
                    onDelete: {
                        stickerVM.removePlacedSticker(sticker, context: modelContext)
                    },
                    onSave: { try? modelContext.save() },
                    onUndoPush: { stickerVM.pushUndo(for: sticker) }
                )
                .zIndex(999)
                // iOS 选框纯视觉，所有交互由画布级 UIKit overlay 统一处理
                #if os(iOS)
                .allowsHitTesting(false)
                #endif
            }

            // 编辑模式浮动"完成"按钮（仅 macOS，iOS 合并在 StickerKeyboardPanel 工具栏里）
            #if os(macOS)
            if stickerVM.isEditingStickers {
                editModeBar
            }
            #endif

            // iOS 画布级统一手势层 — 拖拽/缩放/旋转/选中/长按菜单/撤回全在这一个 UIView 上
            // ⚠️ zIndex(998) 是关键：贴纸有 zIndex(n)，overlay 必须在贴纸上方才能收到触摸
            // frame 撑满 overlay container（= LazyVStack frame），自动覆盖 messages 区域。
            #if os(iOS)
            if stickerVM.isEditingStickers {
                StickerCanvasGestureOverlay(
                    stickerVM: stickerVM,
                    modelContext: modelContext,
                    editModeStartTime: editModeStartTime
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
                .zIndex(998)
            }
            #endif
        }
        .coordinateSpace(name: "stickerCanvas")
        // 重命名弹窗
        .alert("重命名", isPresented: renameBinding) {
            TextField("名称", text: renameTextBinding)
            Button("确定") {
                if let id = stickerVM.renamingStickerId {
                    stickerVM.renameAsset(assetId: id, newName: stickerVM.renameText, context: modelContext)
                    stickerVM.renamingStickerId = nil
                }
            }
            Button("取消", role: .cancel) { stickerVM.renamingStickerId = nil }
        }
        // 便签编辑 sheet
        .sheet(isPresented: editNoteBinding) {
            if let noteId = stickerVM.editingNoteStickerId,
               let sticker = stickerVM.placedStickers.first(where: { $0.id == noteId }) {
                NoteStickerEditor(
                    initialText: sticker.noteContent ?? "",
                    initialStyle: NoteStyle(rawValue: sticker.noteStyle ?? "yellow_square") ?? .yellowSquare,
                    isEditMode: true
                ) { newText, newStyle in
                    sticker.noteContent = newText
                    sticker.noteStyle = newStyle.rawValue
                    try? modelContext.save()
                    stickerVM.editingNoteStickerId = nil
                }
            }
        }
        #if os(macOS)
        // 快捷键（隐藏按钮）
        .background {
            Group {
                // ⌘C 复制
                Button("") {
                    if let id = stickerVM.selectedPlacedStickerId,
                       let sticker = stickerVM.placedStickers.first(where: { $0.id == id }) {
                        stickerVM.copySticker(sticker)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                // ⌘V 粘贴
                Button("") {
                    if let sticker = stickerVM.placedStickers.first(where: { $0.id == stickerVM.selectedPlacedStickerId }) {
                        stickerVM.pasteSticker(
                            conversationId: sticker.conversationId,
                            nearPosition: CGPoint(x: sticker.positionX, y: sticker.positionY),
                            profileId: sticker.profileId,
                            context: modelContext
                        )
                    }
                }
                .keyboardShortcut("v", modifiers: .command)

                // ⌫ 删除
                Button("") {
                    if let id = stickerVM.selectedPlacedStickerId,
                       let sticker = stickerVM.placedStickers.first(where: { $0.id == id }) {
                        stickerVM.removePlacedSticker(sticker, context: modelContext)
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])

                // ] 置于最前
                Button("") {
                    if let id = stickerVM.selectedPlacedStickerId,
                       let sticker = stickerVM.placedStickers.first(where: { $0.id == id }) {
                        stickerVM.bringToFront(sticker, context: modelContext)
                    }
                }
                .keyboardShortcut("]", modifiers: [])

                // [ 置于最后
                Button("") {
                    if let id = stickerVM.selectedPlacedStickerId,
                       let sticker = stickerVM.placedStickers.first(where: { $0.id == id }) {
                        stickerVM.sendToBack(sticker, context: modelContext)
                    }
                }
                .keyboardShortcut("[", modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        #endif
    }

    @ViewBuilder
    private func stickerItem(_ sticker: PlacedSticker) -> some View {
        let isSelected = stickerVM.selectedPlacedStickerId == sticker.id

        StickerView(
            sticker: sticker,
            profileId: profileId,
            isEditing: stickerVM.isEditingStickers,
            isSelected: isSelected,
            onRemove: {
                stickerVM.removePlacedSticker(sticker, context: modelContext)
            },
            onSizeChanged: { size in
                stickerVM.stickerSizes[sticker.id] = size
            }
        )
        // 右键菜单（仅 macOS；iOS 由编辑模式的 UIContextMenuInteraction 处理）
        #if os(macOS)
        .contextMenu { stickerContextMenu(sticker) }
        #endif
        .position(x: sticker.positionX, y: sticker.positionY)
        .zIndex(Double(sticker.zIndex))
        // 长按进入编辑模式 + 选中（0.3s，比默认 0.5s 快）
        .onLongPressGesture(minimumDuration: 0.3) {
            editModeStartTime = Date()
            withAnimation(.easeOut(duration: 0.2)) {
                stickerVM.isEditingStickers = true
                stickerVM.selectedPlacedStickerId = sticker.id
            }
        }
        // 编辑模式下拖动移动位置（macOS 用 SwiftUI DragGesture，iOS 由画布级 UIKit overlay 统一处理）
        #if os(macOS)
        .gesture(
            stickerVM.isEditingStickers && isSelected && !sticker.isLocked
            ? DragGesture(coordinateSpace: .named("stickerCanvas"))
                .onChanged { value in
                    if !stickerVM.dragStarted {
                        stickerVM.pushUndo(for: sticker)
                        stickerVM.dragStarted = true
                        stickerVM.dragTouchOffset = CGPoint(
                            x: value.startLocation.x - sticker.positionX,
                            y: value.startLocation.y - sticker.positionY
                        )
                        stickerVM.lastRotationDelta = 0
                        stickerVM.lastDragTranslation = .zero
                    }
                    // 平移
                    sticker.positionX = value.location.x
                    sticker.positionY = value.location.y

                    // 帧间 delta（DragGesture.translation 是累积值，需要减去上一帧）
                    let delta = CGSize(
                        width: value.translation.width - stickerVM.lastDragTranslation.width,
                        height: value.translation.height - stickerVM.lastDragTranslation.height
                    )
                    stickerVM.lastDragTranslation = value.translation

                    // 扭矩（用 delta，不是累积 translation）
                    let off = stickerVM.dragTouchOffset
                    let crossZ = off.x * delta.height - off.y * delta.width
                    let size = stickerVM.stickerSizes[sticker.id] ?? CGSize(width: 80, height: 80)
                    let w = size.width * sticker.scale
                    let h = size.height * sticker.scale
                    let halfDiagSq = (w * w + h * h) / 4.0
                    let torqueFactor: Double = 15.0
                    let rotDelta = (crossZ / max(halfDiagSq, 1)) * torqueFactor
                    sticker.rotation += rotDelta
                    stickerVM.lastRotationDelta = rotDelta
                }
                .onEnded { value in
                    // 短促惯性（纸在桌上不滑远）
                    let velocity = value.velocity
                    let friction: Double = 0.02
                    let angularInertia = stickerVM.lastRotationDelta * 4.0

                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 22)) {
                        sticker.positionX += velocity.width * friction
                        sticker.positionY += velocity.height * friction
                        sticker.rotation += angularInertia
                    }

                    // B20 修复：fling 累加后 clamp，防贴纸飞远撑虚高 ZStack
                    stickerVM.clampStickerY(sticker)

                    stickerVM.dragStarted = false
                    stickerVM.lastRotationDelta = 0
                    stickerVM.lastDragTranslation = .zero
                    try? modelContext.save()
                }
            : nil
        )
        #endif
        // 双击便签 → 编辑内容（macOS；iOS 编辑模式由 overlay 处理）
        .onTapGesture(count: 2) {
            if sticker.isNote, !sticker.isLocked {
                stickerVM.editingNoteStickerId = sticker.id
            }
        }
        // 单击选中（macOS；iOS 编辑模式由 overlay 处理）
        .onTapGesture {
            if stickerVM.isEditingStickers {
                stickerVM.selectedPlacedStickerId = sticker.id
            }
        }
        // iOS 编辑模式下：所有交互由画布级 overlay 处理，关掉 stickerItem 的 hitTesting
        // 防止 contextMenu / onLongPressGesture 抢走 overlay 的触摸
        #if os(iOS)
        .allowsHitTesting(!stickerVM.isEditingStickers)
        #endif
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func stickerContextMenu(_ sticker: PlacedSticker) -> some View {
        // 标题区分：这是贴纸的右键菜单
        let assetName = stickerVM.stickerAssets.first(where: { $0.id == sticker.stickerAssetId })?.name
        let label = sticker.isNote ? "便签" : (assetName ?? "贴纸")
        Text("🎨 \(label)")
            .font(.caption)

        Divider()

        Button { stickerVM.copySticker(sticker) } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            stickerVM.pasteSticker(
                conversationId: sticker.conversationId,
                nearPosition: CGPoint(x: sticker.positionX, y: sticker.positionY),
                profileId: sticker.profileId,
                context: modelContext
            )
        } label: {
            Label("粘贴", systemImage: "doc.on.clipboard")
        }
        .disabled(stickerVM.copiedSnapshot == nil)

        Divider()

        if sticker.isNote {
            Button { stickerVM.editingNoteStickerId = sticker.id } label: {
                Label("编辑内容", systemImage: "square.and.pencil")
            }
            .disabled(sticker.isLocked)
            Button {
                #if os(macOS)
                stickerVM.saveNoteAsPNG(content: sticker.noteContent ?? "", style: sticker.noteStyle ?? "yellow_square")
                #else
                stickerVM.shareNoteAsPNG(content: sticker.noteContent ?? "", style: sticker.noteStyle ?? "yellow_square")
                #endif
            } label: {
                Label("导出为图片", systemImage: "square.and.arrow.up")
            }
        }

        Button {
            if let assetId = sticker.stickerAssetId {
                stickerVM.renameText = stickerVM.stickerAssets.first(where: { $0.id == assetId })?.name ?? ""
                stickerVM.renamingStickerId = assetId
            }
        } label: {
            Label("重命名", systemImage: "pencil")
        }
        .disabled(sticker.stickerAssetId == nil)

        Divider()

        Button { stickerVM.toggleLock(sticker, context: modelContext) } label: {
            Label(sticker.isLocked ? "解锁" : "锁定", systemImage: sticker.isLocked ? "lock.open" : "lock")
        }

        Button { stickerVM.bringToFront(sticker, context: modelContext) } label: {
            Label("置于最前", systemImage: "square.3.layers.3d.top.filled")
        }
        Button { stickerVM.sendToBack(sticker, context: modelContext) } label: {
            Label("置于最后", systemImage: "square.3.layers.3d.bottom.filled")
        }

        Divider()

        Button(role: .destructive) {
            stickerVM.removePlacedSticker(sticker, context: modelContext)
        } label: {
            Label("删除", systemImage: "trash")
        }
        .disabled(sticker.isLocked)
    }

    private var editNoteBinding: Binding<Bool> {
        Binding(
            get: { stickerVM.editingNoteStickerId != nil },
            set: { if !$0 { stickerVM.editingNoteStickerId = nil } }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { stickerVM.renamingStickerId != nil },
            set: { if !$0 { stickerVM.renamingStickerId = nil } }
        )
    }

    private var renameTextBinding: Binding<String> {
        Binding(
            get: { stickerVM.renameText },
            set: { stickerVM.renameText = $0 }
        )
    }

    /// 编辑模式顶部提示栏
    private var editModeBar: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        stickerVM.isEditingStickers = false
                        stickerVM.selectedPlacedStickerId = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("完成")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.branchIndicator))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
    }
}

// MARK: - Selection Overlay (选框 + 手柄)

/// Figma 风格选框：绿色虚线 + 四角缩放手柄 + 顶部旋转手柄 + 删除按钮
struct StickerSelectionOverlay: View {
    let sticker: PlacedSticker
    let contentSize: CGSize
    let onDelete: () -> Void
    let onSave: () -> Void
    var onUndoPush: (() -> Void)?

    private let handleSize: CGFloat = 8

    @State private var scaleAtDragStart: CGFloat = 1.0
    @State private var isDraggingScale = false
    @State private var startAngle: Double = 0
    @State private var rotationAtDragStart: Double = 0
    @State private var isDraggingRotation = false

    private var borderColor: Color { sticker.isLocked ? .gray.opacity(0.6) : Theme.branchIndicator }

    // 选框紧贴内容，+6 留一点呼吸空间
    private var boxW: CGFloat { contentSize.width * sticker.scale + 6 }
    private var boxH: CGFloat { contentSize.height * sticker.scale + 6 }

    var body: some View {
        // 选框容器（极淡虚线，不抢视觉焦点）
        Rectangle()
            .stroke(borderColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: boxW, height: boxH)
            #if os(macOS)
            // macOS：四角缩放手柄 + 旋转手柄（鼠标精确控制）— 锁定时隐藏
            .overlay(alignment: .topLeading) { if !sticker.isLocked { scaleHandle(xSign: -1, ySign: -1) } }
            .overlay(alignment: .topTrailing) { if !sticker.isLocked { scaleHandle(xSign: 1, ySign: -1) } }
            .overlay(alignment: .bottomLeading) { if !sticker.isLocked { scaleHandle(xSign: -1, ySign: 1) } }
            .overlay(alignment: .bottomTrailing) { if !sticker.isLocked { scaleHandle(xSign: 1, ySign: 1) } }
            .overlay(alignment: .top) {
                if !sticker.isLocked {
                    VStack(spacing: 0) {
                        rotateHandleView
                        Rectangle()
                            .fill(Theme.branchIndicator)
                            .frame(width: 1, height: 12)
                    }
                    .offset(y: -24)
                }
            }
            #endif
            // 锁定图标（右上角）
            .overlay(alignment: .topTrailing) {
                if sticker.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(3)
                        .background(Circle().fill(.white.opacity(0.8)))
                        .offset(x: 10, y: -10)
                }
            }
            // 删除按钮（右上角外侧）— 锁定时隐藏
            .overlay(alignment: .topTrailing) {
                if !sticker.isLocked {
                    Button(action: onDelete) {
                        ZStack {
                            #if os(iOS)
                            Circle().fill(.white).frame(width: 22, height: 22)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Theme.danger)
                            #else
                            Circle().fill(.white).frame(width: 14, height: 14)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.danger)
                            #endif
                        }
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .offset(x: 16, y: -16)
                    #else
                    .offset(x: 10, y: -10)
                    #endif
                }
            }
            .rotationEffect(.degrees(sticker.rotation))
            .position(x: sticker.positionX, y: sticker.positionY)
    }

    // MARK: - Scale Handle

    private func scaleHandle(xSign: CGFloat, ySign: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .stroke(Theme.branchIndicator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
            .offset(x: xSign * -handleSize / 2, y: ySign * -handleSize / 2)
            .padding(18) // 视觉 8px，热区 44px（等比缩放不需要精确瞄角）
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingScale {
                            isDraggingScale = true
                            scaleAtDragStart = sticker.scale
                            onUndoPush?()
                        }
                        let diag = (value.translation.width * xSign + value.translation.height * ySign) / 2
                        sticker.scale = max(0.2, min(4.0, scaleAtDragStart + diag / 80))
                    }
                    .onEnded { _ in
                        isDraggingScale = false
                        onSave()
                    }
            )
            #if os(macOS)
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
    }

    // MARK: - Rotate Handle

    private var rotateHandleView: some View {
        Circle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
                    .font(.system(size: 6))
                    .foregroundColor(Theme.branchIndicator)
            )
            .overlay(Circle().stroke(Theme.branchIndicator, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
            .padding(10)
            .contentShape(Circle())
            .gesture(
                DragGesture(coordinateSpace: .named("stickerCanvas"))
                    .onChanged { value in
                        // PS/Figma 旋转逻辑：atan2(鼠标 - 物体中心)
                        let dx = value.location.x - sticker.positionX
                        let dy = value.location.y - sticker.positionY
                        let currentAngle = atan2(dx, -dy) * 180 / .pi

                        if !isDraggingRotation {
                            isDraggingRotation = true
                            startAngle = currentAngle
                            rotationAtDragStart = sticker.rotation
                            onUndoPush?()
                        }
                        sticker.rotation = rotationAtDragStart + (currentAngle - startAngle)
                    }
                    .onEnded { _ in
                        isDraggingRotation = false
                        onSave()
                    }
            )
            #if os(macOS)
            .onHover { hovering in
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            #endif
    }
}
