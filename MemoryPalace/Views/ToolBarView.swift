import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tool Bar (选中展开文字，长按拖拽排序)

struct ToolBarView: View {
    @Binding var selectedToolId: String
    @Environment(RightPanelToolManager.self) private var toolManager: RightPanelToolManager?

    @State private var showDrawer = false
    @State private var draggingToolId: String? = nil
    /// 胶囊视觉位（selectedToolId 的镜像）。
    /// 08-29 ddaeecf9 把弹簧挂回 .animation(value:) 后兔兔实机仍看不到过渡——
    /// 右滑页每次切工具 panelContent 整棵换枝，隐式动画在这种结构变动下被吞。
    /// 改法：真选中即时赋值（面板立刻切，保住 08-12 的修复），胶囊视觉走本地镜像态，
    /// onChange 里用显式 withAnimation 驱动——显式事务不怕父级换枝。
    @State private var capsuleId: String = ""

    private var pinnedTools: [RightPanelTool] {
        toolManager?.pinnedTools ?? []
    }

    /// 切页动画：原 0.45s 弹簧，点一下要等近半秒才见反应（兔兔实测「反应不过来」）。
    /// 拖拽重排仍用弹簧手感，纯切页用短促的 easeOut。
    private let springAnim: Animation = .spring(response: 0.32, dampingFraction: 0.82)
    /// dock 选中胶囊的展开动画。
    /// 08-12 那刀为治「点了要等半秒才见反应」，把它从弹簧改成了 easeOut——
    /// 治好了迟滞，但也把胶囊撑开时那口弹性一起去掉了（兔兔 08-28 说粟粟那边「有个动画」，
    /// 指的就是这点弹）。
    /// 现在两全：selectedToolId 仍是无动画直接赋值（页面立刻切，保住 08-12 的修复），
    /// 只有这条样式动画换回弹簧。她那边是 0.45/0.75，但她整体切页也走这条、必须留余量；
    /// 我们只驱动一个胶囊的宽度与底色，取更快的 0.30/0.78——弹一下就停，不拖尾。
    private let switchAnim: Animation = .spring(response: 0.30, dampingFraction: 0.78)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
            ForEach(pinnedTools) { tool in
                let isSelected = tool.id == (capsuleId.isEmpty ? selectedToolId : capsuleId)
                Button {
                    // 先无动画置位（内容立刻切过去），样式变化交给短动画——
                    // 否则要等整条弹簧跑完才看到新页面
                    selectedToolId = tool.id
                } label: {
                    HStack(spacing: isSelected ? 5 : 0) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14, weight: .medium))

