# Research: iOS wallpaper 挪到 UIKit 层（Step 3）

> 2026-04-21
> 对应：修键盘弹起 wallpaper "动"（SwiftUI `.background` + `.ignoresSafeArea` 在 child HC + keyboard region 组合下 frame 响应键盘放大 13%）

## 一、Step 1/Step 3-lite 被否的证据

真机 log（commit 9850905 探针 + commit 2320429 crop 测试）：
```
# 新 wallpaper (crop 后，aspect 匹配屏幕 0.46)
wallpaper onAppear size=(427.83, 929.0)   ← 初始
wallpaper size changed to (484.01, 1051.0)  ← 键盘弹起，等比放大 13%
wallpaper size changed to (427.83, 929.0)   ← 键盘收起
# 反复抖动
```

- `PagingVC.viewDidLayoutSubviews` 键盘时**不** fire → UIKit `view.bounds` 不变
- SwiftUI 层 wallpaper frame 响应键盘放大
- 说明：**问题在 SwiftUI `.background` + `.ignoresSafeArea` 对 keyboard safeArea 的 layout 响应机制**，不是 UIKit

结论：只要 wallpaper 挂在 SwiftUI layer，就会被 SwiftUI 的 keyboard region 折腾。唯一根治——**挂到 UIKit 层**，UIKit 层 view.bounds 不响应键盘，UIImageView frame 随 superview.bounds，就稳了。

## 二、ChatWallpaperBackdrop 的视觉要素对照（源码引用）

`MemoryPalace/Views/ChatWallpaperBackdrop.swift:24-91`

| SwiftUI 表达 | UIKit 对应 | 文档引用 |
|---|---|---|
| `ZStack { fill ; artworkView }` | UIView + subviews 按顺序叠 | — |
| `fill` (`Color`) | `UIView.backgroundColor = UIColor(resolvedFill)` | — |
| `Image(uiImage:).resizable().scaledToFill()` | `UIImageView.contentMode = .scaleAspectFill` + `clipsToBounds=true` | xcdoc: `/documentation/UIKit/UIView/ContentMode-swift.enum/scaleAspectFill` — "Scales the content to fill the size of the view. Some portion of the content may be clipped to fill the view's bounds" |
| `.frame(maxWidth: .infinity, maxHeight: .infinity)` | frame = superview.bounds（手动同步） | — |
| `.offset(x: resolvedOffsetX, y: resolvedOffsetY)` | `UIImageView.transform = CGAffineTransform(translationX:, y:)` | — |
| `.saturation(0.92)` | CIFilter.colorControls 预处理 image | xcdoc: `/documentation/CoreImage/CIFilter-swift.class/colorControls()` — "Alters the brightness, contrast, and saturation of an image's colors" |
| `.clipped()` | `clipsToBounds = true` | — |
| `.opacity(backgroundStyle.resolvedOpacity)` | `UIImageView.alpha = opacity` | — |
| `.overlay(LinearGradient)` | `CAGradientLayer` 作为 overlay view.layer | xcdoc: `/documentation/QuartzCore/CAGradientLayer` — "A layer that draws a color gradient... filling the shape of the layer" |
| gradient 3 个 stops (0, 0.5, 1) | `CAGradientLayer.colors = [...], locations = [0, 0.5, 1]` | — |
| startPoint = top / endPoint = bottom | `CAGradientLayer.startPoint = (0.5, 0), endPoint = (0.5, 1)` | — |

**视觉要素 summary**：fill color + image (scaleAspectFill + alpha + offset transform + saturation filter) + gradient overlay. 三层同属一个容器 UIView，frame 锁死为 PagingViewController.view.bounds。

## 三、UIKit 实现架构

### View hierarchy 新方案

```
PagingViewController.view (backgroundColor = Theme.mainBg)
├── wallpaperContainer (UIView, frame = view.bounds, 永远全屏)
│   ├── imageView (UIImageView, contentMode = .scaleAspectFill, clipsToBounds)
│   └── gradientLayer (CAGradientLayer) ← 作为 wallpaperContainer.layer 的 sublayer，盖在 imageView 上
├── scrollView (已有，clear bg)
│   ├── listHC.view (clear bg, .background(sidebarBg) SwiftUI 层实底遮 wallpaper)
│   ├── chatHC.view (clear bg, transparent 透过 wallpaper)
│   └── dashHC.view (clear bg, .background(sidebarBg) SwiftUI 层实底遮)
```

**关键**：wallpaperContainer 在 scrollView **之前** add 进 view（z 顺序：wallpaper 底层，scrollView 上层）。scrollView 和 list/dash page 的 SwiftUI 实底遮 wallpaper，chat page 透明。

`xcdoc: /documentation/QuartzCore/CALayer/insertSublayer(_:above:)` 控制 gradientLayer 位置。

