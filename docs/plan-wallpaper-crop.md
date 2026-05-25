# Plan: 壁纸保存时 center-crop + down-scale（Step 1）

> 2026-04-21
> 依赖：`docs/research-wallpaper-crop.md`
> 目的：从源头让 wallpaper image intrinsic size = 屏幕尺寸，修 SwiftUI 层 738.15×912 怪尺寸

## 目标

`ThemeAssetStore.saveBackgroundImage(data:...)` 在写盘前做：
1. 读 Data → UIImage
2. Orientation 归一化成 `.up`
3. 按**当前设备 portrait 屏幕 aspect** center-crop
4. Down-scale 到屏幕 points × scale
5. JPEG 编码（quality 0.9）
6. 写盘（扩展名统一改 `.jpg`）

UI 无改动。**仅 backend 图像处理**。

## Orientation 策略

⚠️ iPhone 支持 portrait + landscape（project.yml `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`），iPad 支持全部四方向。但 MemoryPalace 的 iOS 布局主要为 portrait（PagingContainerView 水平 paging 在 portrait 体验设计）。

决定：**强制用 portrait aspect 存壁纸**。即 `min(w, h)` × `max(w, h)`。这样：
- 用户 portrait 选壁纸：aspect 匹配主要使用场景 ✅
- 用户 landscape 选壁纸（少见）：存 portrait aspect，landscape 下 `.scaledToFill` 自动 crop（中心可见）
- iPad 多 orientation：同上

## 修改点

### 1. `MemoryPalace/Utils/ThemeAssetStore.swift`

在 `saveBackgroundImage(data:for:preferredExtension:)` 里插入图像处理。原函数保留框架，中间换成 crop + encode 后的 Data。

**新增 helper**（同文件 `enum ThemeAssetStore` 内 static func）：

```swift
/// Center-crop 图片到当前设备 portrait 屏幕 aspect + down-scale 到屏幕 pixel，
/// 返回 JPEG 编码 Data + 扩展名 "jpg"。解决 wallpaper 原图 intrinsic size 在 SwiftUI
/// ZStack 里撑出奇怪 frame 的问题（见 docs/research-wallpaper-crop.md）。
///
/// orientation 归一化 + center-crop + 渲染到 target size。
/// - image source: raw Data
/// - returns: 处理后的 JPEG Data。如果任何一步失败，fallback 返回原 Data（不阻塞用户换壁纸）。
private static func processWallpaperForStorage(_ data: Data) -> (data: Data, ext: String) {
    guard let source = UIImage(data: data) else { return (data, "png") }

    // 1. 目标 portrait 屏幕尺寸 + scale
    let screenPoints = currentPortraitScreenPoints()  // e.g., 420 × 912
    let screenScale = currentScreenScale()            // e.g., 3

    // 2. Orientation 归一化成 .up（UIImage.cgImage 不应用 EXIF orientation，先 redraw）
    let normalized: UIImage = {
        if source.imageOrientation == .up { return source }
        let renderer = UIGraphicsImageRenderer(size: source.size)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }
    }()

    guard let cg = normalized.cgImage else { return (data, "png") }

    // 3. center-crop rect（pixel 坐标系）
    let imgW = CGFloat(cg.width)
    let imgH = CGFloat(cg.height)
    let imgAspect = imgW / imgH
    let screenAspect = screenPoints.width / screenPoints.height

    let cropRect: CGRect
    if imgAspect > screenAspect {
        // image 相对更宽，裁 width 保 height
        let newW = (imgH * screenAspect).rounded(.down)
        cropRect = CGRect(x: ((imgW - newW) / 2).rounded(.down), y: 0, width: newW, height: imgH)
    } else {
        // image 相对更瘦，裁 height 保 width
        let newH = (imgW / screenAspect).rounded(.down)
        cropRect = CGRect(x: 0, y: ((imgH - newH) / 2).rounded(.down), width: imgW, height: newH)
    }
    guard let cropped = cg.cropping(to: cropRect) else { return (data, "png") }

    // 4. down-scale 到 screenPoints × screenScale
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = screenScale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: screenPoints, format: format)
    let final = renderer.image { _ in
        UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: screenPoints))
    }

    // 5. JPEG
    guard let jpeg = final.jpegData(compressionQuality: 0.9) else { return (data, "png") }
    return (jpeg, "jpg")
}

/// 当前设备 portrait 屏幕尺寸 (points)。取 key window scene 的 screen.bounds，
/// 强制 min→width / max→height（应对用户 landscape 下选壁纸的场景）。
/// Fallback: UIScreen.main（iOS 16+ 未 deprecated 但推荐 scene API）。
private static func currentPortraitScreenPoints() -> CGSize {
    let bounds: CGRect = {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
        return scene?.screen.bounds ?? UIScreen.main.bounds
    }()
    let w = min(bounds.width, bounds.height)
    let h = max(bounds.width, bounds.height)
    return CGSize(width: w, height: h)
}

private static func currentScreenScale() -> CGFloat {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first(where: { $0.activationState == .foregroundActive })
        ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
    return scene?.screen.scale ?? UIScreen.main.scale
}
```

