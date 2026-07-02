# 反转列表回滚记录（2026-07-02 深夜）

Phase 1-5 已整体回滚（CardFlowView + StickerCanvasLayer 恢复到 0007f35 版本）。
回滚原因：真机发现三个显示回归，均与双翻转（ScrollView 翻 + cell 翻回正）相关：

1. **编辑模式上下颠倒**：长按 user 消息 → 编辑，inline TextEditor 渲染成镜像。
   疑因：UIKit-backed view（UITextView）在双 transform 层级下只吃到一层翻转。
2. **长按菜单预览错位**：contextMenu lift preview 出现在错误位置/被裁切，
   dismiss 后在列表里留下镜像残影（UITargetedPreview 与 transform 打架，
   liftPreview() 纯文本替代方案不足以解决锚定问题）。
3. **思考链 UI 消失**：流式思考块不再显示（代码完好，疑似渲染位置被翻出可视区，
   待重做时真机验证根因）。

## 重做建议（Round 2）
- 放弃翻转戏法，改用 iOS 17+ 原生 `defaultScrollAnchor(.bottom)` +
  `scrollTargetLayout()`，无 transform、无兼容雷。
- 若必须保留翻转方案：所有 UIViewRepresentable（TextEditor/WebView）、
  contextMenu、编辑态需逐一真机验证。
- 重做前先在真机验证：长按菜单、编辑、思考链、贴纸拖拽四件套。