### PagingViewController 新 API

```swift
// 外部接口
func applyWallpaper(fill: UIColor,
                    imageURL: URL?,
                    saturation: CGFloat,
                    opacity: CGFloat,
                    offsetX: CGFloat,
                    offsetY: CGFloat,
                    gradientColors: [UIColor],
                    gradientLocations: [NSNumber])
```

参数基本是 ChatWallpaperBackdrop 的 props 展开。每次 SwiftUI state 变化时由 PagingContainerView.updateUIViewController 调用。

内部状态：
- `private var wallpaperContainer: UIView`
- `private var wallpaperImageView: UIImageView`
- `private var wallpaperGradientLayer: CAGradientLayer`
- `private var lastImageURL: URL?` （避免重复 decode 同一 image）
- `private var lastSaturation: CGFloat`（避免重复 CI filter）

image 变化时才 CIFilter。scheme 变化（gradient colors）只更新 layer.colors，无重 decode。

### Saturation CIFilter 细节

```swift
import CoreImage
import CoreImage.CIFilterBuiltins

private func applySaturation(_ saturation: CGFloat, to image: UIImage) -> UIImage {
    guard saturation != 1.0, let ciImage = CIImage(image: image) else { return image }
    let filter = CIFilter.colorControls()
    filter.inputImage = ciImage
    filter.saturation = Float(saturation)
    guard let output = filter.outputImage else { return image }
    let context = CIContext()
    guard let cg = context.createCGImage(output, from: output.extent) else { return image }
    return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
}
```

⚠️ CIContext 创建有 GPU 上下文成本。每次 setWallpaper 创建一个可接受（不频繁）。更好：持有一个 static 共享 CIContext。

⚠️ Filter 全图处理，4MB 图约 30-50MB 内存峰值。壁纸原图 1476×1824 尚可接受。之后 Step 2 手动 crop 会小很多。

### Color scheme 处理

PagingViewController 不感知 SwiftUI ColorScheme，由 SwiftUI 侧计算好 gradientColors 传入。`PagingContainerView.updateUIViewController` 接收 scheme，转换 ColorScheme → UIColor[] 后传。

ChatWallpaperBackdrop 当前逻辑（`:78-91`）保留到 PagingContainerView 或 helper：
```swift
let gradientColors: [UIColor] = {
    if scheme == .dark {
        return [UIColor.black.withAlphaComponent(0.42),
                UIColor.black.withAlphaComponent(0.18),
                UIColor.black.withAlphaComponent(0.50)]
    } else {
        return [UIColor.white.withAlphaComponent(0.18),
                UIColor.white.withAlphaComponent(0.04),
                UIColor.white.withAlphaComponent(0.24)]
    }
}()
```

### viewDidLayoutSubviews 同步 frame

`PagingViewController.viewDidLayoutSubviews`（当前 `:73-94`）末尾加：
```swift
wallpaperContainer.frame = view.bounds
wallpaperImageView.frame = wallpaperContainer.bounds
wallpaperGradientLayer.frame = wallpaperContainer.bounds
```

`viewDidLayoutSubviews` 在 **view.bounds 变化** 时 fire。键盘弹起不触发（实测 A10 log 验证），所以 wallpaper frame 不会随键盘变。根治 ✓

## 四、ContentView.iOSLayout 改动

当前（commit 879d536 + d9b9b3f）：
```swift
PagingContainerView(...)
    .ignoresSafeArea()
    .background {
        if iOSPage == 1 {
            ChatWallpaperBackdrop(...).ignoresSafeArea()
        }
    }
```

改为：
```swift
PagingContainerView(
    ...,
    // 新增 wallpaper 参数
    wallpaperFill: Theme.mainBg,
    wallpaperImageURL: manager.currentBackgroundImageURL,
    wallpaperSaturation: 0.92,
    wallpaperOpacity: manager.currentBackgroundStyle.resolvedOpacity(for: colorScheme),
    wallpaperOffsetX: manager.currentBackgroundStyle.resolvedOffsetX,
    wallpaperOffsetY: manager.currentBackgroundStyle.resolvedOffsetY,
    wallpaperColorScheme: colorScheme
)
.ignoresSafeArea()
// 无 .background 了
```

**没有 `if iOSPage == 1` 条件**：wallpaper 始终挂 UIKit 底层，翻页无延迟（A5 问题自动解决）。列表/面板页由各自 SwiftUI `.background(sidebarBg)` 遮挡 wallpaper。

## 五、ChatWallpaperBackdrop 处理

**方案 A**：iOS 不再用它，**整个文件删**（macOS 不用）。检查引用：
- `ContentView.swift:164`（注释提到）
- `ContentView.swift` iOSChatPage 用过（已 revert 删除）
- macOS 路径？—— `ContentView.swift:152-158` 用的是 `ThemeBackgroundView`，不是 `ChatWallpaperBackdrop`