**修改 `saveBackgroundImage(data:...)`**：

```swift
static func saveBackgroundImage(
    data: Data,
    for themeId: String,
    preferredExtension: String?
) throws -> String {
    let processed = processWallpaperForStorage(data)           // ← 新增
    let fileExtension = sanitizedExtension(processed.ext)      // ← 用 processed.ext 而非 preferredExtension
    let fileName = "theme-\(themeId)-\(UUID().uuidString).\(fileExtension)"
    let destination = assetsDirectoryURL.appendingPathComponent(fileName)
    try processed.data.write(to: destination, options: .atomic)
    return fileName
}
```

### 2. 加 `import UIKit`（`ThemeAssetStore.swift` 当前只 `import Foundation`）

### 3. 其它入口核查

- `setBackgroundImage(from url: URL, ...)` → 调 `saveBackgroundImage(data:)` ✓ 自动走新路径
- `copyBackgroundImage(named:for:)` —— 复制已在 ThemeAssets/ 里的老文件到新 theme（复制预设？）。**这条路径 source 已经是 processed 过的（新壁纸）或 raw（老壁纸）**。为了简化，这条路径**保持原样**（直接 FileManager copy）不 reprocess。如果老文件没 crop，换主题后仍然有 738 问题——但 **换主题是小概率，用户会重新选一次壁纸**。

## Checklist

- [ ] 1. `ThemeAssetStore.swift` 加 `import UIKit`
- [ ] 2. 添加 `processWallpaperForStorage` helper
- [ ] 3. 添加 `currentPortraitScreenPoints` / `currentScreenScale` helper
- [ ] 4. 修改 `saveBackgroundImage(data:for:preferredExtension:)` 调用 helper
- [ ] 5. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination "generic/platform=iOS" build` 通过
- [ ] 6. commit + push
- [ ] 7. 粟粟真机：**重新选一次壁纸**（走新 crop 路径），查 log：
  - `[PROBE bg] wallpaper onAppear size=(W, H)` 的 W/H 应 ≈ 屏幕尺寸（例如 420×912），**不再是 738.15**
  - 聊天页翻页时背景应该不延迟
  - 键盘弹起时背景是否还动 → 报现象决定 B 系列方向

## Fallback 行为

任何一步失败（decode / crop / render / encode）→ 返回原 Data，保持原流程不阻塞用户。`data, "png"` 用 PNG 扩展名是因为 raw Data 不知道类型——但如果 raw Data 是 JPEG，写 `.png` 扩展名文件也能被 UIImage 读取（扩展名在 iOS 不是 MIME 决定因素，UIImage 根据 magic byte 判断）。安全。

## 风险和未解

- ⚠️ **巨大图片的内存峰值**：`.cgImage` 触发 decode，粟粟 4MB 图约 20-30MB RAM 瞬时。壁纸选择不频繁，可接受。若粟粟上传 RAW 几十 MB → 可能 OOM。第一版不处理，后续用 `CGImageSource thumbnail` 优化。
- ⚠️ **老壁纸文件不 migration**：已保存的壁纸仍是原尺寸。粟粟重新选壁纸才走新路径。
- ⚠️ **Step 1 完成不能 100% 保证"键盘弹起背景不动"修好**：如果还动，有另一根因（可能是 SwiftUI layout 的 keyboard region 和 PagingContainerView 交互），需 B 系列探针深入。

## 关联 tasks

- A9 实施这个 plan
- A10 粟粟验证，看 738 → 屏幕尺寸 + 键盘弹起现象
- 后续 Step 2（手动 crop sheet）作为 feature enhancement，B 系列完成后再议

## 等待粟粟批注

批注方式：在这个文件直接改/加批注（`⬅ 粟粟意见：...`）。我根据批注改 plan。没意见直接回 "go" 我开工。
