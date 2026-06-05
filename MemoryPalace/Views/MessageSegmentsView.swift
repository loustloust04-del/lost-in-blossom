import SwiftUI
import MarkdownUI

// MARK: - Rich Text 预处理（彩色文字 + spoiler 黑块）

/// `.text` 段在走 Markdown 渲染前的切片结果。
/// - markdown: 普通 Markdown 文本，走原有 MarkdownUI 路径
/// - colored: `{color:xxx}...{/color}` 彩色文字
/// - spoiler: `||...||` 点击展开的黑块
fileprivate enum RichSegment {
    case markdown(String)
    case colored(String, Color)
    case spoiler(String)
}

/// 扫描文本，识别 {color:xxx}...{/color} 和 ||...|| 自定义语法，切成片段数组。
/// 没有命中任何语法时返回单个 .markdown(text)，让上层走原有渲染路径（零成本）。
fileprivate func parseRichSegments(_ text: String) -> [RichSegment] {
    var segments: [RichSegment] = []
    var remaining = text[text.startIndex...]

    while !remaining.isEmpty {
        // 找最近的自定义标记
        let colorStart = remaining.range(of: "{color:")
        let spoilerStart = remaining.range(of: "||")

        // 取最先出现的那个
        let firstColor = colorStart?.lowerBound
        let firstSpoiler = spoilerStart?.lowerBound

        // 都没有 → 剩余全部是 markdown
        if firstColor == nil && firstSpoiler == nil {
            let s = String(remaining)
            if !s.isEmpty { segments.append(.markdown(s)) }
            break
        }

        // 判断谁先出现
        let colorFirst = firstColor != nil && (firstSpoiler == nil || firstColor! < firstSpoiler!)

        if colorFirst, let cStart = firstColor {
            // ── 处理 {color:xxx}...{/color} ──
            // 标记前的普通文本
            if cStart > remaining.startIndex {
                let plain = String(remaining[remaining.startIndex..<cStart])
                if !plain.isEmpty { segments.append(.markdown(plain)) }
            }

            // 找 } 关闭标签获取颜色名
            let afterColorColon = remaining[cStart...].dropFirst("{color:".count)
            if let closeBrace = afterColorColon.range(of: "}") {
                let colorName = String(afterColorColon[afterColorColon.startIndex..<closeBrace.lowerBound])
                let contentStart = closeBrace.upperBound

                // 找 {/color}
                if let endTag = remaining[contentStart...].range(of: "{/color}") {
                    let content = String(remaining[contentStart..<endTag.lowerBound])
                    segments.append(.colored(content, colorFromName(colorName)))
                    remaining = remaining[endTag.upperBound...]
                    continue
                }
            }
            // 格式不完整 → 当普通文本，跳过 {color: 继续
            let skip = String(remaining[remaining.startIndex...cStart])
            segments.append(.markdown(skip))
            remaining = remaining[remaining.index(after: cStart)...]

        } else if let sStart = firstSpoiler {
            // ── 处理 ||...|| ──
            // 标记前的普通文本
            if sStart > remaining.startIndex {
                let plain = String(remaining[remaining.startIndex..<sStart])
                if !plain.isEmpty { segments.append(.markdown(plain)) }
            }

            let contentStart = remaining.index(sStart, offsetBy: 2)
            if contentStart < remaining.endIndex,
               let endMarker = remaining[contentStart...].range(of: "||") {
                let content = String(remaining[contentStart..<endMarker.lowerBound])
                if !content.isEmpty {
                    segments.append(.spoiler(content))
                    remaining = remaining[endMarker.upperBound...]
                    continue
                }
            }
            // 格式不完整 → 当普通文本
            let skip = String(remaining[remaining.startIndex..<remaining.index(sStart, offsetBy: min(2, remaining.distance(from: sStart, to: remaining.endIndex)))])
            segments.append(.markdown(skip))
            remaining = remaining[remaining.index(sStart, offsetBy: min(2, remaining.distance(from: sStart, to: remaining.endIndex)))...]
        }
    }

    return segments.isEmpty ? [.markdown(text)] : segments
}

fileprivate func colorFromName(_ name: String) -> Color {
    switch name.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "yellow": return .yellow
    case "cyan": return .cyan
    case "white": return .white
    case "gray", "grey": return .gray
    default: return Theme.textPrimary
    }
}

/// 按顺序渲染 Claude v2 导入的 [MessageSegment]。
/// - 每段独立折叠（思考 = DisclosureGroup；工具 = 可展开卡片）
/// - toolUse 后紧跟的同 id toolResult 会合并成一张卡片
/// - 样式沿用现有 Theme 调色盘（mainBg + textMuted），不引新色
struct MessageSegmentsView: View {
    let segments: [MessageSegment]
    let selectedFont: String
    let fontScale: Double
    let lineSpacingScale: Double
    let paragraphSpacingScale: Double
    let regexScripts: [RegexScript]
    /// user 气泡字体 / 对齐跟 assistant 不一样；text 段按此切换渲染。
    var isUser: Bool = false

