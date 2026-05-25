# Plan: iOS wallpaper 挪到 UIKit 层（Step 3）

> 2026-04-21
> 依赖：`docs/research-wallpaper-uikit-layer.md`
> 目的：wallpaper 挂 PagingViewController.view 底层 UIImageView，绕开 SwiftUI `.background` + `.ignoresSafeArea` 对 keyboard safeArea 的 layout 响应

## 目标

- wallpaper 显示在 chat page 透过 UIKit 层（永远全屏，键盘不影响）
- 翻页 wallpaper 无延迟（废弃 `if iOSPage == 1` 条件）
- 视觉与 `ChatWallpaperBackdrop` 一致（fill + image scaleAspectFill + offset + saturation + opacity + gradient overlay）
- 视为 B 系列（输入框 2× 空白）的前置条件解决——确认背景问题彻底定位到 SwiftUI layer

## 修改点（有序）

### 1. `MemoryPalace/Views/Paging/PagingViewController.swift`

加 wallpaper layer + API。**撤销 A6 时加的 `[PROBE bg]` viewDidLayoutSubviews 探针**（但加新的 UIKit 层探针做 Step 3 验证）。

伪代码：
```swift
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

final class PagingViewController: UIViewController, UIScrollViewDelegate {
    // ... 原有属性

    // 新增 wallpaper
    private let wallpaperContainer = UIView()
    private let wallpaperImageView = UIImageView()
    private let wallpaperGradientLayer = CAGradientLayer()
    private var lastImageURL: URL?
    private var lastSaturation: CGFloat = 1.0

    private static let sharedCIContext = CIContext()

    override func viewDidLoad() {
        super.viewDidLoad()
        // ... 原有 setup ...

        // wallpaper 挂在 scrollView 之前（z 低）
        wallpaperContainer.backgroundColor = .clear
        wallpaperContainer.clipsToBounds = true
        wallpaperImageView.contentMode = .scaleAspectFill
        wallpaperImageView.clipsToBounds = true
        wallpaperContainer.addSubview(wallpaperImageView)
        wallpaperContainer.layer.addSublayer(wallpaperGradientLayer)
        wallpaperGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        wallpaperGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        view.insertSubview(wallpaperContainer, at: 0)   // ← 底层

        // 原有 scrollView.addSubview + HC 挂载 ...
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        wallpaperContainer.frame = view.bounds
        wallpaperImageView.frame = wallpaperContainer.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaperGradientLayer.frame = wallpaperContainer.bounds
        CATransaction.commit()

        scrollView.frame = view.bounds
        // ... 原有 HC layout ...
    }

    func applyWallpaper(_ config: WallpaperConfig) {
        // fill
        wallpaperContainer.backgroundColor = UIColor(config.fill)

        // image + saturation
        if config.imageURL != lastImageURL || config.saturation != lastSaturation {
            lastImageURL = config.imageURL
            lastSaturation = config.saturation
            if let url = config.imageURL,
               let raw = UIImage(contentsOfFile: url.path) {
                wallpaperImageView.image = applySaturation(config.saturation, to: raw)
                wallpaperImageView.isHidden = false
            } else {
                wallpaperImageView.image = nil
                wallpaperImageView.isHidden = true
            }
        }

        // alpha + offset
        wallpaperImageView.alpha = config.opacity
        wallpaperImageView.transform = CGAffineTransform(translationX: config.offsetX, y: config.offsetY)

        // gradient
        wallpaperGradientLayer.colors = config.gradientColors.map { $0.cgColor }
        wallpaperGradientLayer.locations = [0, 0.5, 1]
    }

    private func applySaturation(_ saturation: CGFloat, to image: UIImage) -> UIImage {
        guard saturation != 1.0, let ciImage = CIImage(image: image) else { return image }
        let filter = CIFilter.colorControls()
        filter.inputImage = ciImage
        filter.saturation = Float(saturation)
        guard let out = filter.outputImage,
              let cg = Self.sharedCIContext.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct WallpaperConfig {
    let fill: Color
    let imageURL: URL?
    let saturation: CGFloat
    let opacity: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let gradientColors: [UIColor]
}
```

