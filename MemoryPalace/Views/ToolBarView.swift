import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tool Bar (选中展开文字，长按拖拽排序)

/// 五渡侦察计数器（struct 会被无限重建，数据必须住在外面）
final class DockProbe {
    static var inits = 0
    static var appears = 0
    static var changes = 0
    static var anims = 0
}

struct ToolBarView: View {
    init(selectedToolId: Binding<String>) {
        self._selectedToolId = selectedToolId
        DockProbe.inits += 1
    }
    @Binding var selectedToolId: String
    @Environment(RightPanelToolManager.self) private var toolManager: RightPanelToolManager?

    @State private var showDrawer = false
    @State private var draggingToolId: String? = nil
    /// 胶囊视觉位（selectedToolId 的镜像）。四修（09-02，兔兔三报仍瞬移）：
    /// 隐式 value 版、@State 镜像版、matchedGeometry+@State 版实机全灭——三种机制
    /// 同死指向同一件事：page2 挂在 UIHostingController.rootView 整体重挂的管线上
    /// （PagingContainerView.updatePages），切工具那次更新里 ToolBarView 身份大概率
    /// 被重建，@State 归零、onChange 不触发、matched 没有「上一帧」可飞。
    /// 对策：镜像态换 **AppStorage 底**（重建也带着旧位置），双保险驱动——
    /// 身份还在→onChange 显式事务；身份被重建→onAppear 发现错位，下一拍动画归位。
    /// 两条路殊途同归：胶囊总是「从旧工具飞到新工具」。
    @AppStorage("dockCapsuleVisualId") private var capsuleId: String = ""
    /// 五渡侦察（临时探针，查明后拆）：四种动画机制实机全灭，不再隔空猜——
    /// 让实机自己报数。i=本视图被重建次数 a=onAppear c=onChange t=withAnimation 执行数
    /// 滑点=同事务驱动的位移测试球：它滑=事务活着（是胶囊机制的锅）；它瞬移=事务整个被吞
    @State private var probeDotRight = false

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
                // Button → onTapGesture（0a3edb2e 之后兔兔仍说「不灵敏不丝滑」：
                // ScrollView 里的 Button 要先过拖拽判定才收 tap，天生一拍延迟；
                // 裸 tap gesture 即点即发）。动画改 matchedGeometryEffect：
                // 底色胶囊是「同一个视图」在工具间飞——不依赖每个 label 的隐式动画，
                // 前两刀都死在那条路上（value 版被换枝吞、镜像版实机也没跑起来）。
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
                // 七渡=手感校准（兔兔：粟粟是「新胶囊撑开把旁边顶走」，不是药丸飞行）。
                // 六渡修稳身份后她的原版机制能活了：底色常驻随选中渐显（不做条件插拔，
                // 插拔没法插值），宽度/间距/内距的变化都发生在 onChange 的显式事务里
                // ——文字长出来、旁边被顶开，就是她那个手感。matchedGeometry 药丸退役。
                .background(
                    Capsule()
                        .fill(Theme.branchIndicator.opacity(isSelected ? 0.14 : 0))
                )
                .opacity(draggingToolId == tool.id ? 0.3 : 1)
                .contentShape(Capsule())
                .onTapGesture {
                    // 真选中即时赋值（面板零延迟），胶囊撑开走镜像态的动画事务
                    selectedToolId = tool.id
                }
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

            // 五渡侦察面板（临时）：i重建 a出现 c变更 t动画 + 滑点（事务活性测试球）
            HStack(spacing: 3) {
                Text("i\(DockProbe.inits) a\(DockProbe.appears) c\(DockProbe.changes) t\(DockProbe.anims)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Theme.textMuted.opacity(0.75))
                ZStack(alignment: probeDotRight ? .trailing : .leading) {
                    Capsule().fill(Theme.textMuted.opacity(0.15)).frame(width: 22, height: 8)
                    Circle().fill(Theme.branchIndicator).frame(width: 8, height: 8)
                }
            }

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
            Image(systemName: "house")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHomeSelected ? Theme.textSecondary : Theme.textMuted)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(Theme.branchIndicator.opacity(isHomeSelected ? 0.14 : 0))
                )
                .contentShape(Capsule())
                .onTapGesture { selectedToolId = "home" }
        }
        .animation(springAnim, value: pinnedTools.map(\.id))
        .onAppear {
            DockProbe.appears += 1
            if capsuleId.isEmpty {
                capsuleId = selectedToolId          // 首装：直接落位不演
            } else if capsuleId != selectedToolId {
                // 身份被重建后的补飞：首帧按旧位画好，下一拍动画归位
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    withAnimation(switchAnim) { capsuleId = selectedToolId }
                }
            }
        }
        .onChange(of: selectedToolId) { _, new in
            DockProbe.changes += 1
            withAnimation(switchAnim) {
                DockProbe.anims += 1
                capsuleId = new
                probeDotRight.toggle()   // 滑点与胶囊同一个事务
            }
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
