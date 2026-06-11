import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Settings Container

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ProviderManager.self) private var providerManager: ProviderManager?
    @Environment(PresetManager.self) private var presetManager: PresetManager?

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "通用"
        case data = "数据与备份"
        case api = "API"
        case mcp = "MCP 工具"
        case persona = "Prompt"
        case regex = "正则"
        case rightPanel = "右栏"
        case memory = "记忆"
        case sticker = "贴纸"
        case notifications = "通知"
        case appearance = "外观"
        case theme = "主题"
        case health = "健康"
        case debug = "开发调试"
        case hapticTest = "震动测试"
        case ccSettings = "Claude Code"
        case terminal = "终端"
        case fileLibrary = "文件库"
    }

    private var manager: ThemeManager {
        themeManager ?? ThemeManager.shared
    }

    var body: some View {
        let _ = manager.themeChangeID
        iOSSettingsBody
    }

    @State private var selectedSettingsTab: SettingsTab? = nil

    private var iOSSettingsBody: some View {
        NavigationStack {
            List {
                Section {
                    settingsButton(icon: "gearshape", title: "通用", color: Theme.textSecondary, tab: .general)
                    settingsButton(icon: "archivebox", title: "数据与备份", color: Theme.textSecondary, tab: .data)
                    settingsButton(icon: "network", title: "API", color: Theme.textSecondary, tab: .api)
                    settingsButton(icon: "wrench.and.screwdriver", title: "🔧 MCP 工具", color: Theme.textSecondary, tab: .mcp)
                    settingsButton(icon: "text.bubble", title: "Prompt", color: Theme.branchIndicator, tab: .persona)
                    settingsButton(icon: "textformat.abc", title: "正则", color: Theme.textSecondary, tab: .regex)
                }
                Section {
                    settingsButton(icon: "sidebar.right", title: "右栏", color: Theme.textSecondary, tab: .rightPanel)
                    settingsButton(icon: "brain.head.profile", title: "记忆", color: Theme.textSecondary, tab: .memory)
                    settingsButton(icon: "heart.text.square", title: "健康", color: Theme.branchIndicator, tab: .health)
                    settingsButton(icon: "star.circle", title: "贴纸", color: Theme.textSecondary, tab: .sticker)
                    settingsButton(icon: "bell.fill", title: "通知", color: Theme.branchIndicator, tab: .notifications)
                }
                Section {
                    settingsButton(icon: "paintbrush", title: "外观", color: Theme.textSecondary, tab: .appearance)
                    settingsButton(icon: "circle.lefthalf.filled", title: "主题", color: Theme.branchIndicator, tab: .theme)
                }
                Section {
                    settingsButton(icon: "terminal", title: "Claude Code", color: Theme.branchIndicator, tab: .ccSettings)
                    settingsButton(icon: "keyboard", title: "终端", color: Theme.textSecondary, tab: .terminal)
                    settingsButton(icon: "folder", title: "文件库", color: Theme.textSecondary, tab: .fileLibrary)
                }
                Section {
                    settingsButton(icon: "ladybug", title: "开发调试", color: Theme.textSecondary, tab: .debug)
                    settingsButton(icon: "waveform", title: "震动测试", color: Theme.textSecondary, tab: .hapticTest)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedSettingsTab) { tab in
                switch tab {
                case .general: IOSGeneralPage()
                case .appearance: IOSAppearancePage()
                case .theme: IOSThemePage()
                case .persona: PersonaSettingsTab()
                case .api: APISettingsTab()
                case .mcp: MCPSettingsTab()
                case .memory: IOSMemoryPage()
                case .regex: IOSRegexPage()
                case .sticker:
                    IOSStickerPage()
                case .rightPanel:
                    IOSRightPanelPage()
                case .data: DataSettingsTab()
                case .health: HealthSettingsTab()
                case .notifications: IOSNotificationPage()
                case .debug: IOSDebugPage()
                case .hapticTest: HapticTestView()
                case .ccSettings: CCSettingsView()
                case .terminal: TerminalSettingsTab()
                case .fileLibrary: FileLibrarySettingsTab()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.branchIndicator)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBg.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Settings Row Helper (iOS)

    private func settingsButton(icon: String, title: String, color: Color, tab: SettingsTab) -> some View {
        Button {
            selectedSettingsTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted.opacity(0.5))
            }
        }
        .listRowBackground(Theme.mainBg)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }
}

// MARK: - Settings Text Field

struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: Theme.SettingsFont.label))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 90, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.SettingsFont.body))
                .padding(.horizontal, 10)
                .padding(.vertical, Theme.optionRowVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.mainBg.opacity(0.8))
                )
        }
    }
}
