# 记忆宫殿 (Memory Palace)

macOS 原生 ChatGPT 对话浏览器。1,733 条对话、205,981 个节点，保留完整树状分支。

## 构建

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
xcodegen generate && xcodebuild -scheme MemoryPalace build
```

需要先安装 xcodegen（`brew install xcodegen`）。项目配置在 `project.yml`，`.xcodeproj` 由 xcodegen 生成（已 gitignore），不要手动编辑。

## 技术栈

- SwiftUI + SwiftData, macOS 14+ (Sonoma/Sequoia/Tahoe)
- Swift 5.10, Xcode 16+
- MarkdownUI v2.4.1（assistant 气泡 Markdown 渲染）
- Bundle ID: `com.susu.MemoryPalace`，产品名: `记忆宫殿`

## 文件结构

```
MemoryPalace/
├── project.yml                           # xcodegen 配置
├── MemoryPalace/
│   ├── MemoryPalaceApp.swift             # App 入口, ModelContainer, WindowConfigurator
│   ├── Models/
│   │   ├── Conversation.swift            # Conversation, MessageNode, UserCard
│   │   └── Folder.swift                  # Folder, FavoriteItem
│   ├── ViewModels/
│   │   └── ConversationViewModel.swift   # 树遍历、分支冒泡、路径构建（后台线程加载）
│   ├── Views/
│   │   ├── ContentView.swift             # NavigationSplitView 主框架
│   │   ├── SidebarView.swift             # 侧边栏：搜索、文件夹、对话列表
│   │   ├── CardFlowView.swift            # 气泡对话流、分支选择器、hover 按钮
│   │   ├── ImportView.swift              # JSON 导入界面
│   │   ├── SettingsView.swift            # 设置页 + 批量导出
│   │   └── ExportOptionsSheet.swift      # 导出选项弹窗
│   ├── Services/
│   │   ├── ConversationImporter.swift    # JSON 解析+批量导入
│   │   └── MarkdownExporter.swift        # 对话导出为 Markdown
│   └── Utils/
│       ├── Theme.swift                   # 配色常量（暖奶白+浅灰薄荷）
│       ├── MarkdownTheme.swift           # MarkdownUI 自定义主题
│       ├── FontManager.swift             # 字体管理
│       └── ContentCleaner.swift          # ChatGPT 引用/实体标记清理
```

## 数据模型 (SwiftData)

| Model | 文件 | 关键字段 |
|-------|------|----------|
| `Conversation` | Conversation.swift | id, title, createTime, updateTime, currentNodeId, folderId, nodeCount, isDeleted, deletedAt, lastOpenedAt |
| `MessageNode` | Conversation.swift | id, role, content, parentId, childrenIds, conversationId, isFavorite, isDeleted, deletedAt — `@Attribute(.unique) var id` |
| `UserCard` | Conversation.swift | id, content, imageData, attachedToNodeId, positionX, positionY |
| `Folder` | Folder.swift | id, name, emoji, order |
| `FavoriteItem` | Folder.swift | id, nodeId, conversationId, folderId, contentPreview |

**数据规模**: 20 万+ MessageNode。任何 FetchDescriptor 都必须考虑这个量级，绝对不要无 predicate 全量 fetch MessageNode。

## 关键架构

### 树遍历 (ConversationViewModel)
- 从 root（parentId==nil）沿 children 向下走，遇到分支按 branchChoices 或 mainPath 选择
- **分支冒泡**: 不可见节点（system/tool）的分支信息冒泡到上一个可见节点（`bubbledBranches` 字典）
- **effectiveChildrenMap**: 从 parentId 反向重建父子关系，修复分支对话中 childrenIds 不完整的问题
- **chaseMissingAncestors**: 按缺失 ID 逐个查询补齐分支对话缺失的祖先节点
- **后台线程加载**: fetch + 树构建在后台线程完成（独立 ModelContext + 纯值类型 NodeInfo），主线程只做快速 re-fetch 和赋值
- **软删除不断链**: nodeMap 加载全量节点（含已删除），rebuildPath 遍历时穿过已删除节点但不显示

### Markdown 导出 (MarkdownExporter)
支持四种模式：longest（最长分支）、current（当前路径）、mainPath（主路径）、fullTree（全部分支用 `<details>` 折叠）。树深度计算用迭代后序遍历，避免递归栈溢出。

### ContentCleaner
ChatGPT 导出的文本含 Unicode PUA 字符（U+E200-E206）做内联标注。ContentCleaner 提取实体名、去除引用块、清理乱码。结果用 NSCache 缓存（cacheKey 必须传 node.id，不要传 nil）。

### 配色 (Theme)
暖奶白 `#FFFBF6` 为主，浅灰薄荷 `#E7EEEC` 为辅，深棕色文字。**不要蓝色、不要黄色**。

