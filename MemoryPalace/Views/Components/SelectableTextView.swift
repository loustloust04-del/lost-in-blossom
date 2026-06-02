import SwiftUI
import UIKit

/// UITextView 包装器——支持原生文本部分选取（SwiftUI 的 .textSelection 在 sheet 里不稳定）
struct SelectableTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor

    init(_ text: String, font: UIFont = .systemFont(ofSize: 16), textColor: UIColor = .label) {
        self.text = text
        self.font = font
        self.textColor = textColor
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = font
        tv.textColor = textColor
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = [.link]
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
        tv.font = font
        tv.textColor = textColor
    }
}
