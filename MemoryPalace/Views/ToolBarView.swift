import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tool Bar (选中展开文字，长按拖拽排序)

struct ToolBarView: View {
    @Binding var selectedToolId: String
    @Environment(RightPanelToolManager.self) private var toolManager: RightPanelToolManager?

    @State private var showDrawer = false
    @State private var draggingToolId: String? = nil

    private var pinnedTools: [RightPanelTool] {
        toolManager?.pinnedTools ?? []
    }

    private let springAnim: Animation = .spring(response: 0.45, dampingFraction: 0.75)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pinnedTools) { tool in
                let isSelected = tool.id == selectedToolId
                Button {
                    withAnimation(springAnim) {
                        selectedToolId = tool.id
                    }
                } label: {
                    HStack(spacing: isSelected ? 5 : 0) {
                        Image(systemName: tool.icon)
                            .font(.system(size: isIOSStyle ? 14 : 11, weight: .medium))

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
                    .frame(height: isIOSStyle ? 36 : 28)
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

            // 抽屉按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showDrawer.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: isIOSStyle ? 14 : 11, weight: .medium))
                    .foregroundColor(showDrawer ? Theme.branchIndicator : Theme.textMuted)
                    .padding(.horizontal, 8)
                    .frame(height: isIOSStyle ? 36 : 28)
            }
            .buttonStyle(.plain)
        }
        .animation(springAnim, value: pinnedTools.map(\.id))
        .animation(springAnim, value: selectedToolId)
        .padding(isIOSStyle ? 4 : 3)
        .glassEffectCompat(tint: Color.white.opacity(0.06), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showDrawer) {
            ToolDrawerView(selectedToolId: $selectedToolId, onDismiss: { showDrawer = false })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var isIOSStyle: Bool {
        true
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
