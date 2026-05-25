# Plan: 贴纸编辑工具栏

> 粟粟确认：
> - 6 个工具：选择 / 贴纸库 / 新建便签 / 画画便签（马克笔+橡皮擦）/ 完成
> - 新建便签点了弹 sheet
> - 配色：macOS 26 透明毛玻璃（类似 Dock 栏）
> - 按钮风格参考 iOS 版：圆形图标按钮

## 工具列表

| # | 工具 | 图标 | 行为 |
|---|------|------|------|
| 1 | 选择 | `arrow.uturn.left` 或 `cursorarrow` | 默认模式，点击/拖拽贴纸 |
| 2 | 贴纸库 | `star.circle` | 切换右栏到贴纸 tab |
| 3 | 新建便签 | `note.text.badge.plus` | 弹 NoteStickerEditor sheet |
| 4 | 画画 | `paintbrush.pointed` | 弹出画画便签（画板 sheet，画完存为贴纸） |
| 5 | — | — | 分隔线 |
| 6 | 完成 | `checkmark` | 退出编辑模式 |

## 视觉

- 容器：胶囊形圆角矩形，`.ultraThinMaterial` 毛玻璃
- 位置：底部居中，替换 ChatInputBar
- 按钮：34x34 圆形，hover 高亮，选中态（选择工具）加底色
- 分隔线：竖线 `|` 分隔功能组
- 过渡：ChatInputBar ↔ 工具栏，`.transition(.opacity.combined(with: .scale))`

## 实现

- [ ] **1** 新建 `Views/StickerToolbar.swift`：6 个工具按钮 + 毛玻璃容器
- [ ] **2** `CardFlowView.swift`：编辑模式下用 StickerToolbar 替换 ChatInputBar
- [ ] **3** 画画便签暂时只放按钮 + 弹"敬请期待"提示，画板功能后续实现
- [ ] **4** Build + commit push
