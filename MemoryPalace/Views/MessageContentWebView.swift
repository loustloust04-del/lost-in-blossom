import SwiftUI
import WebKit

struct MessageContentWebView: UIViewRepresentable {
    let content: String
    let themeColors: [String: String]  // CSS 变量名 → 颜色值
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "heightChanged")
        userContent.add(context.coordinator, name: "linkClicked")

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // 加载本地 HTML 模板
        if let htmlURL = Bundle.main.url(forResource: "message-renderer", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingContent = content
        context.coordinator.pendingTheme = themeColors
        // 如果页面已加载完成，立即渲染；否则等 didFinish 后渲染
        if context.coordinator.pageLoaded {
            context.coordinator.renderContent(in: webView)
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MessageContentWebView
        var pageLoaded = false
        var pendingContent: String = ""
        var pendingTheme: [String: String] = [:]

        init(_ parent: MessageContentWebView) { self.parent = parent }

        // JavaScript → Swift 消息处理
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "heightChanged":
                // JS number 桥接成 NSNumber；CGFloat 不能直接 as? 转，先取 doubleValue。
                if let number = message.body as? NSNumber {
                    let height = CGFloat(number.doubleValue)
                    if height > 0 {
                        DispatchQueue.main.async { self.parent.dynamicHeight = height }
                    }
                }
            case "linkClicked":
                if let urlStr = message.body as? String, let url = URL(string: urlStr) {
                    UIApplication.shared.open(url)
                }
            default: break
            }
        }

        // 页面加载完成后渲染内容
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            renderContent(in: webView)
        }

        func renderContent(in webView: WKWebView) {
            // 先更新主题
            if !pendingTheme.isEmpty {
                let themeJSON = (try? JSONSerialization.data(withJSONObject: pendingTheme))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                webView.evaluateJavaScript("updateTheme(\(themeJSON))")
            }
            // 渲染内容
            let escaped = pendingContent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            webView.evaluateJavaScript("render(`\(escaped)`)")
        }
    }
}
