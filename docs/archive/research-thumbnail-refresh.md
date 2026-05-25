# Research: Gallery 缩略图刷新

## 问题

修改描边/滤镜后，`updateStyle` 重新渲染 PNG 并保存到磁盘，StickerAsset 的 `imagePath`/`thumbnailPath` 也更新了。但 Gallery 里的 `StickerThumbnailView` 显示的还是旧图——因为 `@State private var thumbnailImage: Image?` 已经缓存了旧图，不会重新加载。

## 现状

```swift
struct StickerThumbnailView: View {
    let asset: StickerAsset
    @State private var thumbnailImage: Image?
    
    .onAppear { loadThumbnail() }
    
    private func loadThumbnail() {
        guard thumbnailImage == nil else { return }  // ← 有缓存就不重新加载
        ...
    }
}
```

`guard thumbnailImage == nil` 导致一旦加载过就永远不会刷新。

## 方案

### 方案 A：监听 asset 变化重新加载
用 `.onChange(of: asset.thumbnailPath)` 检测路径变化时清空缓存重新加载。

但 `asset` 是 SwiftData @Model，`thumbnailPath` 是属性。onChange 能不能监听 @Model 的属性变化？可以——SwiftData 模型属性变化会触发 SwiftUI 更新。

### 方案 B：用 asset.thumbnailPath 作为缓存 key
```swift
.task(id: asset.thumbnailPath) {
    loadThumbnail()
}
```
每次 thumbnailPath 变化（包括 updateStyle 后），自动重新加载。

**推荐方案 B** — 最简单，一行改动。

## 描边预览

描边预览已经在 StickerStyleSheet 里实现了（上一个 commit）。Sheet 里切换选项会实时渲染预览图。这个已经做完了。

唯一的问题：预览用的是原图渲染，可能有点慢（大图）。可以先用缩略图渲染加速。但这是优化，不是 bug。
