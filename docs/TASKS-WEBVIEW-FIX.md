# WebView 白屏 + 无限延长修复

> 日期：2026-06-10
> 优先级：P0（触发后整个对话不可见，必须切后台再进）
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`

---

## 问题描述

混合渲染架构中，包含 `{color:}` 或 `||spoiler||` 的消息走 WebView 渲染。
两个致命问题：
1. **白屏**：WebView 加载 HTML 模板需要时间，在此期间 `messageWebViewHeight = 0` → `.frame(height: 0)` → 消息不可见
2. **对话框无限延长**：某些内容导致 JS 端 `scrollHeight` 计算异常，高度变成巨大的值 → 对话框撑到屏幕外，后续消息找不到

---

## Task 1: WebView 高度安全边界

**文件**: `MemoryPalace/Views/CardFlowView.swift`

**当前代码**（第 1298 行）:
```swift
@State private var messageWebViewHeight: CGFloat = 0
```

**当前代码**（第 1526 行）:
```swift
.frame(height: messageWebViewHeight)
```

**改成**:
```swift
// 第 1298 行：初始值给 44（一行文字的最小高度），避免加载期间 height=0 白屏
@State private var messageWebViewHeight: CGFloat = 44

// 第 1526 行：加上下限 clamp
.frame(height: max(44, min(messageWebViewHeight, UIScreen.main.bounds.height * 3)))
```

**原理**:
- 最小 44pt：WebView 加载完成前至少占一行高度，不白屏
- 最大 3 倍屏幕高度：scrollHeight 异常时不会把对话撑到无穷远
- WebView 内部仍可滚动（scrollView.isScrollEnabled 需要在超高时打开）

**commit**: `fix(render): WebView height safety clamp — min 44pt, max 3x screen`

---

## Task 2: WebView 超高时启用内部滚动

**文件**: `MemoryPalace/Views/MessageContentWebView.swift`

**当前代码**（第 31 行）:
```swift
webView.scrollView.isScrollEnabled = false
```

**问题**: 当内容超过 3 倍屏幕高度被 clamp 后，用户看不到被截断的内容。

**改成**: 在 Coordinator 的 heightChanged 处理里动态控制滚动：

```swift
case "heightChanged":
    if let number = message.body as? NSNumber {
        let height = CGFloat(number.doubleValue)
        if height > 0 {
            let maxH = UIScreen.main.bounds.height * 3
            let clamped = min(height, maxH)
            // 超高内容启用内部滚动
            DispatchQueue.main.async {
                self.parent.dynamicHeight = clamped
                // 找到 webView 并设置滚动
                // 注意：这里需要持有 webView 的引用
            }
        }
    }
```

**更好的做法**: 在 Coordinator 里持有 webView 的弱引用：

```swift
class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var parent: MessageContentWebView
    weak var webView: WKWebView?  // 新增
    // ...
}

// makeUIView 里：
context.coordinator.webView = webView

// heightChanged handler 里：
let maxH = UIScreen.main.bounds.height * 3
let needsScroll = height > maxH
self.parent.dynamicHeight = needsScroll ? maxH : height
self.webView?.scrollView.isScrollEnabled = needsScroll
```

**commit**: `fix(render): enable WebView internal scroll when content exceeds 3x screen`

---

## Task 3: WebView 加载失败 fallback

**文件**: `MemoryPalace/Views/MessageContentWebView.swift`

在 Coordinator 里加导航失败处理：

```swift
func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    // HTML 模板加载失败 → 用一个安全高度让气泡至少可见
    DispatchQueue.main.async {
        if self.parent.dynamicHeight < 44 {
            self.parent.dynamicHeight = 44
        }
    }
}

func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    DispatchQueue.main.async {
        if self.parent.dynamicHeight < 44 {
            self.parent.dynamicHeight = 44
        }
    }
}
```

**commit**: `fix(render): WebView navigation failure fallback height`

---

## Task 4: JS 端高度计算加安全检查

**文件**: `MemoryPalace/Resources/message-renderer.html`

**当前代码**（约第 246-248 行）:
```javascript
function notifyHeight() {
    var h = document.getElementById('content').scrollHeight;
    window.webkit.messageHandlers.heightChanged.postMessage(h);
}
```

**改成**:
```javascript
function notifyHeight() {
    var el = document.getElementById('content');
    if (!el) return;
    var h = el.scrollHeight;
    // 安全检查：高度为 0 或者异常大时用 fallback
    if (h <= 0) h = 44;
    if (h > 10000) h = 10000;  // 硬上限，Swift 侧会再 clamp 到 3x 屏幕
    window.webkit.messageHandlers.heightChanged.postMessage(h);
}
```

**commit**: `fix(render): JS height calculation safety bounds`

---

## 规则

- 按 Task 1-4 顺序做，每个单独 commit + push
- 不改 needsWebView 的判断逻辑（{color:} 和 || 的检测不动）
- 不改 MarkdownUI 渲染路径（它没问题）
- 禁触文件清单：`ConversationViewModel.swift`, `ChatService.swift`, `SidebarView.swift`

---

## 验证清单

- [ ] build 通过
- [ ] 发一条包含 `{color:red}测试{/color}` 的消息 → 气泡立即可见（不白屏），红色文字正常
- [ ] 发一条包含 `||剧透||` 的消息 → 气泡可见，黑色遮罩正常
- [ ] 连续发多条富文本消息 → 对话不会无限延长，每条气泡高度合理
- [ ] 切换到包含历史富文本消息的旧对话 → 消息全部可见（不白屏）
- [ ] 暗色模式下以上全部正常
- [ ] 普通 Markdown 消息渲染不受影响（走 MarkdownUI 路径不变）
