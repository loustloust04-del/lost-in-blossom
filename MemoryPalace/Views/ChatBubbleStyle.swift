import SwiftUI
import MarkdownUI

// 气泡模式：iMessage 式带尾巴气泡 + 长回复按空行拆成连续小气泡。
// 2026-08-27 兔兔点名要「小气泡」，自粟粟 06-03~06-12 那条线搬入。
//
// 「小气泡」的真身不是气泡变小，是 assistant 长回复按空行拆块、一块一泡，
// 且只有最后一块带尾巴、中间块纯圆角——视觉上像微信一句一个泡连着掉下来。
//
// 本版是瘦版，相对她那边刻意不搬：
//   · 头像（兔兔明确不要）
//   · usage footer（我们有自己的）
//   · RecallCardView（绑她的记忆系统）
// 接入方式是 if chatBubbleMode 纯分流——加法不是改法，现有渲染路径一行不动，
// 与 08-24 那个「细输入框」开关同一手法。

struct BubbleTailShape: Shape {
    var isUser: Bool
    var radius: CGFloat = 16
    var hasTail: Bool = true

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        // 主体：系统连续曲率圆角矩形
        var p = Path(roundedRect: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
        guard hasTail else { return p }

        let minX = rect.minX, maxX = rect.maxX, maxY = rect.maxY
        // 镜像：assistant 尾巴翻到左下
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: isUser ? x : minX + maxX - x, y: y)
        }
        // 脚丫：必须让 tail 在它自己（镜像后的）局部坐标里仍是 CW，才与矩形 winding 同向、nonZero fill 不相消挖洞。
        // 镜像本身会反转绕向，所以 user / assistant 两套 addCurve 顺序必须相反：
        //  - isUser=true（右下，不镜像）：原顺序 e0→e1→…→e5（视觉 CW）
        //  - isUser=false（左下，镜像）：反序 e5→e4→…→e0（镜像后视觉 CW）
        var t = Path()
        if isUser {
            t.move(to: pt(maxX, maxY - r))
            t.addCurve(to: pt(maxX - 0.4621 * r, maxY - 0.1641 * r),
                       control1: pt(maxX, maxY - 0.6496 * r),
                       control2: pt(maxX - 0.1858 * r, maxY - 0.3427 * r))
            t.addCurve(to: pt(maxX - 0.4762 * r, maxY + 0.2789 * r),
                       control1: pt(maxX - 0.5986 * r, maxY - 0.0555 * r),
                       control2: pt(maxX - 0.5922 * r, maxY + 0.1357 * r))
            t.addCurve(to: pt(maxX - 0.4503 * r, maxY + 0.3571 * r),
                       control1: pt(maxX - 0.4563 * r, maxY + 0.3042 * r),
                       control2: pt(maxX - 0.4333 * r, maxY + 0.3244 * r))
            t.addCurve(to: pt(maxX - 0.5543 * r, maxY + 0.3822 * r),
                       control1: pt(maxX - 0.4752 * r, maxY + 0.4050 * r),
                       control2: pt(maxX - 0.5281 * r, maxY + 0.3902 * r))
            t.addCurve(to: pt(maxX - 1.3789 * r, maxY),
                       control1: pt(maxX - 0.7326 * r, maxY + 0.3286 * r),
                       control2: pt(maxX - 0.9753 * r, maxY + 0.0322 * r))
        } else {
            t.move(to: pt(maxX - 1.3789 * r, maxY))
            t.addCurve(to: pt(maxX - 0.5543 * r, maxY + 0.3822 * r),
                       control1: pt(maxX - 0.9753 * r, maxY + 0.0322 * r),
                       control2: pt(maxX - 0.7326 * r, maxY + 0.3286 * r))
            t.addCurve(to: pt(maxX - 0.4503 * r, maxY + 0.3571 * r),
                       control1: pt(maxX - 0.5281 * r, maxY + 0.3902 * r),
                       control2: pt(maxX - 0.4752 * r, maxY + 0.4050 * r))
            t.addCurve(to: pt(maxX - 0.4762 * r, maxY + 0.2789 * r),
                       control1: pt(maxX - 0.4333 * r, maxY + 0.3244 * r),
                       control2: pt(maxX - 0.4563 * r, maxY + 0.3042 * r))
            t.addCurve(to: pt(maxX - 0.4621 * r, maxY - 0.1641 * r),
                       control1: pt(maxX - 0.5922 * r, maxY + 0.1357 * r),
                       control2: pt(maxX - 0.5986 * r, maxY - 0.0555 * r))
            t.addCurve(to: pt(maxX, maxY - r),
                       control1: pt(maxX - 0.1858 * r, maxY - 0.3427 * r),
                       control2: pt(maxX, maxY - 0.6496 * r))
        }
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

