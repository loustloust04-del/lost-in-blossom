import SwiftUI
import UIKit

// D6（2026-08-30，气泡模式独立化）：附件挪到气泡外上方。
// 微信/iMessage 里图片是一条独立消息，不塞在文字泡里；气泡里只留文字。
//
// 与粟粟 BubbleAttachmentStrip 思路一致，但数据源接我们自己的：
//   · 图片存在 multimodal_text 的 content JSON 里（不是 segments .image 段）
//   · 文件附件是 segments 的 .attachment 段（content 里另有全文发给模型）
// 之前气泡分支没解包 multimodal_text，开气泡模式发图会直接露 JSON——本刀顺手修。

/// multimodal_text 内容解包（原 MultimodalUserBubble 私有逻辑抽出共用）
struct MultimodalContent {
    var images: [Data] = []
    var documentTitles: [String] = []
    var text: String = ""

    static func parse(_ content: String) -> MultimodalContent {
        var out = MultimodalContent()
        guard let data = content.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            out.text = content
            return out
        }
        for item in arr {
            let type = item["type"] as? String ?? ""
            if type == "image", let source = item["source"] as? [String: Any],
               let b64 = source["data"] as? String,
               let imgData = Data(base64Encoded: b64) {
                out.images.append(imgData)
            } else if type == "document" {
                out.documentTitles.append(item["title"] as? String ?? "document.pdf")
            } else if type == "text" {
                out.text = item["text"] as? String ?? ""
            }
        }
        return out
    }
}

/// 气泡模式附件条：图片（点开全屏）+ 文件卡，靠消息侧对齐，放在正文泡上方
struct BubbleAttachmentStrip: View {
    let images: [Data]
    let documentTitles: [String]
    let attachments: [(name: String, type: String?, content: String?)]
    let isUser: Bool

    @State private var fullImageIndex: Int? = nil

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            ForEach(images.indices, id: \.self) { i in
                if let ui = UIImage(data: images[i]) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { fullImageIndex = i }
                }
            }
            ForEach(documentTitles.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                    Text(documentTitles[i])
                        .font(FontManager.font(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.textMuted.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            ForEach(attachments.indices, id: \.self) { i in
                AttachmentCardView(name: attachments[i].name, type: attachments[i].type,
                                   extractedContent: attachments[i].content)
                    .frame(maxWidth: 260, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .fullScreenCover(isPresented: Binding(
            get: { fullImageIndex != nil },
            set: { if !$0 { fullImageIndex = nil } }
        )) {
            if let i = fullImageIndex, i < images.count, let ui = UIImage(data: images[i]) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { fullImageIndex = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
