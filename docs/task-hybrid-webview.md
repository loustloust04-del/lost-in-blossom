# 混合架构 Phase 1 — WebView 消息渲染

> 用 WKWebView + HTML/CSS/JS 替代 SwiftUI Markdown() 渲染消息内容。
> 一次解决：富文本、Markdown 改进、代码高亮、未来 LaTeX/图表。
> 猫按顺序做，每个 commit 做完 push。

---

## 背景

SwiftUI 的 Markdown() 和自定义 parseRichSegments 方案在 ViewBuilder 的类型约束下反复失败。
HTML + CSS 天然支持富文本、颜色、遮罩、代码高亮。已有 ArtifactCanvasView (WKWebView) 作为参考。

---

## Commit 1: HTML 模板 + JS 渲染引擎

创建 `MemoryPalace/Resources/message-renderer.html`

这个文件是消息内容的渲染引擎。通过 JavaScript 的 `render(markdown)` 函数接收原始消息文本，
预处理富文本标记，再用 marked.js 渲染 Markdown，输出到 DOM。

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
:root {
    --text-color: #1a1a1a;
    --text-muted: #888;
    --bg-color: transparent;
    --code-bg: rgba(0,0,0,0.04);
    --spoiler-bg: #333;
    --spoiler-revealed-bg: rgba(0,0,0,0.06);
    --link-color: #007AFF;
    --font-size: 15px;
    --line-height: 1.6;
    --font-family: -apple-system, system-ui, sans-serif;
    --code-font: 'SF Mono', Menlo, Consolas, monospace;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: var(--font-family);
    font-size: var(--font-size);
    line-height: var(--line-height);
    color: var(--text-color);
    background: var(--bg-color);
    word-wrap: break-word;
    overflow-wrap: break-word;
    -webkit-text-size-adjust: none;
}
p { margin-bottom: 0.6em; }
p:last-child { margin-bottom: 0; }
a { color: var(--link-color); text-decoration: none; }
strong { font-weight: 600; }
em { font-style: italic; }

/* 行内代码 */
code {
    font-family: var(--code-font);
    font-size: 0.88em;
    background: var(--code-bg);
    padding: 1px 4px;
    border-radius: 3px;
}

/* 代码块 */
pre {
    background: var(--code-bg);
    padding: 10px 12px;
    border-radius: 8px;
    overflow-x: auto;
    margin: 8px 0;
    -webkit-overflow-scrolling: touch;
}
pre code {
    background: none;
    padding: 0;
    font-size: 12.5px;
    line-height: 1.5;
}

/* 引用 */
blockquote {
    border-left: 3px solid var(--text-muted);
    padding-left: 12px;
    color: var(--text-muted);
    margin: 8px 0;
}

/* 列表 */
ul, ol { padding-left: 1.5em; margin: 4px 0; }
li { margin-bottom: 2px; }

/* 富文本：彩色文字 */
.rich-color { /* color 通过 inline style 设置 */ }

/* 富文本：剧透黑块 */
.spoiler {
    background: var(--spoiler-bg);
    color: transparent;
    border-radius: 4px;
    padding: 1px 6px;
    cursor: pointer;
    transition: all 0.3s ease;
    -webkit-tap-highlight-color: transparent;
}
.spoiler.revealed {
    color: var(--text-color);
    background: var(--spoiler-revealed-bg);
}

/* 图片 */
img { max-width: 100%; border-radius: 8px; }

/* 表格 */
table { border-collapse: collapse; margin: 8px 0; width: 100%; }
th, td { border: 1px solid var(--code-bg); padding: 6px 10px; text-align: left; }
th { background: var(--code-bg); font-weight: 600; }
</style>
</head>
<body>
<div id="content"></div>
<script>
// ── marked.js (内联，避免外部文件加载) ──
// 猫：这里需要内联 marked.min.js 的内容。
// 从 https://cdn.jsdelivr.net/npm/marked/marked.min.js 下载，
// 粘贴到这个 script 标签里。不要用 <script src>，iOS 本地文件加载有限制。
// 如果文件太大，可以用 marked 的精简版 (marked.min.js 约 40KB)。
</script>
<script>
// ── 富文本预处理 ──
function preprocessRichText(text) {
    // {color:xxx}文字{/color} → <span>
    text = text.replace(/\{color:(\w+)\}([\s\S]*?)\{\/color\}/g,
        '<span class="rich-color" style="color:$1">$2</span>');
    // ||spoiler|| → 点击展开的黑块
    text = text.replace(/\|\|(.+?)\|\|/g,
        '<span class="spoiler" onclick="this.classList.toggle(\'revealed\')">$1</span>');
    return text;
}

// ── 渲染入口 ──
function render(markdown) {
    if (typeof marked === 'undefined') {
        // marked 还没加载，直接显示纯文本
        document.getElementById('content').innerText = markdown;
        notifyHeight();
        return;
    }
    var processed = preprocessRichText(markdown);
    document.getElementById('content').innerHTML = marked.parse(processed, {
        breaks: true,      // 换行符转 <br>
        gfm: true,         // GitHub Flavored Markdown
        headerIds: false,   // 不给标题加 id
        mangle: false       // 不转义邮箱
    });
    notifyHeight();
}

