import UIKit
import UniformTypeIdentifiers

/// 绕过 SwiftUI 的 .sheet/.fullScreenCover presentation，
/// 直接用 UIKit 原生 present UIDocumentPickerViewController。
/// 解决 SwiftUI 环境下文件选择器触摸事件丢失的问题。
class DocumentPickerHelper: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerHelper()

    private var onPick: (([URL]) -> Void)?
    private var onCancel: (() -> Void)?

    func present(
        contentTypes: [UTType] = [.item],
        allowsMultipleSelection: Bool = false,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.onPick = onPick
        self.onCancel = onCancel

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick?(urls)
        cleanup()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel?()
        cleanup()
    }

    private func cleanup() {
        onPick = nil
        onCancel = nil
    }
}
