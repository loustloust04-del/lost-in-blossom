# 任务：UI 第二轮修复

天奕真机测试反馈。按优先级排序。

## 1. 思考链适配（最高优先级）

DeepSeek 思考模型（deepseek-reasoner）的思考内容放在 `delta["reasoning_content"]` 字段里，ChatService 目前只处理 `delta["content"]`，思考链被丢弃了。

**修复：** 在 ChatService 的 SSE 流式解析中（约第344行附近），增加对 `reasoning_content` 的处理：
- 检测 `delta["reasoning_content"]`
- 将其累积到一个 `streamingThinking` buffer
- 流式结束时，将 thinking 内容包装成 `MessageSegment.thinking(text:signature:)` 
- 或者更简单：将 reasoning_content 用 `[thinking]...[/thinking]` 标记包裹后拼到 content 前面，复用现有的 segment 解析逻辑

现有的 MessageSegment 已有 `.thinking` 类型，MessageSegmentsView 已有 DisclosureGroup 折叠 UI。只需要在数据层把 DeepSeek 的 reasoning_content 喂进去。

## 2. 删除气泡底部功能键行

每条消息气泡下面有一行小按钮（编辑✏️、复制📋、收藏⭐、钉住📌、删除🗑️）。

**天奕要求：** 删掉这一行。只保留长按消息弹出的 context menu（编辑、收藏、收藏到文件夹、钉住、复制文本、删除）。

在 CardFlowView.swift 或消息气泡组件中找到这行 HStack，用 `#if os(macOS)` 包裹或直接删除 iOS 端的显示。

## 3. + 号面板改为 Bottom Sheet

现在 + 号点击后是添加便签功能。改为 Claude App 风格的功能面板。

**实现：**
```swift
.sheet(isPresented: $showAddPanel) {
    AddToChatPanel()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

AddToChatPanel 内容：
- 📎 添加文件/照片（占位，功能待做）
- 🤖 选择模型（导航到模型选择）
- ⚙️ 设置（导航到设置页）
- 📝 导入聊天记录（导航到 ImportView）

## 4. 全局动画

参照 docs/task-ui-polish.md 中的动画规格：
- 侧边栏：spring 弹出 + 背景遮罩渐变
- 消息气泡：淡入 + 上移
- 面板：系统 sheet 自带
- 状态切换：withAnimation 包裹

## 5. 删除 macOS target

在 project.yml 中删除 `MemoryPalace`（macOS target），只保留 `MemoryPalaceIOS`。

---

每项改完 commit 一次。小步前进。
