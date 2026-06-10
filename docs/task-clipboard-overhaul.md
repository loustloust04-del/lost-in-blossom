# 剪贴板大改：文件粘贴 + 导入功能全面修复

> 2026-06-03 · Caelum 梳理 · 给猫的任务文档
> 优先级：P0 — 这是 App 的核心功能

---

## 问题全景

ESign 签名的 App 里 UIDocumentPickerViewController 完全不能选文件（能浏览但点击无反应）。
这影响两个入口：

1. **聊天附件**（AddToChatSheet → 粘贴文件）：粘贴能拿到数据，但模型读不到
2. **导入聊天记录**（ImportView → 选择 JSON 文件）：完全不能用，需要改成剪贴板

---

## 第一部分：聊天附件 — 粘贴文件后模型读不到

### 根因分析

**问题 A：MIME 类型检测太粗糙**

AddToChatSheet.swift 从剪贴板读 pb.types.first，这返回的是 UTI（如 com.adobe.pdf、public.json），但文件名推断只做了简单的 contains("pdf") 子串匹配。很多 UTI 匹配不到。

**问题 B：OpenAI/DeepSeek 路径丢弃 document 块**

ChatService.swift OpenAI 流式发送遍历 content blocks 时只处理 type:"image" 和 type:"text"。如果 block 的 type 是 "document"，直接被跳过，模型完全看不到文件内容。

**问题 C：Claude 路径的 MIME 类型不对**

ConversationViewModel.swift 非图片非 PDF 文件的 MIME 被设为 application/octet-stream。Claude API 的 document block 不支持这个 MIME 类型。

**问题 D：文本文件不应该走 document block**

JSON、TXT、MD、CSV 这类文本文件，应该直接读成 UTF-8 字符串，嵌入消息文本里。不需要 base64 编码。这样所有模型都能读。

### 修复方案

#### Step 1：改进 AddToChatSheet 的剪贴板读取

文件：MemoryPalace/Views/AddToChatSheet.swift

替换现有的粘贴文件 Button action：加 UTI→扩展名映射表，遍历 pb.types 找到第一个已知类型，fallback 从 UTI 最后一段猜扩展名。

UTI 映射表：
- com.adobe.pdf → pdf
- public.json → json
- public.plain-text / public.utf8-plain-text / public.text → txt
- public.html → html
- public.xml → xml
- public.comma-separated-values-text → csv
- public.png → png
- public.jpeg → jpg
- com.compuserve.gif → gif
- public.webp → webp

#### Step 2：sendMessage 里区分文本文件和二进制文件

文件：MemoryPalace/ViewModels/ConversationViewModel.swift

替换 sendMessage 函数中 else if let data = fileData 分支，按扩展名分四条路：

1. 图片扩展名（jpg/jpeg/png/gif/webp/heic）→ image block（保持现有逻辑）
2. 文本扩展名（json/txt/md/csv/html/xml/swift/py/js/ts/yaml/yml/toml/log/sh/css）→ 读成 UTF-8 字符串，嵌入消息文本，用代码块包裹。截断保护：超 100K 字符只取前 100K
3. PDF → document block（MIME 用 application/pdf）
4. 未知 → 尝试当 UTF-8 文本读，失败则返回错误提示

关键：文本文件返回 contentType = "text" 而非 "multimodal_text"，这样所有模型都能读。

#### Step 3：OpenAI 路径处理 document block（兜底）

文件：MemoryPalace/Services/ChatService.swift

在 OpenAI 流式发送的 for block in blocks 循环里，给 type == "document" 加一个分支，输出 "[附件: xxx — OpenAI 不支持 document 类型，请使用 Claude 模型]"。

---

## 第二部分：导入聊天记录 — 改用剪贴板

### 修改 ImportView.swift

1. 把 Button("选择文件...") { presentFilePicker() } 改成 Button("从 Files 粘贴 JSON") { pasteAndImport() }
2. 加操作说明 Text："打开 Files App → 长按 conversations.json → 拷贝 → 回到这里点按钮"
3. 新增 pasteAndImport() 函数：
   - 尝试从 pb.data(forPasteboardType:) 读取，依次试 public.json / public.plain-text / public.utf8-plain-text / public.text
   - fallback 用 pb.string
   - 验证是否为有效 JSON（JSONSerialization.jsonObject）
   - 写入临时文件 → 调用现有的 startImport(url:)
   - 错误处理：剪贴板没数据 / 不是有效 JSON / 写入失败
4. 删除所有 showFilePicker / .fileImporter / presentFilePicker() 相关代码

---

## 修改文件清单

| 文件 | 改动 |
|------|------|
| MemoryPalace/Views/AddToChatSheet.swift | 改进 UTI→扩展名检测 |
| MemoryPalace/ViewModels/ConversationViewModel.swift | sendMessage 区分文本/图片/PDF/未知 |
| MemoryPalace/Services/ChatService.swift | OpenAI 路径兜底 document block |
| MemoryPalace/Views/ImportView.swift | 文件选择器 → 剪贴板粘贴 |

## 执行顺序

1. 先改 ConversationViewModel（Step 2）— 核心修复
2. 再改 ChatService（Step 3）— OpenAI 兜底
3. 改 AddToChatSheet（Step 1）— 粘贴检测
4. 改 ImportView（第二部分）— 导入功能
5. 每步一个 commit，编译通过再做下一步
