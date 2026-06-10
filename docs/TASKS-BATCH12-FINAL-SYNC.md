# 第十二批任务 — 最后四个文件同步

> 日期：2026-06-10
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟 VPS `/root/projects/SusuPalace/MemoryPalace/`

---

## Task 1: ChatToolTypes.swift（MCP工具类型）
**源**: `Models/ChatToolTypes.swift`
**目标**: `MemoryPalace/Models/ChatToolTypes.swift`
- 直接照搬，不改
**commit**: `feat: add ChatToolTypes (MCP tool call/result types) from susu`

## Task 2: AttachmentTextExtractor.swift（PDF文本提取）
**源**: `Services/AttachmentTextExtractor.swift`
**目标**: `MemoryPalace/Services/AttachmentTextExtractor.swift`
- 直接照搬，不改
**commit**: `feat: add AttachmentTextExtractor (PDF/file text extraction) from susu`

## Task 3: SpeechService.swift（TTS语音）
**源**: `Services/SpeechService.swift`
**目标**: `MemoryPalace/Services/SpeechService.swift`
- 直接照搬，不改
**commit**: `feat: add SpeechService (TTS voice) from susu`

## Task 4: GlassBackButton.swift（毛玻璃按钮）⚠️ 需要改
**源**: `Views/GlassBackButton.swift`
**目标**: `MemoryPalace/Views/GlassBackButton.swift`

**⚠️ 粟粟用了 iOS 26 专属的 `.glassEffect()` API，我们的编译环境不支持！**

**替换方案**——把 `.glassEffect(...)` 换成兼容 iOS 17+ 的毛玻璃效果：

```swift
// 粟粟的（iOS 26专属，不能用）：
// .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)

// 替换成（iOS 17+ 兼容）：
.background(.ultraThinMaterial, in: Circle())
```

完整的兼容版本：
```swift
import SwiftUI

#if os(iOS)
struct GlassBackButton: View {
    var systemImage: String = "chevron.left"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
#endif
```

**commit**: `feat: add GlassBackButton with iOS 17+ compatible material (no glassEffect)`

---

## 规则
- Task 1-3 照搬不改
- Task 4 必须替换 glassEffect → ultraThinMaterial
- 每个 Task 单独 commit + push
