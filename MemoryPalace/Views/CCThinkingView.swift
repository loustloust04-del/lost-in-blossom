import SwiftUI

/// CC 执行任务时的思考链展示。
/// 灰色小字标题「CC 思考过程」，点击展开/折叠；展开后 monospace + 浅灰背景显示全文。
/// 样式与聊天气泡里的 Claude 思考链（ThinkingBlockView）保持一致。
struct CCThinkingView: View {
    let block: CCThinkingBlock
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("CC 思考过程")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(Theme.textMuted.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(block.thinking)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.mainBg.opacity(0.5))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
