# Artifacts 画布

> 聊天中渲染交互式内容（HTML/代码预览/图表）。
> Bunny 说"实在做不成就算了"—— 评估可行性后决定。

---

## 需求

参考 Claude.ai 的 Artifacts 功能：

1. **AI 回复中识别 Artifact 内容**
   - 当 AI 返回 HTML/SVG/Mermaid/React 代码块时，识别为可渲染内容
   - 在聊天气泡中显示一个"打开画布"按钮（而不是纯代码文本）

2. **画布渲染**
   - 点击后在半屏或全屏面板中渲染内容
   - 使用 WKWebView 加载 HTML/JS/CSS
   - 支持的类型（按优先级）：
     - HTML + CSS + JS（最基础，覆盖面最广）
     - SVG 图表
     - Mermaid 流程图（需要引入 mermaid.js CDN）
     - Markdown 渲染预览

3. **交互**
   - 画布内的 JS 可以正常执行（按钮点击、动画等）
   - 画布可以全屏/半屏切换
   - 复制代码按钮（复制原始代码）
   - 关闭画布回到聊天

---

## 技术方案

### 核心：WKWebView

```swift
import WebKit

struct ArtifactCanvasView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
```

### 识别 Artifact

在 AI 回复的 content 中扫描代码块。规则：

- 语言标记为 `html`、`svg`、`mermaid` 的代码块 → 可渲染
- 代码块内包含 `<html`、`<svg`、`<div`、`<!DOCTYPE` → 可渲染
- 纯 Python/Swift/Bash 等 → 不渲染，保持代码显示

### 展示方式

聊天气泡中：
```
┌─────────────────────────────┐
│ 📄 Artifact                 │
│ [HTML 页面] 点击预览         │
│                    [复制代码] │
└─────────────────────────────┘
```

点击后弹出 sheet/全屏的 WKWebView 渲染。

---

## 可行性评估

**能做的：**
- WKWebView 渲染 HTML/CSS/JS — iOS 原生支持，没有技术障碍
- 代码块识别 — 正则或简单的字符串匹配
- Sheet 弹出 — 已有类似 UI 模式（ThinkingPanelView）

**有风险的：**
- Mermaid.js 需要从 CDN 加载，离线时不可用
- React 组件渲染需要构建步骤（babel transform）—— 复杂，可以先不做
- 安全性：WKWebView 执行任意 JS 有安全风险 —— 用沙盒隔离

**建议：先做 HTML+CSS+JS 基础渲染，Mermaid 和 React 后续再加。**

---

## 实现顺序

1. ArtifactCanvasView（WKWebView 包装）
2. 代码块识别逻辑（MessageSegment 或 CardFlowView 中）
3. 聊天气泡中的 Artifact 卡片 UI
4. Sheet 弹出渲染
5. 复制代码 + 全屏切换
6. （后续）Mermaid.js 支持
