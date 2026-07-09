# 任务：内置浏览器升级（对齐粟粟实现）

> 参考：`/root/projects/SusuPalace` origin/master 分支
> 涉及文件：`MemoryPalace/Views/Web/MiniBrowserView.swift`、`MemoryPalace/Views/Web/BrowserView.swift`
> 难度：🟢 大部分是一两行改动

---

## 改动 1：Cookie 持久化 + 登录态共享（最重要）

**现状**：我们的 WKWebView 用即焚模式，cookie 不保留
**目标**：用 `.default()` datastore，登录态持久化

文件：`MiniBrowserView.swift`

找到 `WKWebViewConfiguration()` 创建的地方，加一行：

```swift
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .default()  // ← 加这行
```

**效果**：用户在浏览器里登录知乎/X → cookie 存下来 → AI 用 browse_url 抓同域网页自动带 cookie

参考粟粟：
```bash
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Views/Web/MiniBrowserView.swift | grep -A5 "websiteDataStore"
```

---

## 改动 2：UA 伪装（防白屏）

**现状**：用 WKWebView 默认 UA，X.com 等反爬站会白屏
**目标**：伪装成真 Safari 18

### 2a. 新建文件 `MemoryPalace/Utils/WebUserAgent.swift`

```swift
import Foundation

enum WebUserAgent {
    static let iOSMobile =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static let macDesktop =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static var platformDefault: String {
        #if os(iOS)
        return iOSMobile
        #else
        return macDesktop
        #endif
    }
}
```

### 2b. 在 MiniBrowserView.swift 的 makeWebView 里加

```swift
webView.customUserAgent = WebUserAgent.platformDefault
```

放在 `webView.navigationDelegate = controller` 之后。

---

## 改动 3：Universal Links 阻断

**现状**：点知乎/X 链接可能被踢去安装原生 app
**目标**：链接全在 app 内打开

在 makeWebView 里加：

```swift
webView.allowsLinkPreview = false
```

---

## 改动 4：iOS 滑动手势

在 makeWebView 里加（`#if os(iOS)` 块内）：

```swift
#if os(iOS)
webView.allowsBackForwardNavigationGestures = true
webView.scrollView.keyboardDismissMode = .onDrag
#endif
```

---

## 改动 5：空白主页快捷站点

**现状**：空白主页只有搜索框 + 历史
**目标**：加常用站点快捷入口

在 `BrowserView.swift` 的 `BrowserBlankHome` 里加快捷站点数组：

```swift
struct QuickSite: Identifiable {
    let id: String
    let name: String
    let urlStr: String
    let symbol: String
    var url: URL? { URL(string: urlStr) }
}

private let quickSites: [QuickSite] = [
    QuickSite(id: "google", name: "Google", urlStr: "https://www.google.com", symbol: "magnifyingglass"),
    QuickSite(id: "zhihu", name: "知乎", urlStr: "https://www.zhihu.com", symbol: "questionmark.bubble.fill"),
    QuickSite(id: "x", name: "X", urlStr: "https://x.com", symbol: "xmark"),
    QuickSite(id: "bilibili", name: "B站", urlStr: "https://m.bilibili.com", symbol: "play.rectangle.fill"),
    QuickSite(id: "github", name: "GitHub", urlStr: "https://github.com", symbol: "chevron.left.forwardslash.chevron.right"),
]
```

渲染成 LazyVGrid 网格（2 列），每个站点一个圆角卡片，点击跳转。

参考粟粟：
```bash
cd /root/projects/SusuPalace
git show origin/master:MemoryPalace/Views/Web/BrowserView.swift | grep -A30 "QuickSite"
```

---

## 改动 6：Cookie 计数显示（可选，锦上添花）

在空白主页的历史列表每条旁边显示 cookie 数量，让用户知道哪些站已登录。

```swift
// 加载 cookie 计数
WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
    var hostMap: [String: Int] = [:]
    for c in cookies {
        hostMap[c.domain, default: 0] += 1
    }
    cookieByHost = hostMap
}
```

历史列表每行加：
```swift
if let count = cookieByHost[entry.host], count > 0 {
    Text("🍪\(count)")
        .font(.caption2)
        .foregroundColor(Theme.textMuted)
}
```

---

## 验证清单

1. [ ] 编译通过
2. [ ] 打开浏览器 → 登录知乎 → 关闭 → 再打开 → 仍然登录（cookie 持久化）
3. [ ] 打开 X.com → 不白屏（UA 伪装生效）
4. [ ] 点知乎文章链接 → 不跳转到 App Store（Universal Links 阻断）
5. [ ] 左滑可后退（iOS 手势）
6. [ ] 空白主页有快捷站点网格
7. [ ] 搜索工具 browse_url 抓已登录站点 → 能拿到登录态内容

---

## 注意事项

1. **不要碰 CLAUDE.md**
2. 改动 1-4 是核心，改动 5-6 是锦上添花
3. 每个改动可以单独 commit
4. commit message：`feat(browser): xxx`
