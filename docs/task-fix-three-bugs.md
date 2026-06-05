# Bug Fix Batch — Artifacts / Rich Text / CC Bridge Button

> 三个 commit，一个一个做，每个做完 push。

---

## Commit 1: Artifacts 代码块隐藏

**问题**：AI 回复包含 HTML/SVG/Mermaid 代码块时，代码块在气泡里完整显示了一遍，底部又显示一个 ArtifactCardView 卡片。应该只显示卡片，不显示代码。

**修改文件**：

### ArtifactCanvasView.swift — ArtifactDetector 加 stripFirst 方法

在 `ArtifactDetector` enum 里，`find(in:)` 方法之后，加：

```swift
/// 从内容中移除第一个可渲染代码块（HTML/SVG/Mermaid），返回剩余内容。
/// 配合 find(in:) 使用：先 find 检测是否有 artifact，有则 strip 后传给 Markdown 渲染。
static func stripFirst(in content: String) -> String {
    let lines = content.components(separatedBy: "\n")
    var result: [String] = []
    var inBlock = false
    var blockLang = ""
    var blockStartIdx = 0
    var blockLines: [String] = []
    var removed = false

    for (i, line) in lines.enumerated() {
        if removed {
            result.append(line)
            continue
        }
        if !inBlock {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("```") {
                let lang = String(stripped.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                inBlock = true
                blockLang = lang
                blockStartIdx = i
                blockLines = []
            } else {
                result.append(line)
            }
        } else {
            if line.trimmingCharacters(in: .whitespaces) == "```" {
                let code = blockLines.joined(separator: "\n")
                if classify(code: code, lang: blockLang) != nil {
                    removed = true
                } else {
                    result.append(lines[blockStartIdx])
                    result.append(contentsOf: blockLines)
                    result.append(line)
                }
                inBlock = false
                blockLang = ""
                blockLines = []
            } else {
                blockLines.append(line)
            }
        }
    }

    if inBlock {
        result.append(lines[blockStartIdx])
        result.append(contentsOf: blockLines)
    }

    return result.joined(separator: "\n")
}
```

### CardFlowView.swift — 提前检测 artifact，strip 后渲染

找到这一行（大约 1481 行）：
```swift
let rawDisplay = shouldTruncate ? String(cleaned.prefix(truncateLength)) + "\n\n..." : cleaned
```

在它**上面**加两行：
```swift
let artifactForCard: ArtifactContent? = (!isUser && !isStreaming) ? ArtifactDetector.find(in: cleaned) : nil
let cleanedForDisplay = artifactForCard != nil ? ArtifactDetector.stripFirst(in: cleaned) : cleaned
```

然后把 rawDisplay 的 `cleaned` 改成 `cleanedForDisplay`：
```swift
let rawDisplay = shouldTruncate ? String(cleanedForDisplay.prefix(truncateLength)) + "\n\n..." : cleanedForDisplay
```

找到 artifact card 的条件渲染（大约 1507 行）：
```swift
if !isUser && !isStreaming, let artifact = ArtifactDetector.find(in: cleaned) {
```
改成：
```swift
if let artifact = artifactForCard {
```

这样 artifact 只检测一次，代码块从 Markdown 内容中移除，只显示卡片。

---

## Commit 2: 富文本 debug 日志

**问题**：`{color:red}文字{/color}` 和 `||spoiler||` 不渲染。parseRichSegments 代码逻辑正确，但不确定上游是否预处理掉了标记。

**修改文件**：MessageSegmentsView.swift

找到 assistant 分支里调用 parseRichSegments 的地方（大约 238 行）：
```swift
let richSegments = parseRichSegments(applied)
```

在这行**上面**加：
```swift
#if DEBUG
if applied.contains("{color:") || applied.contains("||") {
    print("[RichText] INPUT: \(applied.prefix(200))")
    print("[RichText] SEGMENTS: \(richSegments.count)")
}
#endif
```

同样在 isUser 分支（大约 219 行）也加同样的日志。

这个 commit 只加日志，不改逻辑。编译后兔兔测试，从 Xcode console（或 macOS Console.app 连 iPhone）看输出，确认文本进来时标记是否完整。

---

## Commit 3: CC Bridge 按钮 debug 日志

**问题**：APISettingsTab 里"保存并连接"和"重新连接"按钮不工作。

**修改文件**：CCBridgeWebSocketClient.swift

在 `forceReconnect` 方法里加日志：
```swift
func forceReconnect(url: URL, token: String? = nil) {
    print("[CCBridge] forceReconnect called, url=\(url)")
    disconnect()
    print("[CCBridge] disconnected, scheduling connect in 0.3s")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self else { print("[CCBridge] self is nil after delay"); return }
        print("[CCBridge] connecting to \(url)")
        self.connect(url: url, token: token)
    }
}
```

在 `connect(urls:)` 方法开头加：
```swift
func connect(urls inputURLs: [URL], token: String? = nil) {
    print("[CCBridge] connect called, urls=\(inputURLs), isConnected=\(isConnected), task=\(task != nil)")
```

在 `startTask()` 方法里加：
```swift
private func startTask() {
    guard let url else { print("[CCBridge] startTask: url is nil"); return }
    print("[CCBridge] startTask: \(url)")
```

在 URLSession delegate 的 `didOpenWithProtocol` 里加：
```swift
print("[CCBridge] WebSocket opened: \(webSocketTask.currentRequest?.url?.absoluteString ?? "?")")
```

在 `didCloseWith` 里加：
```swift
print("[CCBridge] WebSocket closed: code=\(closeCode.rawValue) reason=\(String(data: reason ?? Data(), encoding: .utf8) ?? "")")
```

---

## 执行顺序

1. Commit 1 — `fix: hide artifact code block from bubble, show card only`
2. Commit 2 — `debug: add rich text parsing logs`
3. Commit 3 — `debug: add CC Bridge reconnect logs`
4. Push all to main
5. 不触发编译（等群聊做完一起编译）

