import SwiftUI

// MARK: - MCP Settings Tab

struct MCPSettingsTab: View {
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?
    @AppStorage("apiSelectedProvider") private var apiSelectedProviderId = "openrouter"

    @State private var editingServer: MCPServerConfig?
    @State private var isAddingServer = false

    private var selectedProvider: APIProvider? {
        providerManager?.providers.first(where: { $0.id == apiSelectedProviderId })
    }

    private var isAnthropic: Bool {
        selectedProvider?.type == .anthropic
    }

    private var servers: [MCPServerConfig] {
        selectedProvider?.mcpServers ?? []
    }

    var body: some View {
        List {
            // 说明
            Section {
                Text("MCP 让 AI 连接外部工具（文件系统、数据库、API 等）。")
                    .font(.system(size: Theme.F.secondary))
                    .foregroundColor(Theme.textMuted)
            }
            .listRowBackground(Theme.mainBg)

            if !isAnthropic {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Theme.textMuted)
                        Text("MCP 仅支持 Claude API。请在 API 设置里切换到 Anthropic 类型的提供商。")
                            .font(.system(size: Theme.F.secondary))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.mainBg)
            } else {
                if servers.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.textMuted.opacity(0.4))
                            Text("还没有 MCP Server")
                                .font(.system(size: Theme.F.body))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .listRowBackground(Theme.mainBg)
                    .listRowSeparator(.hidden)
                } else {
                    Section("已连接的 Server") {
                        ForEach(servers) { server in
                            Button {
                                isAddingServer = false
                                editingServer = server
                            } label: {
                                serverRow(server)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    providerManager?.removeMCPServer(id: server.id, from: apiSelectedProviderId)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.mainBg)
                }

                Section {
                    Button {
                        editingServer = nil
                        isAddingServer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(Theme.branchIndicator)
                            Text("添加 MCP Server")
                                .font(.system(size: Theme.F.body))
                                .foregroundColor(Theme.branchIndicator)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Theme.mainBg)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBg.ignoresSafeArea())
        .navigationTitle("MCP 工具")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingServer) {
            MCPServerEditSheet(server: nil) { newServer in
                providerManager?.addOrUpdateMCPServer(newServer, for: apiSelectedProviderId)
            }
        }
        .sheet(item: $editingServer) { server in
            MCPServerEditSheet(server: server) { updated in
                providerManager?.addOrUpdateMCPServer(updated, for: apiSelectedProviderId)
            }
        }
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.isEnabled ? Color.green : Theme.textMuted.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.isEmpty ? "（未命名）" : server.name)
                    .font(.system(size: Theme.F.label, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(server.url)
                    .font(.system(size: Theme.F.caption))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { newValue in
                    var updated = server
                    updated.isEnabled = newValue
                    providerManager?.addOrUpdateMCPServer(updated, for: apiSelectedProviderId)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - MCP Server Edit Sheet

struct MCPServerEditSheet: View {
    let server: MCPServerConfig?
    let onSave: (MCPServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @State private var token: String

    private var isNew: Bool { server == nil }

    init(server: MCPServerConfig?, onSave: @escaping (MCPServerConfig) -> Void) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: server?.url ?? "")
        _token = State(initialValue: server?.authorizationToken ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.branchIndicator)
                Spacer()
                Text(isNew ? "添加 MCP Server" : "编辑 MCP Server")
                    .font(.system(size: Theme.F.sectionHeader, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.plain)
                    .foregroundColor(canSave ? .white : Theme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(canSave ? Theme.branchIndicator : Theme.textMuted.opacity(0.3)))
                    .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("名字") {
                        TextField("imprint-memory", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: Theme.F.body))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                    }

                    field("URL") {
                        TextField("https://mcp.example.com/sse", text: $url)
                            .textFieldStyle(.plain)
                            .font(.system(size: Theme.F.body))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                    }

                    field("Token（可选）") {
                        TextField("Bearer token", text: $token)
                            .textFieldStyle(.plain)
                            .font(.system(size: Theme.F.body))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.mainBg.opacity(0.8)))
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: 500, minHeight: 360)
        .frame(maxWidth: .infinity)
        .background(Theme.sidebarBg)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: Theme.F.secondary))
                .foregroundColor(Theme.textMuted)
            content()
        }
    }

    private func save() {
        guard canSave else { return }
        var result = server ?? MCPServerConfig(name: "", url: "")
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.url = url.trimmingCharacters(in: .whitespaces)
        result.authorizationToken = token.trimmingCharacters(in: .whitespaces)
        onSave(result)
        dismiss()
    }
}