// ── 主题更新 ──
function updateTheme(vars) {
    var root = document.documentElement;
    for (var key in vars) {
        root.style.setProperty('--' + key, vars[key]);
    }
    notifyHeight();
}

// ── 高度通知 ──
// 渲染完成后把内容高度通知 Swift 侧，用于动态调整 WKWebView 的 frame。
function notifyHeight() {
    var h = document.getElementById('content').scrollHeight;
    window.webkit.messageHandlers.heightChanged.postMessage(h);
}

// 监听图片加载完成后重新通知高度
new MutationObserver(function() {
    document.querySelectorAll('img').forEach(function(img) {
        if (!img.dataset.observed) {
            img.dataset.observed = '1';
            img.onload = notifyHeight;
        }
    });
}).observe(document.getElementById('content'), { childList: true, subtree: true });

// 拦截链接点击，交给 Swift 处理
document.addEventListener('click', function(e) {
    var a = e.target.closest('a');
    if (a && a.href) {
        e.preventDefault();
        window.webkit.messageHandlers.linkClicked.postMessage(a.href);
    }
});
</script>
</body>
</html>
```

同时下载 marked.min.js 并内联到 HTML 里：
```bash
curl -sL https://cdn.jsdelivr.net/npm/marked@12/marked.min.js -o /tmp/marked.min.js
```
把 marked.min.js 的内容粘贴到 HTML 里 `// 猫：这里需要内联 marked.min.js 的内容` 的位置，
用 `<script>` 标签包裹。

将 message-renderer.html 添加到 Xcode 项目的 Copy Bundle Resources 里
（确保它会被打包进 App Bundle）。

---

## Commit 2: MessageContentWebView 组件

创建 `MemoryPalace/Views/MessageContentWebView.swift`

```swift
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
                if let height = message.body as? CGFloat, height > 0 {
                    DispatchQueue.main.async { self.parent.dynamicHeight = height }
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
```

---

## Commit 3: CardFlowView 集成

在 CardFlowView 中替换 assistant 消息的 Markdown() 渲染。

找到 assistant 消息渲染的 `else if !displayText.isEmpty` 分支（大约 1489 行）。

**替换前**（当前的 parseRichSegments + RichSegmentRenderer 方案）：
```swift
let richSegs = parseRichSegments(displayText)
if richSegs.count == 1, case .markdown = richSegs[0] {
    Markdown(displayText) ...
} else {
    VStack ... ForEach ... RichSegmentRenderer ...
}
```

**替换后**：
```swift
// 混合架构：用 WebView 渲染消息内容（支持富文本 + Markdown + 代码高亮）
MessageContentWebView(
    content: displayText,
    themeColors: [
        "text-color": Theme.textPrimary.toHex(),
        "text-muted": Theme.textMuted.toHex(),
        "code-bg": Theme.mainBg.toHex(),
        "font-size": "\(13.5 * (fontScale > 0 ? fontScale : 1.0))px",
        "line-height": "\(1.5 * lineSpacingScale)"
    ],
    dynamicHeight: $messageWebViewHeight
)
.frame(height: messageWebViewHeight)
```

需要在 bubbleBody 附近加一个 @State：
```swift
@State private var messageWebViewHeight: CGFloat = 44
```

**注意**：
- 只替换 assistant 消息的渲染路径
- 用户消息保留原有的 Text() 渲染（用户消息不需要 Markdown 和富文本）
- 保留 ArtifactDetector 的逻辑（strip 代码块 + 显示卡片）
- 保留 thinking block 的折叠 UI（在 WebView 之前的位置不变）

### Theme.Color.toHex() 扩展

如果还没有，在 Theme 或 Color 扩展里加：
```swift
extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
```

---

## Commit 4: marked.js 打包验证

确保 marked.min.js 已内联到 message-renderer.html 里，且 HTML 文件在 Xcode 项目的
Copy Bundle Resources 列表中（否则运行时 Bundle.main.url 返回 nil）。

在 Xcode 项目的 Build Phases → Copy Bundle Resources 里检查 message-renderer.html 是否存在。
如果不存在，手动添加。

---

## 测试方法

编译后在 App 里：
1. 跟 AI 聊天，看普通 Markdown 渲染是否正常（标题、列表、代码块、粗体）
2. 发一条包含 `{color:red}红色文字{/color}` 的消息或让 AI 回复包含它，看是否变红
3. 发一条包含 `||隐藏内容||` 的消息，看是否有黑块，点击后展开
4. 检查消息气泡高度是否正确自适应（不截断、不多余空白）
5. 检查深色/浅色模式切换后颜色是否正确

---

## 注意

- 不要动用户消息的渲染路径（保留 Text()）
- 不要动 thinking block 的折叠 UI
- 不要动 ArtifactDetector 的逻辑
- HTML 文件必须加入 Xcode 的 Copy Bundle Resources
- marked.js 必须内联不能外链（iOS WKWebView 本地文件安全限制）
- 每个 commit 独立 push，不要一次全做