// MARK: - 拆块

enum BubbleBlockSplitter {
    /// 按段落拆块：空行分隔成块；``` 代码块整块保留不拆。
    static func splitBlocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var buf: [String] = []
        var inCode = false
        func flush() {
            let s = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(s) }
            buf.removeAll()
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inCode { buf.append(line); inCode = false; flush() }
                else { flush(); buf.append(line); inCode = true }
            } else if inCode {
                buf.append(line)
            } else if t.isEmpty {
                flush()
            } else {
                buf.append(line)
            }
        }
        flush()
        return blocks.isEmpty ? [text] : blocks
    }

    /// 流式弹泡（粟粟 B6 A2'）：只出**已完成**段落——尾段还在生长不渲染，
    /// 等下一个空行出现它才成块弹出。思考标签未闭合时整段留在尾块 → 思考阶段自然只显示 dots。
    static func streamingBlocks(_ text: String) -> [String] {
        Array(splitBlocks(text).dropLast())
    }
}

// MARK: - 气泡模式单条渲染

/// 一条消息 → 一列连续气泡。
/// user 靠右、assistant 靠左；只有最后一块带尾巴。
struct BubbleModeRow: View {
    let text: String
    let isUser: Bool
    /// 复杂消息（带思考/工具段）不拆块，整条一个泡
    var allowSplit: Bool = true
    /// 思考链（第三刀）：有就在正文气泡上方挂一个灰气泡。
    /// 「不拆块」与「不显示思考链」是两件独立的事，这里只管显示。
    var thinking: String? = nil
    /// 流式弹泡（D1，粟粟 575e14cf/35322cfb）：气泡模式不逐字吐，
    /// 一段写完弹一泡（spring），尾部挂独立 dots 泡；定格后尾巴回到末块。
    var isLiveStreaming: Bool = false
    /// 语音气泡（D4，粟粟 bb8fd45b）：audioRef 在正文泡上方一条一泡；正文空时尾巴归最后一条语音
    var voices: [(path: String, duration: Double?)] = []
    var nodeId: String = ""
    var profileId: String = ""
    /// 附件条（D6）：图片/文档/文件卡放气泡外上方，正文泡只留文字
    var images: [Data] = []
    var documentTitles: [String] = []
    var attachments: [(name: String, type: String?, content: String?)] = []

    @AppStorage("bubbleModeCornerRadius") private var cornerRadius: Double = 16
    @AppStorage("hideTimestamp") private var hideTimestamp = false
    @AppStorage("fontScale") private var fontScale: Double = 1.2
    @AppStorage("selectedFont") private var selectedFont = ""
    @AppStorage("lineSpacingScale") private var lineSpacingScale: Double = 1.45
    @AppStorage("paragraphSpacingScale") private var paragraphSpacingScale: Double = 1.65

    /// iMessage 式固定内距——气泡模式锁定外观，不吃「气泡外观（高级）」那组滑块（数值对齐粟粟 fixedPaddingH/V）
    private let padH: CGFloat = 18
    private let padV: CGFloat = 15

    private var blocks: [String] {
        if isLiveStreaming {
            return BubbleBlockSplitter.streamingBlocks(text)
                .filter { !BubbleMarkdownSimplifier.isRenderEmpty($0) }
        }
        let raw = allowSplit ? BubbleBlockSplitter.splitBlocks(text) : [text]
        // 抹平文档感会把纯分隔线块（---）删空——拆块时就过滤掉，避免渲染出空气泡（粟粟 7a6d2423）
        let filtered = isUser ? raw : raw.filter { !BubbleMarkdownSimplifier.isRenderEmpty($0) }
        return filtered.isEmpty ? raw : filtered
    }

