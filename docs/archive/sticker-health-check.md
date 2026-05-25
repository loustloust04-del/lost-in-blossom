# 贴纸模块健康检查

> 2026-04-15 · feature/sticker-system 分支合并前审查

## 边界情况

### 需要关注（P1）

| 问题 | 文件 | 说明 | 状态 |
|------|------|------|------|
| 图片无缓存 | StickerView.swift | 每个 StickerView 独立加载全尺寸图片，100 张 = 100 次磁盘 IO + 内存。iOS 会被系统杀 | ✅ NSCache 200 张 / 50MB |
| undo 栈不清理已删贴纸 | StickerViewModel | 删除贴纸后 undo 栈还持有快照，撤回会恢复幽灵贴纸 | ✅ removePlacedSticker 时 filter |
| conversationId 无索引 | PlacedSticker.swift | 每次打开对话全表扫描贴纸，数据量大了会卡 | ⬜ 后续 |
| zIndex 无界增长 | StickerViewModel | 反复"置于最前/最后"让 zIndex 往正负无穷漂移 | ⬜ 后续 |
| 缩略图失败回退全图 | StickerFileManager | thumbnail 生成失败用原图充当缩略图，panel 加载大量全尺寸图 | ⬜ 后续 |
| copiedSnapshot 跨 profile | StickerViewModel | 复制贴纸后切楼层，粘贴用旧 profile 的 assetId | ⬜ 后续 |

### 可接受（P2）

| 问题 | 文件 | 说明 |
|------|------|------|
| 贴纸拖到画布边缘外无回弹 | StickerGestureOverlay | 贴纸可以拖到 (10000, 10000)，没有 bounds 检查 |
| 便签文字无长度限制 | StickerAsset | 用户可以粘贴 1MB 文本，SwiftUI Text 渲染会卡 |
| 文件写入中途失败无清理 | StickerFileManager | 原图写成功 + 缩略图失败 = 磁盘孤儿文件 |
| `try? context.save()` 静默吞错 | 全模块 | 所有 save 调用都用 try?，失败时 UI 和 DB 状态不一致 |
| 图片加载失败永久占位 | StickerView | loadImage 返回 nil 时占位符永远不消失，无重试 |
| context menu 闭包捕获 sticker 对象 | StickerGestureOverlay | 菜单弹出后如果贴纸被删，闭包引用的 sticker 可能已失效 |

## 与其他模块的交互

| 模块 | 交互点 | 风险 |
|------|--------|------|
| Profile 系统 | 贴纸绑 profileId，切楼层需 reload | 目前没监听 profile 变化，但 CardFlowView 已在切换时重建 |
| PromptAssembler | 无直接交互 | 低 |
| 搜索 | SearchService.searchStickers() | 已集成，正常工作 |
| 导入/导出 | 贴纸资产文件在 profileId 目录下 | 导出 profile 时需要包含贴纸文件夹 |

## 技术债务

### 合并前必须修（本次）

1. ~~**图片缓存**~~ ✅ `StickerFileManager.loadImageCached()` — NSCache 200 张 / 50MB，StickerView + PanelStickerCell + LibraryView + StyleSheet 共用
2. ~~**undo 栈清理**~~ ✅ `removePlacedSticker()` 时 filter 掉对应 stickerId 的快照，`deleteAsset()` 时清除图片缓存

### 稳定性打磨轮次（后续）

- conversationId 加 SwiftData 索引
- zIndex 归一化（定期重排为 0, 1, 2, ...）
- save() 错误处理统一（至少加 print 日志）
- StickerFileManager 写入失败回滚
- 便签文字长度限制（500 字符）