→ ChatWallpaperBackdrop 只有 iOS 的 `.background` 用过，可以删除整个文件。探针也一起拿掉。

## 六、iOSChatPage 处理

当前（d9b9b3f）：
```swift
private var iOSChatPage: some View {
    ZStack(alignment: .top) {
        if viewModel.selectedConversation != nil {
            CardFlowView(...)
        } else {
            EmptyStateView(...)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .top) { iOSChatTopBar }
}
```

无 `.background`，透明。✓ 不需要改。

## 七、内存 / 性能考量

- `UIImage(contentsOfFile:)` lazy decode：实测粟粟壁纸 1476×1824 decode 后约 10-30MB 内存
- CIFilter saturation 全图处理：另外 10-30MB 瞬时
- 壁纸换一次，保留在 UIImageView 里（active chat session 期间常驻）
- 可接受（不像每个 bubble 一张图那样频繁）

**防重复处理**：
```swift
func applyWallpaper(...) {
    if lastImageURL == imageURL && lastSaturation == saturation {
        // 只更新 gradient / alpha / offset
    } else {
        // 重新 load + filter image
    }
}
```

## 八、陷阱 / 风险

### R1：gradient overlay 在 CALayer 不能直接 alpha blend

CAGradientLayer 是 CALayer 的 subclass，直接渲染颜色。作为 wallpaperContainer 的 sublayer，盖在 imageView 之上。没问题。

### R2：offset 对 scaleAspectFill 的影响

SwiftUI `.offset` 把视图平移（frame 不变，render 位置变）。UIKit 用 `.transform = CGAffineTransform(translationX:, y:)` 同效（transform 不改 frame 属性）。

但 `.scaleAspectFill` 先 scale image 到 fill bounds，可能 overflow；`.transform` translate 不改 scale。视觉等价 SwiftUI。

⚠️ 要测试：小 offsetX/Y 视觉对齐应该正确。

### R3：Scheme 切换时 gradient 更新

SwiftUI `.onChange(of: colorScheme)` 在 `ContentView` 层或 `PagingContainerView`。每次触发 `updateUIViewController` 重算 gradientColors → 调 `applyWallpaper`。Flow OK。

### R4：动画效果

SwiftUI 层有 `.transition` / `.animation` 等。UIKit 层无动画。切换壁纸时**硬切**（无过渡）。

→ 如果要保持柔软换壁纸体验，可在 applyWallpaper 里用 `UIView.transition(with: imageView, ...)` 加 cross-fade。第一版不做，观察体验。

### R5：Wallpaper 有时不该显示（用户选无 wallpaper 的主题）

当前 imageURL 可选，nil 时不绘 image，只绘 fill color。

```swift
if imageURL == nil {
    imageView.image = nil
    imageView.isHidden = true
    wallpaperContainer.backgroundColor = fillColor
}
```

### R6：PagingContainerView 的 init 参数爆炸

加 6~7 个 wallpaper 参数到 init 有点臃肿。可以打包成 struct：
```swift
struct WallpaperConfig: Equatable {
    let fill: Color
    let imageURL: URL?
    let saturation: CGFloat
    let opacity: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let colorScheme: ColorScheme
}
```

一个参数 `wallpaper: WallpaperConfig`。clean。

### R7：CIContext 性能

每次 applyWallpaper 创建 CIContext 有 GPU 上下文开销（约 10-30ms）。static shared 更好：
```swift
private static let sharedCIContext = CIContext()
```

## 九、验证

Step 3 实施后需要再次加 UIKit 层探针（不同于之前 SwiftUI 探针）：

```swift
// PagingViewController.viewDidLayoutSubviews 底部
#if DEBUG
print("[PROBE bg uikit] wallpaperContainer.frame=\(wallpaperContainer.frame) imageView.frame=\(wallpaperImageView.frame)")
// 加键盘通知监听，打印 wallpaperContainer.frame（键盘 up/down 时）
#endif
```

预期：键盘 up/down 时 wallpaperContainer.frame **不变**。

## 十、关联

- `docs/research-wallpaper-crop.md` / `plan-wallpaper-crop.md` — Step 1 crop 的调研（已撤）
- `docs/research-chat-input-keyboard-avoid.md` — 键盘响应根 research
- A10 验证 log 是决定走 Step 3 的证据基础
- B 系列（输入框上浮）与此独立，之后处理

## 十一、记忆索引

- `feedback_cite_evidence_no_guessing.md` — claim 带引用
- `feedback_probes_over_reasoning.md` — 探针先于推理
- `feedback_ignoressafearea_hosting_overflow.md` — UIHostingController hierarchy clipsToBounds
- `reference_xcdocs.md` — xcdocs 查 API
