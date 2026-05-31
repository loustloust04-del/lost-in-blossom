# Lost in Blossom v0.2 更新日志

## 🌸 CC Bridge — 在 App 里直接跟 Claude Code 对话

从零搭建了完整的 CC Bridge 系统。iPhone 上打开 Lost in Blossom，直接跟 VPS 上的 Claude Code 对话。不受任何平台审查，不会被封窗口。

- 采用粟粟验证过的 WebSocket 方案（感谢粟粟！）
- Ping 心跳保活、reply 去重、自动重连
- 设置页可自定义 Hub URL
- `--resume` session 保上下文

## 📸 图片 & 文件发送

- 图片发送到 API ✅（base64 编码，自动压缩）
- 文件选择器修复 — SwiftUI 的 `.fileImporter` 在 iPhone 上有 bug，换成了 UIKit 的 `UIDocumentPickerViewController`
- "发送 PDF" → "发送文件"，支持所有文件类型

## 📋 双击选取文本

双击消息气泡弹出文本选取视图，可以自由拖拽选区、部分复制。思考链内容也能选取。

## 💭 思考链 UI 改版

思考链弹窗对齐 Claude iOS 官方风格 — 标题居中，关闭按钮左上角。

## 📳 双模式震动反馈

两种风格，设置里切换：
- **打字机模式（ChatGPT 风格）**：AI 回复时随文字轻震，完成时提示震动
- **精简模式（Claude 风格）**：仅在发送、复制、删除等操作时反馈

## 🖼️ 模型兼容

切换到不支持图片的模型时，自动过滤历史消息中的图片，对话不再卡死。

## 🚀 自动部署

GitHub Actions 编译完 → ipa 自动 SCP 到 VPS → 直接下载安装。再也不用手动下载 artifact 了。

## 🔧 编译优化

- docs 和 .md 文件的 push 不再触发编译，节省 runner 额度
- 任务队列系统（TASK-QUEUE.md）— 一条指令批量喂猫

---

*Lost in Blossom v0.2 · 2026年6月1日 · 儿童节*
*Built by Bunny & Caelum · 花丛中迷失，但我们找到了彼此*
