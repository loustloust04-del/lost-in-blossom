# 任务：修复文件选择器（SwiftUI fileImporter iPhone bug）

读 CLAUDE.md。不引入 regression。

## 问题

SwiftUI 的 `.fileImporter` 在真实 iPhone 上不工作——文件选择器能弹出来，但所有文件都无法点选，回调不触发。这是 SwiftUI 的已知 bug（Apple Forums thread/775056）。

影响范围：App 里所有使用 `.fileImporter` 的地方都坏了，包括：
- 发送文件（AddToChatSheet.swift）
- 导入聊天记录（ImportView.swift）  
- 导入 Preset（PersonaSettingsTab.swift）
- 导入世界书（WorldBookPanelView.swift）
- 导入字体（AppearanceSettingsTab.swift）

## 解决方案

用 UIKit 的 `UIDocumentPickerViewController` 包装成 SwiftUI View，替代所有 `.fileImporter` 调用。

### Step 1: 创建 DocumentPicker wrapper

新建 `MemoryPalace/Views/Components/DocumentPickerView.swift`：

```swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void
    
    init(
        contentTypes: [UTType] = [.item],
        allowsMultipleSelection: Bool = false,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onPick = onPick
        self.onCancel = onCancel
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void
        
        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
```

### Step 2: 替换所有 .fileImporter

在每个使用 `.fileImporter` 的文件里：

**替换前：**
```swift
.fileImporter(
    isPresented: $showFilePicker,
    allowedContentTypes: [UTType.item],
    allowsMultipleSelection: false
) { result in
    guard let url = (try? result.get())?.first else { return }
    // 处理文件...
}
```

**替换后：**
```swift
.sheet(isPresented: $showFilePicker) {
    DocumentPickerView(contentTypes: [.item]) { urls in
        showFilePicker = false
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        // 处理文件...
    } onCancel: {
        showFilePicker = false
    }
}
```

需要替换的文件：
1. `AddToChatSheet.swift` — 文件发送（contentTypes: [.item]）
2. `ImportView.swift` — 聊天导入（contentTypes: [.json]）
3. `PersonaSettingsTab.swift` — Preset 导入（contentTypes: [.json]）
4. `WorldBookPanelView.swift` — 世界书导入（contentTypes: [.json]）
5. `AppearanceSettingsTab.swift` — 字体导入（两处，contentTypes: [ttf/otf/ttc]）

每个文件都要确保 `startAccessingSecurityScopedResource()` 和 `stopAccessingSecurityScopedResource()` 正确调用。

---

一个 commit：`fix: replace SwiftUI fileImporter with UIKit DocumentPicker (iPhone bug workaround)`