    /// 外观 - 消息显示 - 「显示安全提示卡」开关。粟粟觉得 flag 卡丑可关掉。
    @AppStorage("showFlagBlocks") private var showFlagBlocks: Bool = true

    /// 合并后的渲染条目
    fileprivate enum Item {
        case text(String)
        case thinking(String)
        case toolPair(name: String, inputJSON: String, resultText: String?, isError: Bool, integration: String?)
        case orphanToolResult(text: String, isError: Bool, integration: String?)
        case flag(kind: String, helplineLine: String?, helplineUrl: String?)
        case attachment(name: String, type: String?, content: String?)
        case file(name: String)
    }

    private var items: [Item] {
        var result: [Item] = []
        var i = 0
        while i < segments.count {
            let seg = segments[i]
            switch seg {
            case .text(let s):
                result.append(.text(s))
                i += 1
            case .thinking(let text, _):
                result.append(.thinking(text))
                i += 1
            case .toolUse(let id, let name, let inputJSON, let integration, _):
                // Peek next: 若紧邻的是匹配 id 的 toolResult → 配对
                if i + 1 < segments.count,
                   case let .toolResult(toolUseId, text, isError, resultIntegration) = segments[i + 1],
                   toolUseId == id {
                    result.append(.toolPair(
                        name: name,
                        inputJSON: inputJSON,
                        resultText: text,
                        isError: isError,
                        integration: integration ?? resultIntegration
                    ))
                    i += 2
                } else {
                    // 没有配对的 result（罕见；防御）
                    result.append(.toolPair(
                        name: name,
                        inputJSON: inputJSON,
                        resultText: nil,
                        isError: false,
                        integration: integration
                    ))
                    i += 1
                }
            case .toolResult(_, let text, let isError, let integration):
                // 没有配对的 toolUse 的孤儿 result（防御）
                result.append(.orphanToolResult(text: text, isError: isError, integration: integration))
                i += 1
            case .flag(let kind, let hName, let hPhone, let hUrl):
                var parts: [String] = []
                if let hName, !hName.isEmpty { parts.append(hName) }
                if let hPhone, !hPhone.isEmpty { parts.append(hPhone) }
                result.append(.flag(
                    kind: kind,
                    helplineLine: parts.isEmpty ? nil : parts.joined(separator: " · "),
                    helplineUrl: hUrl
                ))
                i += 1
            case .attachment(let name, let type, let extracted):
                result.append(.attachment(name: name, type: type, content: extracted))
                i += 1
            case .file(let name, _):
                result.append(.file(name: name))
                i += 1
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let resolved = items
            ForEach(resolved.indices, id: \.self) { idx in
                itemView(resolved[idx])
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: Item) -> some View {
        switch item {
        case .text(let s):
            let applied = regexScripts.isEmpty
                ? s
                : RegexEngine.apply(scripts: regexScripts, text: s, messagePlacement: 2, isMarkdown: true)
            if !applied.isEmpty {
                if isUser {
                    let richSegs = parseRichSegments(applied)
                    if richSegs.count == 1, case .markdown = richSegs[0] {
                        // 纯文本，保留用户气泡字体路径
                        Text(applied)
                            .font(FontManager.font(size: 13.5))
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(4 * (fontScale > 0 ? fontScale : 1.0) * lineSpacingScale)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // 含富文本标记，逐段渲染
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(richSegs.enumerated()), id: \.offset) { _, seg in
                                richSegmentView(seg)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    let richSegments = parseRichSegments(applied)
                    if richSegments.count == 1, case .markdown = richSegments[0] {
                        // 纯 Markdown，走原有渲染路径（零成本）
                        Markdown(applied)
                            .markdownTheme(.memoryPalace(
                                fontName: selectedFont,
                                scale: fontScale > 0 ? fontScale : 1.0,
                                lineSpacingScale: lineSpacingScale,
                                paragraphSpacingScale: paragraphSpacingScale
                            ))
                            .textSelection(.enabled)
                    } else {
                        // 混合内容，逐段渲染
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(richSegments.enumerated()), id: \.offset) { _, seg in
                                richSegmentView(seg)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .thinking(let s):
            ThinkingBlockView(text: s)
        case .toolPair(let name, let inputJSON, let resultText, let isError, let integration):
            ToolCallCardView(
                name: name,
                inputJSON: inputJSON,
                resultText: resultText,
                isError: isError,
                integration: integration
            )
        case .orphanToolResult(let text, let isError, let integration):
            ToolCallCardView(
                name: isError ? "tool 结果（失败）" : "tool 结果",
                inputJSON: "",
                resultText: text,
                isError: isError,
                integration: integration
            )
        case .flag(let kind, let helplineLine, let helplineUrl):
            if showFlagBlocks {
                FlagCardView(kind: kind, helplineLine: helplineLine, helplineUrl: helplineUrl)
            }
        case .attachment(let name, let type, let content):
            AttachmentCardView(name: name, type: type, extractedContent: content)
        case .file(let name):
            HStack(spacing: 6) {
                Text("🖼")
                    .font(.system(size: 11))
                Text(name.isEmpty ? "(图片)" : name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    /// 混合 rich text 模式下的单段渲染分发。
    @ViewBuilder
    private func richSegmentView(_ seg: RichSegment) -> some View {
        let scale = fontScale > 0 ? fontScale : 1.0
        switch seg {
        case .markdown(let md):
            Markdown(md)
                .markdownTheme(.memoryPalace(
                    fontName: selectedFont,
                    scale: scale,
                    lineSpacingScale: lineSpacingScale,
                    paragraphSpacingScale: paragraphSpacingScale
                ))
                .textSelection(.enabled)
        case .colored(let text, let color):
            Text(text)
                .foregroundColor(color)
                .font(.system(size: 13.5 * scale))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .spoiler(let text):
            SpoilerView(text: text)
                .font(.system(size: 13.5 * scale))
        }
    }
}

// MARK: - Spoiler 黑块

/// `||...||` 隐藏文字：默认黑块遮罩，点击展开。
private struct SpoilerView: View {
    let text: String
    @State private var revealed = false

    var body: some View {
        Text(text)
            .foregroundColor(revealed ? Theme.textPrimary : .clear)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(revealed ? Theme.mainBg.opacity(0.3) : Theme.textPrimary)
            )
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { revealed.toggle() } }
    }
}

// MARK: - Thinking Block

/// 原本用 `DisclosureGroup("思考")` —— macOS 下嵌在 LazyVStack + 自定义 bubble
/// background 里有时吃点击（实测粟粟反馈"思考都点不开"）。改成和 ToolCallCard
/// 一致的 Button + @State 结构，命中区域扩到整行，保证可点。
private struct ThinkingBlockView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("思考")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(Theme.textMuted.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .textSelection(.enabled)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Tool Call Card

private struct ToolCallCardView: View {
    let name: String
    let inputJSON: String
    let resultText: String?
    let isError: Bool
    let integration: String?

    @State private var isExpanded = false
    @State private var resultExpanded = false
    private let resultTruncate = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("🔧").font(.system(size: 11))
                    Text(name.isEmpty ? "(未命名 tool)" : name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    if let integration, !integration.isEmpty {
                        Text("· \(integration)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted.opacity(0.7))
                    }
                    if isError {
                        Text("· 失败")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if !inputJSON.isEmpty && inputJSON != "{}" {
                    Text(inputJSON)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let r = resultText, !r.isEmpty {
                    if !inputJSON.isEmpty && inputJSON != "{}" {
                        Divider().padding(.vertical, 2)
                    }
                    let shown = resultExpanded ? r : String(r.prefix(resultTruncate))
                    Text(shown)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if r.count > resultTruncate {
                        Button(resultExpanded ? "收起结果" : "展开全部（共 \(r.count) 字）") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                resultExpanded.toggle()
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundColor(Theme.branchIndicator)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.mainBg.opacity(0.5))
        )
    }
}

// MARK: - Flag Card

private struct FlagCardView: View {
    let kind: String
    let helplineLine: String?
    let helplineUrl: String?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("⚠️").font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("flag: \(kind)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                if let line = helplineLine {
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted.opacity(0.8))
                        .textSelection(.enabled)
                }
                if let url = helplineUrl, let link = URL(string: url) {
                    Link(url, destination: link)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.branchIndicator)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.textMuted.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Attachment Card

private struct AttachmentCardView: View {
    let name: String
    let type: String?
    let extractedContent: String?

    @State private var isExpanded = false
    private let previewTruncate = 2000

    private var hasContent: Bool {
        (extractedContent?.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if hasContent {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("📎").font(.system(size: 11))
                    Text(name.isEmpty ? "(附件)" : name)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textPrimary)
                    if let t = type, !t.isEmpty {
                        Text("· \(t)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted.opacity(0.7))
                    }
                    Spacer()
                    if hasContent {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)

            if isExpanded, let ex = extractedContent, !ex.isEmpty {
                let shown = ex.count > previewTruncate ? String(ex.prefix(previewTruncate)) + "\n...（已截断）" : ex
                Text(shown)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .textSelection(.enabled)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.mainBg.opacity(0.5))
        )
    }
}
