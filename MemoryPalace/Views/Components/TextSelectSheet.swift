import SwiftUI

struct TextSelectSheet: View {
    let text: String
    let thinkingText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let thinking = thinkingText, !thinking.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("思考过程")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(thinking)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    Text(text)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("选取文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        HapticService.shared.copyText()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
