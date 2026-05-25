# Research: 壁纸保存时 center-crop + down-scale

> 2026-04-21
> 对应 Step 1：修 kelivo 路线 C 下 wallpaper view frame 奇怪尺寸（738.15 × 912）导致键盘弹起背景"动"的根因

## 一、实测证据

真机（iPhone 17 Air）log（commit 9850905 探针）：
```
[PROBE bg] wallpaper onAppear size=(738.15, 912.0) safeAreaInsets=EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 0.0)
[PROBE bg] PagingVC.viewDidLayoutSubviews bounds=(0.0, 0.0, 420.0, 912.0) safeAreaInsets=UIEdgeInsets(top: 68.0, left: 0.0, bottom: 34.0, right: 0.0)
```

- PagingVC.view 的 UIKit bounds width = 420（iPhone 17 Air portrait 屏幕宽）
- wallpaper 的 SwiftUI GeometryReader 报告 width = **738.15**（1.757× 屏幕宽）
- 高度 912 两侧一致

## 二、根因（带代码引用）

`ThemeAssetStore.swift:14-33`：
```swift
static func saveBackgroundImage(from url: URL, for themeId: String) throws -> String {
    let data = try Data(contentsOf: url)
    return try saveBackgroundImage(data: data, for: themeId, preferredExtension: url.pathExtension)
}

static func saveBackgroundImage(data: Data, for themeId: String, preferredExtension: String?) throws -> String {
    let fileExtension = sanitizedExtension(preferredExtension)
    let fileName = "theme-\(themeId)-\(UUID().uuidString).\(fileExtension)"
    let destination = assetsDirectoryURL.appendingPathComponent(fileName)
    try data.write(to: destination, options: .atomic)
    return fileName
}
```

**只做 Data 读取 + 直接写盘，无任何图像处理**。原图什么尺寸就存什么尺寸。

粟粟的壁纸图 @2x pixel size ≈ 1476×1824，转 point = **738×912**。

`ChatWallpaperBackdrop.swift:38-49`：
```swift
Image(uiImage: image)
    .resizable()
    .scaledToFill()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .offset(...)
    .saturation(0.92)
    .clipped()
```

`.scaledToFill()` 的行为（经验观察，`feedback_cite_evidence_no_guessing.md` 要求我标 ⚠️ 未严格 xcdoc 验证）：保持 aspect 撑到覆盖 container，可能超出 container。当 image aspect (0.81) ≠ container aspect (0.46 屏幕)，image 渲染 size 被撑到 738×912，这个 size 反作用于外层 ZStack 的 layout report。`.clipped()` 只管视觉裁剪，不改 layout size。

⚠️ 具体"image size 影响 ZStack GeometryReader 读数"的机制我没从 xcdoc 直接找到。但**从源头 fix**（让 image intrinsic 和 container aspect 匹配）就绕开了这个机制——无须彻底搞懂。

## 三、Fix 方向：保存时 center-crop + down-scale

### 总流程

```
原图 Data
  ↓
解码成 UIImage
  ↓
取当前 key window screen 的 bounds（得到设备屏幕 aspect）
  ↓
计算 center-crop rect（image pixel 坐标系）
  ↓
CGImage.cropping(to:) 得到 cropped CGImage
  ↓
UIGraphicsImageRenderer 渲染到 screen points × scale（down-scale）
  ↓
JPEG 压缩（壁纸视觉 loss 可接受）
  ↓
写盘
```

### 关键 API 引用

1. **`CGImage.cropping(to:)`**
   - xcdoc: `/documentation/CoreGraphics/CGImage/cropping(to:)`
   - 语义："Creates a bitmap image using the data contained within a subregion of an existing bitmap image"
   - ⚠️ rect 坐标系是 **CGImage pixel**，不是 UIImage point。`cgImage.width / cgImage.height` 是 pixel 尺寸
   - 重要：文档明确 "Be sure to specify the subrectangle's coordinates relative to the original image's full size, even if the UIImageView shows only a scaled version"

2. **`UIGraphicsImageRenderer(size:format:)`**
   - xcdoc: `/documentation/UIKit/UIGraphicsImageRenderer/init(size:format:)`
   - size 是 **points**，format.scale 决定输出 pixel density
   - output pixels = size.width × format.scale × size.height × format.scale

3. **`UIImage.init(CGImage:scale:orientation:)`**
   - xcdoc: `/documentation/UIKit/UIImage/init(CGImage:scale:orientation:)`
   - 从裁切后的 CGImage 包回 UIImage，指定 scale 和 orientation

4. **`UIImage.jpegData(compressionQuality:)`** / `pngData()`
   - xcdoc: `/documentation/UIKit/UIImage/pngData()`
   - 壁纸建议 JPEG（有损省空间），quality 0.9 视觉无感知 loss

5. **当前设备 screen bounds 取法**
   - xcdoc: `/documentation/UIKit/UIWindowScene/keyWindow`
   - iOS 16+ 推荐用 `UIWindowScene.keyWindow` 而不是 `UIScreen.main`
   - 路径：`UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }) ?? fallback`
   - 项目里 `ContentView.swift:316-336` 已有类似的 `screenSafeAreaBottom` / `screenSafeAreaTop` helper，用同样 pattern 复用 fallback

### Orientation 陷阱

⚠️ `UIImage.imageOrientation` 可能是 `.right` / `.down` 等（iPhone 拍的照片 EXIF），而 `UIImage.cgImage` **不应用 orientation**，直接访问 pixel data。

处理方式（经验）：
- 进 crop 前先 redraw 成 `.up` orientation：
  ```swift
  let normalized = UIGraphicsImageRenderer(size: source.size).image { _ in
      source.draw(in: CGRect(origin: .zero, size: source.size))
  }
  // normalized.cgImage 是 .up 方向的 pixel
  ```
