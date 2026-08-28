// html 卡片点开后真正渲染网页的那层 WebView。
// 2026-08-27 补搬：下午搬 HTMLArtifactCardView 时盘依赖漏了它，CI #179 报
// 「cannot find HTMLPreviewWebView in scope」才发现。只依赖 Theme，我们全有。
// 搬入时删掉 #if os(macOS) 分支——project.yml 已无 macOS target。

import SwiftUI

struct HTMLPreviewWebView: View {
    let content: String
    var backdrop: Color = Theme.mainBg
    /// W2：递增触发重注入 srcdoc（绕过 WebViewHost 的 payload 去重）
    var refreshToken: Int = 0
    var onPageTitle: ((String) -> Void)? = nil
    var onLoadingChanged: ((Bool) -> Void)? = nil
    /// W3：本地模式 OFF 时点链接进 mini browser；nil 或本地模式 ON 时外开系统浏览器
    var onOpenLink: ((URL) -> Void)? = nil

    @State private var isReady = false
    @State private var errorMessage: String?
    @State private var artifactErrors: [String] = []

    var body: some View {
        ZStack(alignment: .top) {
            // W1 联网渲染：本地模式关闭 → 放宽子资源 CSP 的 shell（fetch 仍封）；开 → 全封 shell。
            // 开关在 sheet 打开时生效（WebView 创建即定型，切开关重开预览即可）
            WebViewHost(
                htmlResourceName: LocalMode.isOn ? "html-preview" : "html-preview-online",
                payload: [
                    "type": "setContent",
                    "content": content,
                    "refreshToken": refreshToken
                ],
                onMessage: handleMessage
            )

            if !artifactErrors.isEmpty {
                artifactErrorBar
            }

            if !isReady {
                VStack {
                    Spacer()
                    Text(errorMessage ?? "正在加载预览")
                        .font(.system(size: Theme.F.secondary))
                        .foregroundColor(errorMessage == nil ? Theme.textMuted : Theme.branchIndicator)
                        .padding(10)
                        .background(Theme.mainBg.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                }
            }
        }
        .background(backdrop)
        .onChange(of: content) { _, _ in
            artifactErrors = []
        }
        .onChange(of: refreshToken) { _, _ in
            artifactErrors = []
            onLoadingChanged?(true)
        }
    }

    private var artifactErrorBar: some View {
        HStack(spacing: 8) {
            Text(artifactErrors.joined(separator: " · "))
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.branchIndicator)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                artifactErrors = []
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Theme.F.caption, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.mainBg.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 1)
        }
    }

    private func handleMessage(_ message: WebViewBridgeMessage) {
        switch message.type {
        case "ready":
            isReady = true
            errorMessage = nil
        case "error":
            errorMessage = message.message ?? "预览加载失败"
        case "artifactError":
            let text = message.message ?? "脚本错误"
            if !artifactErrors.contains(text), artifactErrors.count < 3 {
                artifactErrors.append(text)
            }
        case "pageTitle":
            onPageTitle?(message.title ?? "")
        case "pageLoaded":
            onLoadingChanged?(false)
        case "openLink":
            if let onOpenLink, !LocalMode.isOn,
               let href = message.href, let url = URL(string: href),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                onOpenLink(url)
            } else {
                openExternalWebViewLink(message.href)
            }
        default:
            break
        }
    }
}
