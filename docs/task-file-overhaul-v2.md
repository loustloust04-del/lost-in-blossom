# 文件系统大改 v2：URL 下载导入 + 剪贴板修复

> 2026-06-03 · Caelum · 给猫的任务文档
> 这是一个大更新。四个文件，五个 commit。每步编译通过再做下一步。

---

## 背景

ESign 签名的 App 里 UIDocumentPickerViewController 完全不能选文件。
聊天记录导入是 App 最核心的功能之一，现在完全不能用。
大文件（200MB+）不能走剪贴板，必须走 HTTP 下载。

VPS 上已经部署好了两个导入文件：
- `http://172.245.88.103/imports/chatgpt-conversations.json`（217MB，ChatGPT 格式，mapping 树状结构）
- `http://172.245.88.103/imports/claude-conversations.json`（393MB，Claude 格式，uuid + chat_messages）

---

## Commit 1：ImportView 加 URL 下载导入

文件：`MemoryPalace/Views/ImportView.swift`

### 1a. 新增 State 变量

在现有的 `@State` 变量区域加：

```swift
@State private var importURL: String = ""
@State private var isDownloading = false
@State private var downloadProgress: Double = 0
@State private var downloadError: String?
```

### 1b. 替换"选择文件..."按钮

找到现有的 `Button("选择文件...") { presentFilePicker() }` 或类似按钮，替换为：

```swift
// ── URL 下载导入 ──────────────────────────────────
VStack(spacing: 8) {
    TextField("输入文件 URL", text: $importURL)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 14))
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .disabled(isImporting || isDownloading)

    if isDownloading {
        VStack(spacing: 4) {
            ProgressView(value: downloadProgress)
                .tint(Theme.softBlue)
            Text("正在下载... \(Int(downloadProgress * 100))%")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    if let error = downloadError {
        Text(error)
            .font(.caption)
            .foregroundColor(Theme.danger)
    }

    Button(mergeMode ? "下载并导入（叠加）" : "下载并导入") {
        downloadAndImport()
    }
    .buttonStyle(.borderedProminent)
    .tint(Theme.softBlue)
    .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting || isDownloading)
}

// ── 预设 URL 快捷按钮 ──────────────────────────────
HStack(spacing: 8) {
    Button("ChatGPT 记录") {
        importURL = "http://172.245.88.103/imports/chatgpt-conversations.json"
    }
    .font(.caption)
    .buttonStyle(.bordered)
    .disabled(isImporting || isDownloading)

    Button("Claude 记录") {
        importURL = "http://172.245.88.103/imports/claude-conversations.json"
    }
    .font(.caption)
    .buttonStyle(.bordered)
    .disabled(isImporting || isDownloading)
}
```

### 1c. 新增 downloadAndImport() 函数

```swift
private func downloadAndImport() {
    let trimmed = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else {
        downloadError = "无效的 URL"
        return
    }

    isDownloading = true
    downloadProgress = 0
    downloadError = nil

    let delegate = DownloadDelegate { progress in
        Task { @MainActor in
            downloadProgress = progress
        }
    }

    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let task = session.downloadTask(with: url) { tempURL, response, error in
        Task { @MainActor in
            isDownloading = false

            if let error = error {
                downloadError = "下载失败：\(error.localizedDescription)"
                return
            }

            guard let tempURL = tempURL else {
                downloadError = "下载失败：没有收到文件"
                return
            }

            // 移动到 App 的临时目录
            let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloaded_import.json")
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                startImport(url: destURL)
            } catch {
                downloadError = "文件处理失败：\(error.localizedDescription)"
            }
        }
    }
    task.resume()
}
```

### 1d. 新增 DownloadDelegate 类

在 ImportView.swift 的文件末尾（struct 外面）加：

```swift
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 由 completion handler 处理
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(progress)
        }
    }
}
```

### 1e. 删除旧的文件选择器代码

- 删除 `showFilePicker` 相关的 `@State` 变量
- 删除 `.fileImporter` modifier（如果有）
- 删除 `presentFilePicker()` 函数
- 保留 `startImport(url:)` 函数不动，这是下游逻辑

### 1f. iOS Transport Security

