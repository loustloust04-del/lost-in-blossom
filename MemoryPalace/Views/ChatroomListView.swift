import SwiftUI

struct ChatroomListView: View {
    private var service = ChatroomService.shared

    @State private var showCreate = false
    @State private var activeSession: ChatroomSession? = nil
    @State private var sessionToDelete: ChatroomSession? = nil

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("群聊")
                    .font(.system(size: Theme.F.secondary, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if service.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.textMuted.opacity(0.3))
                    Text("还没有群聊")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                    Text("点击 + 让两个 AI 聊起来")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.sessions) { session in
                            ChatroomSessionRow(session: session)
                                .onTapGesture { activeSession = session }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        sessionToDelete = session
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .task { try? await service.fetchSessions() }
        .confirmationDialog("删除群聊", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let s = sessionToDelete {
                    Task { try? await service.deleteSession(id: s.id) }
                }
                sessionToDelete = nil
            }
            Button("取消", role: .cancel) { sessionToDelete = nil }
        } message: {
            if let s = sessionToDelete {
                Text("确定删除「\(s.topic)」？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateChatroomView { newSession in
                activeSession = newSession
                Task { try? await service.fetchSessions() }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            ChatroomView(session: session)
        }
    }
}

// MARK: - Session Row

struct ChatroomSessionRow: View {
    let session: ChatroomSession

    private var isActive: Bool { session.status == "active" }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? Color.green : Theme.textMuted.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.topic)
                    .font(.system(size: Theme.F.label, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(session.ai_a_name) · \(session.ai_b_name)")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                    Text("\(session.rounds) 轮")
                        .font(.system(size: Theme.F.caption))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