### 2. `MemoryPalace/Views/Paging/PagingContainerView.swift`

加 wallpaper 参数（或 WallpaperConfig struct），在 `updateUIViewController` 里调 `applyWallpaper`。

```swift
struct PagingContainerView: UIViewControllerRepresentable {
    let listPage: AnyView
    let chatPage: AnyView
    let dashPage: AnyView
    @Binding var currentPage: Int
    let disableScroll: Bool
    let initialPage: Int
    let wallpaper: WallpaperConfig   // ← 新增

    func makeUIViewController(...) -> PagingViewController { ... }

    func updateUIViewController(_ vc: PagingViewController, context: Context) {
        vc.updatePages(...)
        vc.setScrollEnabled(...)
        vc.applyWallpaper(wallpaper)   // ← 新增
        ...
    }
}
```

### 3. `MemoryPalace/Views/ContentView.swift` — iOSLayout

撤 `.background { ChatWallpaperBackdrop }`，wallpaper 参数打包传给 PagingContainerView。

```swift
private var iOSLayout: some View {
    let manager = themeManager ?? ThemeManager.shared
    let config = WallpaperConfig(
        fill: Theme.mainBg,
        imageURL: manager.currentBackgroundImageURL,
        saturation: 0.92,
        opacity: manager.currentBackgroundStyle.resolvedOpacity(for: colorScheme),
        offsetX: manager.currentBackgroundStyle.resolvedOffsetX,
        offsetY: manager.currentBackgroundStyle.resolvedOffsetY,
        gradientColors: wallpaperGradientColors(for: colorScheme)
    )
    return PagingContainerView(
        listPage: AnyView(injectPagingEnv(iOSListPage)),
        chatPage: AnyView(injectPagingEnv(iOSChatPage)),
        dashPage: AnyView(injectPagingEnv(iOSDashboardPage)),
        currentPage: $iOSPage,
        disableScroll: stickerVM.isEditingStickers,
        initialPage: 1,
        wallpaper: config
    )
    .ignoresSafeArea()
    // 无 .background
    .sensoryFeedback(...)
    .onChange(...)
    ...
}

private func wallpaperGradientColors(for scheme: ColorScheme) -> [UIColor] {
    if scheme == .dark {
        return [UIColor.black.withAlphaComponent(0.42),
                UIColor.black.withAlphaComponent(0.18),
                UIColor.black.withAlphaComponent(0.50)]
    }
    return [UIColor.white.withAlphaComponent(0.18),
            UIColor.white.withAlphaComponent(0.04),
            UIColor.white.withAlphaComponent(0.24)]
}
```

### 4. `MemoryPalace/Views/ChatWallpaperBackdrop.swift` — 删除

整个文件（iOS-only）可以删除。确认引用：
- grep 确认只有 iOSChatPage 曾经用过（d9b9b3f 已 revert 删引用）
- macOS 背景走 `ThemeBackgroundView`（`ContentView.swift:152`），不关 ChatWallpaperBackdrop 事

删除文件 + 删除探针代码（之前 9850905 加的 `[PROBE bg]` SwiftUI 层探针随 file 一起走）。

### 5. `PagingViewController.swift` — 撤旧探针 + 加新探针

撤 A6 的 `viewDidLayoutSubviews` 探针（SwiftUI 层追踪已无意义，UIKit 层探针更精准）。
加新 UIKit 层探针：
```swift
#if DEBUG
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // ... wallpaper + scrollView layout ...
    print("[PROBE bg uikit] PagingVC.viewDidLayoutSubviews view.bounds=\(view.bounds) wallpaper=\(wallpaperContainer.frame)")
}

// 加键盘通知监听仅做 log，不改任何 state
override func viewDidLoad() {
    super.viewDidLoad()
    // ... 原 setup ...
    NotificationCenter.default.addObserver(
        self, selector: #selector(logKeyboardEvent(_:)),
        name: UIResponder.keyboardWillShowNotification, object: nil)
    NotificationCenter.default.addObserver(
        self, selector: #selector(logKeyboardEvent(_:)),
        name: UIResponder.keyboardWillHideNotification, object: nil)
}

@objc private func logKeyboardEvent(_ notif: Notification) {
    print("[PROBE bg uikit] \(notif.name.rawValue) → view.bounds=\(view.bounds) wallpaper=\(wallpaperContainer.frame)")
}
#endif
```