    /// 单块渲染（粟粟 blockText 对应版）：
    /// user 裸 Text；assistant 走 Markdown + 抹平文档感（标题→加粗、嵌套列表拍平、分隔线删，
    /// 代码块表格原样）。正则脚本已在 CardFlowView 吃过原文，这里只做渲染前简化。
    @ViewBuilder
    private func blockText(_ block: String) -> some View {
        if isUser {
            Text(block)
                .font(.system(size: 15 * fontScale))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
        } else {
            Markdown(BubbleMarkdownSimplifier.simplify(block))
                .markdownTheme(.memoryPalace(
                    fontName: selectedFont,
                    scale: CGFloat(fontScale > 0 ? fontScale : 1.0),
                    lineSpacingScale: CGFloat(lineSpacingScale),
                    paragraphSpacingScale: CGFloat(paragraphSpacingScale)
                ))
                .textSelection(.enabled)
        }
    }

    /// 弹入动画。anchor 取水平侧沿（垂直居中）——反转列表 flip 只翻纵轴，
    /// 侧沿 anchor 与翻转方向无关，不踩 flip 雷（粟粟 35322cfb）
    private var popTransition: AnyTransition {
        .scale(scale: 0.85, anchor: isUser ? .trailing : .leading).combined(with: .opacity)
    }

    private func bubbleBackground(hasTail: Bool) -> some View {
        BubbleTailShape(isUser: isUser, radius: cornerRadius, hasTail: hasTail)
            .fill(isUser ? Theme.userBubble : Theme.assistantBubble)
    }

    var body: some View {
        // blocks 数提到闭包外给 .animation(value:) 用，避免二次拆块
        let shown = blocks
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !images.isEmpty || !documentTitles.isEmpty || !attachments.isEmpty {
                    BubbleAttachmentStrip(images: images, documentTitles: documentTitles,
                                          attachments: attachments, isUser: isUser)
                        .padding(.bottom, 3)
                }
                if !isUser, let t = thinking,
                   !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ThinkingBubble(text: t, radius: cornerRadius, fontScale: fontScale)
                }
                let voiceTail = shown.isEmpty && !isLiveStreaming
                ForEach(voices.indices, id: \.self) { i in
                    VoiceCapsuleView(path: voices[i].path, duration: voices[i].duration,
                                     nodeId: nodeId, profileId: profileId,
                                     isUser: isUser, embedded: true)
                        .padding(.horizontal, padH)
                        .padding(.vertical, padV)
                        .background(bubbleBackground(hasTail: voiceTail && i == voices.count - 1))
                }
                ForEach(shown.indices, id: \.self) { i in
                    blockText(shown[i])
                        .padding(.horizontal, padH)
                        .padding(.vertical, padV)
                        // 只有最后一块带尾巴，中间块纯圆角；流式中尾巴归 dots 泡
                        .background(bubbleBackground(
                            hasTail: i == shown.count - 1 && !isLiveStreaming))
                        // 块级弹入只在流式弹泡态挂——静态渲染一律 .identity 直出，防群弹
                        .transition(isLiveStreaming ? popTransition : .identity)
                }
                // 流式尾部 typing dots 独立泡（固定 identity，不混进块 ForEach——
                // 否则「dots 变正文」被 transition 当内容替换而不是新泡弹入）
                if isLiveStreaming {
                    TypingDotsView()
                        .padding(.horizontal, padH)
                        .padding(.vertical, padV + 2)
                        .background(bubbleBackground(hasTail: true))
                        .transition(popTransition)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .animation(.spring(duration: 0.35), value: shown.count)
        .animation(.spring(duration: 0.35), value: isLiveStreaming)
    }
}

// MARK: - 思考链灰气泡（第三刀）

/// 正文气泡上方的灰泡：收起时一行预览（时钟 + 前 40 字），点开展开全文。
/// 尊重「思考链预览」设置：hidden 不渲染。
struct ThinkingBubble: View {
    let text: String
    let radius: Double
    let fontScale: Double

    @AppStorage("thinkingPreviewMode") private var thinkingPreviewMode: String = "summary"
    @State private var expanded = false

    private var preview: String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(40)) + (flat.count > 40 ? "…" : "")
    }

    var body: some View {
        if thinkingPreviewMode != "hidden" {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(expanded ? "思考过程" : preview)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                    }
                    .font(.system(size: 13 * fontScale))
                    .foregroundColor(Theme.textSecondary)
                    if expanded {
                        Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 13 * fontScale))
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.textMuted.opacity(0.18))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