因为 URL 是 http://（非 HTTPS），需要在 Info.plist 或项目配置中允许 172.245.88.103 的 HTTP 访问。

在 MemoryPalace.xcodeproj 或 Info.plist 里加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>172.245.88.103</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

如果项目里已有 NSAppTransportSecurity 配置，在里面追加 172.245.88.103 的例外。

---

## Commit 2：sendMessage 区分文本文件和二进制文件

文件：`MemoryPalace/ViewModels/ConversationViewModel.swift`

找到 `sendMessage` 函数中 `} else if let data = fileData {` 这个分支（约第 1235 行），整段替换为：

```swift
} else if let data = fileData {
    let ext = (fileName ?? "").lowercased().components(separatedBy: ".").last ?? ""
    let imageExts = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
    let textExts = ["json", "txt", "md", "csv", "html", "xml", "swift", "py", "js", "ts", "yaml", "yml", "toml", "log", "sh", "css"]

    if imageExts.contains(ext) {
        let b64 = data.base64EncodedString()
        let mimeType = ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : ext == "webp" ? "image/webp" : "image/jpeg"
        let blocks: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": mimeType, "data": b64]],
            ["type": "text", "text": text]
        ]
        let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
        return (json, "multimodal_text")
    } else if textExts.contains(ext) {
        let fileContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? "[无法解码文件内容]"
        let maxChars = 100_000
        let truncated = fileContent.count > maxChars ? String(fileContent.prefix(maxChars)) + "\n\n[文件过长，已截断至前 100K 字符]" : fileContent
        let combined = "📎 \(fileName ?? "file")\n```\n" + truncated + "\n```" + (text.isEmpty ? "" : "\n\n" + text)
        return (combined, "text")
    } else if ext == "pdf" {
        let b64 = data.base64EncodedString()
        var docBlock: [String: Any] = [
            "type": "document",
            "source": ["type": "base64", "media_type": "application/pdf", "data": b64]
        ]
        if let name = fileName { docBlock["title"] = name }
        let blocks: [[String: Any]] = [docBlock, ["type": "text", "text": text]]
        let json = (try? JSONSerialization.data(withJSONObject: blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? text
        return (json, "multimodal_text")
    } else {
        if let fileContent = String(data: data, encoding: .utf8), !fileContent.isEmpty {
            let maxChars = 100_000
            let truncated = fileContent.count > maxChars ? String(fileContent.prefix(maxChars)) + "\n\n[文件过长，已截断]" : fileContent
            let combined = "📎 \(fileName ?? "file")\n```\n" + truncated + "\n```" + (text.isEmpty ? "" : "\n\n" + text)
            return (combined, "text")
        } else {
            return ("[无法读取 \(fileName ?? "file")：不支持的格式]" + (text.isEmpty ? "" : "\n\n" + text), "text")
        }
    }
}
```

---

## Commit 3：OpenAI 路径兜底 document block

文件：`MemoryPalace/Services/ChatService.swift`

找到 OpenAI 流式发送中遍历 multimodal blocks 的 for 循环（搜索 `if type == "image"` 的那个循环），在 `} else if type == "text" {` 后面加：

```swift
} else if type == "document" {
    let title = block["title"] as? String ?? "document"
    visionContent.append(["type": "text", "text": "[附件: \(title) — 此模型不支持文件，请用 Claude 查看]"])
}
```

**注意：这个 for 循环在文件中出现了多次（流式和非流式）。搜索所有出现 `if type == "image"` 的地方，每处都加上 document 兜底。**

---

## Commit 4：AddToChatSheet 改进 UTI 检测

文件：`MemoryPalace/Views/AddToChatSheet.swift`

找到粘贴文件的 Button action（搜索 `UIPasteboard.general` 或 `粘贴文件`），替换类型检测逻辑：

