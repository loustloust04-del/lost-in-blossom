# Plan: 画画便签（磁性画板）

---

- [ ] **1** 新建 `Views/DrawingBoardSheet.swift`：
  - SwiftUI Canvas + DragGesture 画笔
  - Line 数据结构（points, color, lineWidth, isEraser）
  - 磁性画板配色：浅灰绿背景 + 深灰笔触
  - 底部工具栏：颜色选择（5 色）/ 笔粗（3 档）/ 橡皮擦 / 清除
  - "清除"动画（模拟拉杆擦除）

- [ ] **2** 导出功能：画完 → ImageRenderer 导出透明 PNG → 命名 → 存为 StickerAsset

- [ ] **3** StickerToolbar "画画"按钮从 alert 改为弹 DrawingBoardSheet

- [ ] **4** StickerLibraryView "新建便签"旁加"画一张"按钮（也弹 DrawingBoardSheet）

- [ ] **5** Build + commit push