                        Text(tool.name)
                            .font(.system(size: Theme.F.secondary, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: isSelected ? nil : 0, alignment: .leading)
                            .opacity(isSelected ? 1 : 0)
                            .clipped()
                    }
                    .foregroundColor(isSelected ? Theme.textSecondary : Theme.textMuted)
                    .padding(.horizontal, isSelected ? 14 : 10)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(Theme.branchIndicator.opacity(isSelected ? 0.14 : 0))
                    )
                    .opacity(draggingToolId == tool.id ? 0.3 : 1)
                }
                .buttonStyle(.plain)
                .onDrag {
                    draggingToolId = tool.id
                    return NSItemProvider(object: tool.id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ToolReorderDropDelegate(
                    tool: tool,
                    toolManager: toolManager,
                    draggingToolId: $draggingToolId
                ))
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(springAnim) {
                            toolManager?.setEnabled(tool.id, false)
                            if tool.id == selectedToolId,
                               let fallback = toolManager?.fallbackToolId(from: selectedToolId) {
                                selectedToolId = fallback
                            }
                        }
                    } label: {
                        Label("移除", systemImage: "minus.circle")
                    }
                }
            }
                } // inner tools HStack
            } // horizontal ScrollView

            // 抽屉按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showDrawer.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showDrawer ? Theme.branchIndicator : Theme.textMuted)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 🏠 桌面键：HStack 内、ScrollView 外最右，固定不可拖不可删（对齐粟粟布局）
            let isHomeSelected = ((capsuleId.isEmpty ? selectedToolId : capsuleId) == "home")
            Button {
                selectedToolId = "home"
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHomeSelected ? Theme.textSecondary : Theme.textMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(Theme.branchIndicator.opacity(isHomeSelected ? 0.14 : 0))
                    )
            }
            .buttonStyle(.plain)
        }
        .animation(springAnim, value: pinnedTools.map(\.id))
        .onAppear { capsuleId = selectedToolId }
        .onChange(of: selectedToolId) { _, new in
            withAnimation(switchAnim) { capsuleId = new }
        }
        .padding(4)
        .glassEffectCompat(tint: Color.white.opacity(0.06), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showDrawer) {
            ToolDrawerView(selectedToolId: $selectedToolId, onDismiss: { showDrawer = false })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Drag Reorder Delegate

struct ToolReorderDropDelegate: DropDelegate {
    let tool: RightPanelTool
    let toolManager: RightPanelToolManager?
    @Binding var draggingToolId: String?

    func performDrop(info: DropInfo) -> Bool {
        guard let fromId = draggingToolId else { return false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toolManager?.reorder(fromId: fromId, toId: tool.id)
        }
        draggingToolId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromId = draggingToolId, fromId != tool.id else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toolManager?.reorder(fromId: fromId, toId: tool.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}

    func validateDrop(info: DropInfo) -> Bool { true }
}

// MARK: - Tool Drawer (长按弹出的工具网格)

struct ToolDrawerView: View {
    @Binding var selectedToolId: String
    var onDismiss: () -> Void
    @Environment(RightPanelToolManager.self) private var toolManager: RightPanelToolManager?

    @State private var draggingToolId: String? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var allTools: [RightPanelTool] {
        toolManager?.allToolsSorted ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("工具箱")
                    .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("完成") { onDismiss() }
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.branchIndicator)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Text("拖拽排序，点击切换")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
                .padding(.bottom, 8)

            // Grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(allTools) { tool in
                    toolCell(tool)
                        .onDrag {
                            draggingToolId = tool.id
                            return NSItemProvider(object: tool.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ToolReorderDropDelegate(
                            tool: tool,
                            toolManager: toolManager,
                            draggingToolId: $draggingToolId
                        ))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: allTools.map(\.id))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Spacer()
        }
        .background(Theme.sidebarBg)
    }

    private func toolCell(_ tool: RightPanelTool) -> some View {
        let isActive = tool.id == selectedToolId

        return Button {
            if tool.isEnabled {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedToolId = tool.id
                }
                onDismiss()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    toolManager?.setEnabled(tool.id, true)
                    selectedToolId = tool.id
                }
                onDismiss()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tool.icon)
                    .font(.system(size: 20))
                    .foregroundColor(
                        !tool.isEnabled ? Theme.textMuted.opacity(0.4)
                        : isActive ? Theme.branchIndicator
                        : Theme.textSecondary
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                !tool.isEnabled ? Theme.mainBg.opacity(0.3)
                                : isActive ? Theme.branchIndicator.opacity(0.12)
                                : Theme.mainBg.opacity(0.8)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                !tool.isEnabled ? Theme.accent.opacity(0.15)
                                : isActive ? Theme.branchIndicator.opacity(0.3)
                                : Theme.accent.opacity(0.4),
                                lineWidth: 1
                            )
                    )

                Text(tool.name)
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(
                        !tool.isEnabled ? Theme.textMuted.opacity(0.4)
                        : isActive ? Theme.textPrimary
                        : Theme.textMuted
                    )
            }
            .opacity(draggingToolId == tool.id ? 0.3 : 1)
        }
        .buttonStyle(.plain)
    }
}