## 已完成功能

JSON 导入、对话列表（分页 100/页）、ChatGPT 风格气泡、树状分支浏览（分支冒泡）、收藏/软删除、回收站（恢复+永久删除）、文件夹系统（emoji+名称）、右键菜单、hover 按钮（opacity 控制不改变布局）、对话重命名、Markdown 渲染（MarkdownUI）、引用标记清理、对话导出 Markdown、搜索（标题+内容）、最近打开排序。

## 性能状况

详见 `性能体检报告.md`，摘要：

| # | 问题 | 状态 |
|---|------|------|
| P0-1 | chaseMissingAncestors 全量 fetch | ✅ 已修复（按 ID 逐个查询） |
| P0-2 | performSearch cacheKey=nil | ✅ 已修复（改为 node.id） |
| P0-2 | 搜索全表扫描 20 万节点 | ⏸ 搁置（需搜索索引/异步搜索） |
| P1-3 | performLoad 阻塞主线程 | ✅ 已修复（后台线程 fetch + 树计算） |
| P1-4 | 收藏/回收站 N+1 查询 | ✅ 已修复（批量 fetch titleMap） |
| P2-5 | 文件夹全量 fetch 再内存过滤 | ✅ 已修复（加 isDeleted predicate） |
| P2-6 | 批量导出共享 ancestor lookup | ⏸ 搁置 |

## 开发规则

### UI 变动
- 用户对 UI 变动敏感，**宁可小步迭代，不要一次改太多**
- 做 UI 修改前先描述要改什么，等确认再动手
- 不要用 debug 样式（亮色边框、红色背景）除非明确要求
- hover 按钮用 `.opacity()` 控制显隐，不要用 `if` 条件渲染（防止布局抖动）

### 调试
- 遇到视觉 bug，先排查是不是样式/可见度问题（颜色太浅看不出来），再查逻辑
- sidebar 数据变更后不会自动刷新，需要手动触发（sidebarRefreshTrigger 或 @FetchRequest 重新求值）

### 性能
- 20 万+ MessageNode，任何查询都要加 predicate，**禁止 `FetchDescriptor<MessageNode>()` 无条件全量 fetch**
- ContentCleaner.clean() 的 cacheKey 必须传 node.id
- 搜索结果不要加 fetchLimit 截断（用户需要完整结果）

### 代码习惯
- 修改代码前先读文件，改坏了要能立刻回退
- NSWindow titlebar 已设为透明（WindowConfigurator），不要再动标题栏相关配置
- 每次 git commit 后 push 到 GitHub
- 用户名叫 Susu，AI 叫"小雾"，用户气泡标签是"你"
- 界面全中文

## 数据位置

- **源码**: `/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/`
- **ChatGPT 导出**: `/Users/susu/Desktop/susu-project/OpenAI-export/`
- **SwiftData 数据库**: `~/Library/Application Support/default.store`
- **GitHub**: `git@github.com:replica882/MemoryPalace.git` (private)

## 待办

### Bug / 体验
- 全屏时顶部白框未解决
- 搜索排序对标题搜索不成立
- 滚动条太粗

### 功能
- 日历视图（按时间轴浏览对话）
- 对话统计/词频（可放日历视图里）
- 皮肤/主题切换
- 图片支持（匹配 ChatGPT 导出图片 → node）
- 无限画布 / 手写卡片（远期）
- iOS 版本（远期）

### 性能（搁置）
- ⏸ 搜索全表扫描优化（需建搜索索引或后台异步搜索）
- ⏸ 批量导出共享 ancestor lookup（当前逐条够用）