## Checklist

- [ ] 1. 新建 `WallpaperConfig` struct（放 PagingViewController.swift 或独立文件）
- [ ] 2. PagingViewController：加 wallpaperContainer / wallpaperImageView / wallpaperGradientLayer 属性
- [ ] 3. viewDidLoad 里挂 wallpaperContainer 到 `view.insertSubview(_, at: 0)`
- [ ] 4. viewDidLayoutSubviews 同步 wallpaperContainer / imageView / gradientLayer 的 frame
- [ ] 5. `applyWallpaper(_:)` 方法：fill / image + saturation / alpha / offset / gradient
- [ ] 6. `applySaturation` 私有方法（CIFilter + sharedCIContext）
- [ ] 7. PagingContainerView：加 `wallpaper: WallpaperConfig` 参数 + `updateUIViewController` 调 `applyWallpaper`
- [ ] 8. ContentView.iOSLayout：撤 `.background`，构造 WallpaperConfig 传入；加 `wallpaperGradientColors(for:)` helper
- [ ] 9. **删除** `ChatWallpaperBackdrop.swift`（不再引用）
- [ ] 10. 撤 PagingViewController 原 `[PROBE bg]` 探针，加新 UIKit 层探针（viewDidLayoutSubviews + keyboard notification）
- [ ] 11. build iOS 通过
- [ ] 12. build macOS 通过（ChatWallpaperBackdrop 删除不影响 macOS，确认）
- [ ] 13. commit + push
- [ ] 14. 粟粟真机验证：
  - 壁纸视觉与 master 一致（fill + image scaleAspectFill + gradient）
  - 翻页不延迟
  - 键盘弹起壁纸不动
  - `[PROBE bg uikit]` log 键盘事件时 wallpaperContainer.frame 不变

## 风险 / 已知未决

- ⚠️ **Saturation 视觉一致性**：SwiftUI `.saturation(0.92)` 和 CIFilter colorControls saturation=0.92 的实现算法可能有微小色彩差异。如果粟粟视觉挑剔出差异，调整 filter 参数
- ⚠️ **Image 一次性 load 大图**：无 crop 的原图直接 decode + CIFilter，峰值 30-50MB 内存。壁纸不常换，可接受。后续 Step 2（手动 crop UI）会降到合理大小
- ⚠️ **offset 语义**：SwiftUI `.offset` 是 SwiftUI view 层的 translation；UIKit `transform` translate 是 UIView 层——本应等价，但如果粟粟发现 offset 对不准，换用 `CGAffineTransform(translationX:, y:)` 之前 `bounds.origin` 或者 `imageView.frame` 调整
- ⚠️ **硬切换壁纸**：换主题或换图瞬间无过渡。想要过渡可后加 UIView.transition cross-fade。第一版不做

## 文件改动总览

| 文件 | 改动 |
|---|---|
| `Views/Paging/PagingViewController.swift` | +~80 行（wallpaper setup/apply + probes）-~5 行（旧探针） |
| `Views/Paging/PagingContainerView.swift` | +~5 行（wallpaper 参数） |
| `Views/ContentView.swift` | 改 iOSLayout ~30 行 |
| `Views/ChatWallpaperBackdrop.swift` | **删除** 整个文件 |

净增：~100 行。

## 等待粟粟批注

粟粟直接在此 plan 文件加 `⬅ 粟粟意见：...` 批注。没意见回 "go" 我开 A13 implement。