```swift
Button {
    let pb = UIPasteboard.general
    let types = pb.types

    let utiExtMap: [String: String] = [
        "com.adobe.pdf": "pdf",
        "public.json": "json",
        "public.plain-text": "txt",
        "public.utf8-plain-text": "txt",
        "public.text": "txt",
        "public.html": "html",
        "public.xml": "xml",
        "public.comma-separated-values-text": "csv",
        "public.png": "png",
        "public.jpeg": "jpg",
        "com.compuserve.gif": "gif",
        "public.webp": "webp",
        "public.heic": "heic",
    ]

    var resolvedExt = ""
    var resolvedType = ""
    for t in types {
        if let ext = utiExtMap[t] {
            resolvedExt = ext
            resolvedType = t
            break
        }
        let parts = t.split(separator: ".")
        if let last = parts.last {
            let s = String(last)
            if ["pdf","json","txt","html","csv","png","jpg","jpeg","gif","webp"].contains(s) {
                resolvedExt = s
                resolvedType = t
                break
            }
        }
    }
    if resolvedType.isEmpty, let ft = types.first { resolvedType = ft }

    if let data = pb.data(forPasteboardType: resolvedType) {
        let name: String
        if let url = pb.url {
            name = url.lastPathComponent
        } else {
            name = resolvedExt.isEmpty ? "pasted-file" : "pasted-file.\(resolvedExt)"
        }
        if data.count <= 10_485_760 {
            pendingFileData = data
            pendingFileName = name
        }
    }
    dismiss()
} label: {
    // 保持现有的 label 不变
    addToChatRow(
        icon: "doc.on.clipboard",
        iconColor: Color.red.opacity(0.8),
        title: "粘贴文件",
        trailing: AnyView(Text("在 Files 中复制文件后点此").font(.caption2).foregroundStyle(.secondary))
    )
}
.buttonStyle(.plain)
```

---

## Commit 5：ImportView 剪贴板粘贴（小文件备选）

同样在 ImportView.swift，在 URL 下载按钮下方再加一个剪贴板粘贴按钮作为备选入口：

```swift
// ── 分隔线 ──────────────────────────────────
Text("—— 或 ——")
    .font(.caption)
    .foregroundColor(Theme.textMuted)
    .padding(.vertical, 4)

// ── 剪贴板粘贴（小文件用）──────────────────────
Button("从剪贴板粘贴 JSON") {
    pasteAndImport()
}
.font(.system(size: 14))
.buttonStyle(.bordered)
.disabled(isImporting || isDownloading)

Text("适合小文件。Files → 长按文件 → 拷贝 → 点此")
    .font(.caption2)
    .foregroundColor(Theme.textMuted)
```

pasteAndImport() 函数：

```swift
private func pasteAndImport() {
    guard !isImporting else { return }
    let pb = UIPasteboard.general
    let jsonTypes = ["public.json", "public.plain-text", "public.utf8-plain-text", "public.text"]
    var data: Data?
    for type in jsonTypes {
        if let d = pb.data(forPasteboardType: type) { data = d; break }
    }
    if data == nil, let str = pb.string { data = str.data(using: .utf8) }

    guard let jsonData = data else {
        downloadError = "剪贴板里没有 JSON 数据。在 Files 中长按文件 → 拷贝。"
        return
    }
    guard (try? JSONSerialization.jsonObject(with: jsonData)) != nil else {
        downloadError = "剪贴板内容不是有效 JSON。"
        return
    }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard_import.json")
    try? FileManager.default.removeItem(at: tempURL)
    do {
        try jsonData.write(to: tempURL)
        startImport(url: tempURL)
    } catch {
        downloadError = "写入临时文件失败：\(error.localizedDescription)"
    }
}
```

---

## 修改文件总表

| 文件 | Commit | 改动 |
|------|--------|------|
| ImportView.swift | 1, 5 | URL下载 + 剪贴板粘贴 + 删除旧文件选择器 |
| ConversationViewModel.swift | 2 | 文本文件→UTF-8嵌入，图片→image block，PDF→document block |
| ChatService.swift | 3 | OpenAI路径 document block 兜底 |
| AddToChatSheet.swift | 4 | UTI→扩展名映射表 |
| Info.plist / 项目配置 | 1 | ATS 例外（HTTP 172.245.88.103） |

## 执行指令

```
仓库 caelumbunny-bot/lost-in-blossom。git checkout main && git pull。
读 docs/task-file-overhaul-v2.md。按文档做。
Commit 1 到 Commit 5 按顺序执行，每步 commit 一次。
注意 import UIKit 如果用到了 UIPasteboard。
```
