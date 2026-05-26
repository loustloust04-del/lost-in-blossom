import SwiftUI

struct IOSDebugPage: View {
    @AppStorage(DebugRenderSettings.themeBackgroundModeKey)
    private var backgroundModeRaw: String = DebugThemeBackgroundMode.original.rawValue

    @AppStorage(DebugRenderSettings.pageIndicatorModeKey)
    private var pageIndicatorModeRaw: String = DebugPageIndicatorMode.proxyInset.rawValue

    private var backgroundMode: DebugThemeBackgroundMode {
        get { DebugThemeBackgroundMode(rawValue: backgroundModeRaw) ?? .original }
    }

    private var pageIndicatorMode: DebugPageIndicatorMode {
        get { DebugPageIndicatorMode(rawValue: pageIndicatorModeRaw) ?? .proxyInset }
    }

    var body: some View {
        List {
            Section {
                ForEach(DebugThemeBackgroundMode.allCases) { mode in
                    Button(action: { backgroundModeRaw = mode.rawValue }) {
                        HStack {
                            Text(mode.displayName)
                                .font(.system(size: Theme.F.body))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if backgroundMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: Theme.F.label, weight: .semibold))
                                    .foregroundColor(Theme.branchIndicator)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Wallpaper 渲染模式")
            } footer: {
                Text("调查：安全区漏白。切换对比 ThemeBackgroundView 在不同挂法下是否真能漫到 status bar / home indicator。")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
            .listRowBackground(Theme.mainBg)

            Section {
                ForEach(DebugPageIndicatorMode.allCases) { mode in
                    Button(action: { pageIndicatorModeRaw = mode.rawValue }) {
                        HStack {
                            Text(mode.displayName)
                                .font(.system(size: Theme.F.body))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if pageIndicatorMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: Theme.F.label, weight: .semibold))
                                    .foregroundColor(Theme.branchIndicator)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("页码点定位模式")
            } footer: {
                Text("调查：页码点飘到列表中。proxy.safeAreaInsets.bottom 在 safe-area 内 GeometryReader 里返回 0，padding 不足；可试 UIApplication 拿真值 / safeAreaInset modifier / VStack flex frame。")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
            .listRowBackground(Theme.mainBg)

            Section {
                Button(action: {
                    backgroundModeRaw = DebugThemeBackgroundMode.original.rawValue
                    pageIndicatorModeRaw = DebugPageIndicatorMode.proxyInset.rawValue
                }) {
                    Text("重置全部到原版")
                        .font(.system(size: Theme.F.body))
                        .foregroundColor(Theme.danger)
                }
                .buttonStyle(.plain)
            } footer: {
                Text("相关文档：docs/research-ios-wallpaper-safearea-root-cause-2026-04-19.md")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
            .listRowBackground(Theme.mainBg)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("开发调试")
        .navigationBarTitleDisplayMode(.inline)
    }
}