- 或者 crop rect 考虑 orientation 做 transform

第一个方案简单，一次性处理。

### Center-crop rect 计算（图像 pixel 坐标系）

```swift
let imgW = CGFloat(cgImage.width)    // pixels
let imgH = CGFloat(cgImage.height)
let imgAspect = imgW / imgH
let screenAspect = screenBounds.width / screenBounds.height

let cropRect: CGRect
if imgAspect > screenAspect {
    // image 更宽（粟粟的 738×912 情形：0.81 > 屏幕 0.46 是 false；image 比屏幕瘦）
    let newW = imgH * screenAspect
    cropRect = CGRect(x: (imgW - newW) / 2, y: 0, width: newW, height: imgH)
} else {
    // image 更瘦（粟粟情形匹配：height fill，width 裁）
    let newH = imgW / screenAspect
    cropRect = CGRect(x: 0, y: (imgH - newH) / 2, width: imgW, height: newH)
}
```

粟粟图 aspect 0.81，屏幕 0.46 → image 比屏幕宽得多 → 按 image 更宽分支。等等算：
- imgW = 1476, imgH = 1824
- imgAspect = 1476 / 1824 = 0.809
- screenAspect = 420 / 912 = 0.461
- imgAspect > screenAspect ✓
- newW = 1824 × 0.461 = 841
- cropRect = (x:(1476-841)/2=317, y:0, w:841, h:1824)

crop 后 image pixel size = 841 × 1824，aspect = 0.461 匹配屏幕 ✅

### Down-scale target

- screen points = 420 × 912（iPhone 17 Air 例）
- screen scale = 3（@3x）
- target output pixels = 1260 × 2736

UIGraphicsImageRenderer：
```swift
let format = UIGraphicsImageRendererFormat.default()
format.scale = screenScale  // 从 UIWindowScene.screen.scale 取
format.opaque = true         // 壁纸不透明
let renderer = UIGraphicsImageRenderer(size: screenPoints, format: format)
let result = renderer.image { ctx in
    UIImage(cgImage: croppedCG).draw(in: CGRect(origin: .zero, size: screenPoints))
}
```

输出 UIImage：
- UIImage.size = screenPoints (420 × 912)
- underlying pixels = 1260 × 2736
- 这样 ChatWallpaperBackdrop 里 Image(uiImage:) 的 intrinsic point size = 420 × 912 = 屏幕尺寸

### 内存考量

- `UIImage(data:)` lazy decode，OK
- 访问 `.cgImage` 会触发 decode → 粟粟 4MB 图解压大概 20-30MB RAM 瞬时占用（1476×1824×4 bytes ≈ 10MB）
- 壁纸选择是**不频繁**的 one-shot 操作，瞬时内存可接受
- 处理完 crop + down-scale 后原 UIImage 可释放，final output 只 1260×2736×4 ≈ 14MB（pixel buffer），encode 成 JPEG 后写盘 ~500KB-1MB

⚠️ 如果担心 huge image 爆内存（比如专业相机 RAW 几十 MB），可以用 `CGImageSourceCreateThumbnailAtIndex` 先 downsample 到合理 size 再 decode。第一版先不做，看实测有没有问题。

参考 xcdoc：`/documentation/ImageIO/CGImageSource`（未查具体 thumbnail API，备选）

## 四、既有壁纸迁移

当前 app support 目录里 `ThemeAssets/` 下有老壁纸文件（原尺寸未 crop）。Step 1 改动只影响**新选的**壁纸。

粟粟要验证 crop 效果 → **需要重新选一次壁纸**走新路径。老文件不管它（占空间但不出 bug，因为新 crop 逻辑应用的是**保存时**）。

或者 plan 里加一个 migration 选项（app 启动时对 ThemeAssets/ 下所有文件 reprocess）。⚠️ 但 migration 有风险（万一处理错毁了原图），第一版不做。

## 五、潜在问题

### P1：screen aspect 随 orientation / 设备变化

- 用户选壁纸时是 portrait，crop 存 portrait aspect
- 之后切 landscape（iPad 或 iPhone 横屏），壁纸 aspect 不匹配 container
- 当前 MemoryPalace 只支持竖屏？需要看 project.yml 里 supported orientations
- 如果只 portrait，不是问题

### P2：Image intrinsic 和 ZStack layout 关系没完全搞懂

- 根因定位靠的是"image intrinsic = 屏幕 aspect 后 `.scaledToFill` 不撑出去"的经验，没从 xcdoc 严格验证 SwiftUI layout 对 image intrinsic size 的 propagation 机制
- 但 Step 1 是从源头避开这个机制，不依赖它搞清楚——改完如果 wallpaper size = 420 × 912 = 屏幕尺寸，那 hypothesis 验证正确；如果不是，说明机制更复杂，需要进一步调查

### P3：键盘弹起背景是否还动

- 这个问题和 738 宽度谜团**可能相关也可能不相关**
- Step 1 修完 image intrinsic，需要粟粟重新测键盘，看背景是否还动
- 如果不动：738 root cause 解决一切，B 系列只剩输入框位置
- 如果还动：还有另一个根因，需 B 系列探针进一步定位

## 六、记忆索引

- `reference_xcdocs.md` — xcdocs 查 Apple API
- `feedback_cite_evidence_no_guessing.md` — 每个 claim 带引用
- `feedback_probes_over_reasoning.md` — 诡异 bug 加探针（已用）
- `docs/research-chat-input-keyboard-avoid.md` — 上游键盘 research（关联）
