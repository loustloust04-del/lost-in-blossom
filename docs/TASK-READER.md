# 任务：基础阅读器搬运

> 参考：`/root/projects/SusuPalace` origin/master
> 目标：能导入 txt/pdf → 书架展示 → 点击阅读 → 翻章 → 进度保存
> 预计文件数：12 个新文件 + 3 个改动
> 共读系统后续单独做，本次只做"能看书"

---

## 从粟粟复制的文件

```bash
cd /root/projects/SusuPalace && git checkout origin/master

# 1. Model
cp MemoryPalace/Models/BookEntry.swift \
   /root/projects/BunnyPalace/MemoryPalace/Models/

# 2. Service
cp MemoryPalace/Services/BookStore.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/

# 3. Views
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Views/Reading
cp MemoryPalace/Views/Reading/ReadingPanelView.swift \
   MemoryPalace/Views/Reading/BookshelfView.swift \
   MemoryPalace/Views/Reading/BookReaderSheet.swift \
   MemoryPalace/Views/Reading/BookReaderWebView.swift \
   MemoryPalace/Views/Reading/PDFReaderSheet.swift \
   MemoryPalace/Views/Reading/NoteQuickLookSheet.swift \
   /root/projects/BunnyPalace/MemoryPalace/Views/Reading/

# 4. JS 脚本（WebView 渲染用）
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Resources/ReaderScripts
cp MemoryPalace/Resources/ReaderScripts/extract.js \
   MemoryPalace/Resources/ReaderScripts/readability.min.js \
   MemoryPalace/Resources/ReaderScripts/turndown.min.js \
   /root/projects/BunnyPalace/MemoryPalace/Resources/ReaderScripts/
```

**暂不复制的文件**（共读 phase 用）：
- BookAnnotationDrawer（批注）
- BookChatDrawer（问 AI 抽屉）
- ReadingSignals（在场心跳）

---

## 接线步骤

### 1. BookEntry 加入 SwiftData schema

在 `MemoryPalaceApp.swift` 的 ModelContainer schema 数组里加 `BookEntry.self`：
```bash
grep -n "Schema\|modelContainer\|BookEntry" /root/projects/BunnyPalace/MemoryPalace/MemoryPalaceApp.swift | head -10
```
找到 schema 数组，确认包含 `BookEntry.self`。

### 2. 接入 Page 2 dock

在 `RightPanelPlugin.swift` 的 `builtInTools` 加：
```swift
RightPanelTool(id: "reading", name: "读书", icon: "book.fill", order: 9),
```

在 `MemoryPanelView.swift` 的 `panelContent` switch 加：
```swift
case "reading":
    ReadingPanelView()
```

### 3. project.yml 确认资源引用

确保 `MemoryPalace/Resources/ReaderScripts/` 被包含在 build resources 里：
```bash
grep -n "resources\|Resources" /root/projects/BunnyPalace/project.yml | head -10
```
如果 resources 用 glob（`MemoryPalace/Resources/**`），不用改。

### 4. 精简 BookReaderSheet（去掉共读依赖）

BookReaderSheet 1201 行，里面有批注（M3）和问 AI（M3-B）的代码。搬过来后需要注释或删除这些部分：

搜索并注释掉：
```
BookAnnotationDrawer   → 批注抽屉相关代码
BookChatDrawer         → 问 AI 抽屉
showChatDrawer         → 问 AI 开关
ReadingSignals         → 在场信号上报
askToast               → 问 AI 反馈
```

最简做法：
- 搜所有 `BookAnnotationDrawer`、`BookChatDrawer`、`ReadingSignals` 引用，注释掉
- 搜 `showChatDrawer`、`showAnnotation` 相关 @State 和 View，注释掉
- 保留核心：toolbar + WebView + 章节切换 + 进度保存

### 5. 精简 PDFReaderSheet（同理）

PDFReaderSheet 1125 行也有批注/问 AI 代码，同样注释掉 `Annotation`/`ChatDrawer` 相关部分。

### 6. BookStore 适配

`BookStore.swift` 321 行，核心是：
- `importBook(from:profileId:context:)` — 导入 txt/pdf
- `refreshEntries(profileId:context:)` — 扫描文件夹同步索引
- `loadChapterContent(bookSafeName:chapter:profileId:)` — 加载章节
- `splitChapters(text:)` — txt 切章逻辑

检查它依赖的 `FileLibraryStore` 函数我们有没有。关键是：
```bash
grep "FileLibraryStore\." /root/projects/SusuPalace/MemoryPalace/Services/BookStore.swift | head -10
```
对照我们的 FileLibraryStore，缺什么补什么。

### 7. macOS 条件编译

所有文件里的 `#if os(macOS)` 块可以直接删掉，我们只要 iOS。

---

## 验证清单

1. [ ] 编译通过
2. [ ] Page 2 dock 出现 📖「读书」图标
3. [ ] 点进去看到空书架 + "导入书"按钮
4. [ ] 导入 .txt 文件 → 自动切章 → 书架出现封面卡片
5. [ ] 点击书卡 → 全屏阅读器打开 → 能翻章
6. [ ] 退出阅读器 → 再进来 → 进度恢复到上次位置
7. [ ] 导入 .pdf → PDF 阅读器打开 → 能翻页

---

## 注意事项

1. **不要碰 CLAUDE.md**
2. 共读相关代码（批注/问AI/在场信号）全部注释掉，后续单独搬
3. BookEntry 是新 SwiftData model，旧数据自动无影响（空表）
4. macOS 代码全删
5. commit message：`feat(reader): ...`
6. 先确保 BookshelfView 编译通过再搬 ReaderSheet
