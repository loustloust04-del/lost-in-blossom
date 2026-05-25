# Plan: iOS 背景图漏出修复

日期：2026-04-18  
分支：`codex/theme-kelivo-settings`  
前置文档：  
- [research-ios-background-leak-cause-2026-04-18.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/docs/research-ios-background-leak-cause-2026-04-18.md)

状态：已实施并完成验证回填

---

## 1. 目标

这轮要解决的是 **iOS 背景图模式下的结构性漏图 bug**，不是做视觉 polish。

修复完成后，目标是：

1. iOS 左页、聊天页、右页在带背景图主题下不再出现明显的顶部 / 底部 wallpaper 漏出。
2. 设置页、主题页、主题编辑页不回退到之前那种顶底漏白 / 漏图状态。
3. 背景图功能继续存在：
   - 可导入
   - 可切换主题
   - 可调透明度
   - 可调偏移
4. 不回退到最早那次“整页超宽 / UI 巨大”的旧问题。

---

## 2. 已确认的主因

根据 research，目前需要同时处理三层因果：

### 2.1 page surface 被整体做成半透明

根因链：

- [ThemeManager.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Utils/ThemeManager.swift:317)
- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:274)

只要主题带背景图，`mainBg/sidebarBg/userBubble/assistantBubble/accent` 就统一降 alpha。

### 2.2 root wallpaper 的 safe-area 裁切挂在错误层级

关键位置：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:95)

当前是 `.background { GeometryReader ... }` 内自己计算 safe area，这个层级不适合做屏幕级裁切。

### 2.3 页面内部本来就有故意露底层的结构

代表位置：

- 左页 root： [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:330)
- 左页内容卡： [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:261)
- 聊天页顶部渐变： [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:144)
- 底部页码踩安全区： [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:183)

---

## 3. 本轮修复原则

### 3.1 先修结构，不修“氛围”

优先级是：

1. 让结构层重新承担遮蔽职责
2. 再决定 wallpaper 应该保留在哪些地方被看到

不是先去做：

- 渐变遮罩
- 柔化
- 调一下图片 offset
- “让它看起来没那么明显”

### 3.2 单变量实验，不能混改

这次允许做实验，但实验必须满足：

1. 一次只验证一个假设
2. 实验和正式修复分开记录
3. 实验不能直接混成最终实现

### 3.3 不动 `master`

所有工作继续留在：

- worktree: `/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings`
- branch: `codex/theme-kelivo-settings`

### 3.4 方向错了就回到基线，不在错误方向上继续打补丁

当前 worktree 已经有实验性未提交修改，尤其在：

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/SidebarView.swift`

正式实现前，要先明确哪些是保留的结构修复，哪些是本轮分析过程里的临时试验。

---

## 4. 先做的实验验证

这部分不是正式修复，而是为了验证主因排序。

## 4.1 实验 A：切断“背景图主题 => surface 降 alpha”链路

### 目的

验证 `Theme.mainBg/sidebarBg` 的半透明化是否是当前漏图的主因。

### 单变量

只改：

- `AppTheme.applyingBackgroundImageSurfaceStyle(for:)`

让 page-level surface 暂时保持不透明，其他都不动：

- root wallpaper 继续存在
- 聊天页顶部渐变继续存在
- 页码继续踩底部 safe area

### 预期结果

如果 research 判断正确，那么：

1. 左页顶部 / 底部的大块漏图会明显收缩。
2. 中页空状态大面积透图会明显减弱。
3. 聊天页顶部可能仍然残留一条，因为顶部渐变和 root 挂法还没动。

### 价值

这个实验验证的是：

> “大面积漏图”到底是不是主要来自全局 surface 透明化。

---

## 4.2 实验 B：让 root wallpaper 回到纯 root，不做局部 safe-area 算法

### 目的

验证 root wallpaper 当前挂法是否是顶底漏图的第二主因。

### 单变量

只改 `ContentView` root wallpaper 的挂法：

- 不再在 `.background { GeometryReader ... }` 里手算 safe area
- 先回到稳定、单纯的 root 背景挂法

但先不改：

- page surface alpha
- 聊天页顶部渐变
- 底部页码位置

### 预期结果

如果判断正确，那么：

1. 顶部 / 底部“像裁切错位”的那种条带感会变化。
2. 但因为页面 surface 仍然半透明，页面大面积通透感不会完全消失。

### 价值

这个实验验证的是：

> root wallpaper 挂法到底在“漏出来的形状”里占多大权重。

---

## 4.3 实验 C：只去掉聊天页顶部“渐变到透明”

### 目的

验证聊天页顶部问题里，`CardFlowView` 顶部 overlay 的贡献度。

### 单变量

只改：

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:144)

让顶部 overlay 不再从 `Theme.mainBg` 渐变到 `0 alpha`。

其余不动：

- root wallpaper
- surface alpha
- 页码 safe area

### 预期结果

如果判断正确，那么：

1. 聊天页顶部漏图应明显减少。
2. 左页和底部问题不会同步消失。

### 价值

这个实验验证的是：

> 聊天页顶部不是 root 单点 bug，而是 page 自己就在主动露底层。

---

## 4.4 实验 D：只把页码点从底部安全区拿回页面内

### 目的

验证底部漏图里，页码 overlay 自身是否是放大器。

### 单变量

只改：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:183)

让页码点不再 `ignoresSafeArea(.container, edges: .bottom)`。

### 预期结果

如果判断正确，那么：

1. 底部页码附近那块漏图会缩小。
2. 页面主体底部如果仍半透明，底部不会完全干净。

### 价值

这个实验验证的是：

> 底部问题不是单一 root 裁切问题，还包含 overlay 自己踩安全区的问题。

---

## 5. 正式修复策略

实验验证完主因排序后，再做正式实现。

## Step 1：重建 wallpaper 与 structure 的职责边界

### 目标

明确：

- wallpaper 是 root canvas
- page surface 是 structure layer

两者不能混成同一层“通透氛围层”。

### 计划做法

1. `ContentView` root 只负责全局背景画布。
2. 页级背景由页面自己承担，不再依赖 root wallpaper 来“顺便显示点氛围”。
3. 不在 root 背景里继续手写脆弱的 safe-area 裁切算法。

### 影响文件

- `MemoryPalace/Views/ContentView.swift`
- 视情况可能包括 `MemoryPalace/Views/ThemeBackgroundView.swift`

---

## Step 2：把“structure layer”从“atmosphere layer”里剥出来

### 目标

让 page-level surface 在带背景图时，仍然能稳定承担遮蔽职责。

### 计划做法

1. 重新定义哪些 token 可以继续受背景图模式影响。
2. 重新定义哪些 token 不应该被整体降 alpha。
3. 尤其是：
   - `mainBg`
   - `sidebarBg`
   不能继续既当结构底，又当氛围半透明层。

### 影响文件

- `MemoryPalace/Models/AppTheme.swift`
- `MemoryPalace/Utils/ThemeManager.swift`
- `MemoryPalace/Utils/Theme.swift`

### 说明

这一步不是取消 wallpaper 功能，而是把“结构底色”和“氛围层”分职。

---

## Step 3：按页面收最小必要的露底结构

### 目标

只清理那些会在背景图模式下放大 bug 的页面结构，不做全 app 视觉重写。

### 左页

重点看：

- `SidebarView` root 背景
- 列表内容卡背景
- 顶部搜索 / 底部 footer 的承载层

影响文件：

- `MemoryPalace/Views/SidebarView.swift`

### 中页

重点看：

- `CardFlowView` 顶部 overlay 是否继续允许透明到底层
- 空状态页是否继续只依赖半透明 `Theme.mainBg`

影响文件：

- `MemoryPalace/Views/CardFlowView.swift`
- `MemoryPalace/Views/ContentView.swift`

### 右页

重点看：

- `RightPanelView` / `MemoryPanelView` 这类工具页的整页背景是否继续只是半透明 sidebarBg

影响文件：

- `MemoryPalace/Views/MemoryPanelView.swift`
- 相关右栏页面

---

## Step 4：把设置页链路和主界面链路统一

### 目标

确保设置页 / 主题页 / 编辑主题页不再重复出现同一类漏图问题。

### 计划做法

1. 对齐主界面和设置链路的 wallpaper / surface 责任划分。
2. 不让设置页继续变成：
   - root wallpaper 在底下
   - List 透明
   - row 再用半透明 `mainBg`

### 影响文件

- `MemoryPalace/Views/SettingsView.swift`
- `MemoryPalace/Views/ThemeSettingsTab.swift`
- `MemoryPalace/Views/ThemeEditorView.swift`

---

## 6. 不做的事

本轮明确不做：

1. 不做 wallpaper 最终视觉 polish。
2. 不做整套主题系统审美重写。
3. 不做“靠遮罩 / 渐变 / 特殊 blur”掩盖 bug 的方案。
4. 不把问题重新定义成“调一调图片透明度就好了”。

---

## 7. 文件影响范围

高优先级：

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Models/AppTheme.swift`
- `MemoryPalace/Utils/ThemeManager.swift`
- `MemoryPalace/Views/SidebarView.swift`
- `MemoryPalace/Views/CardFlowView.swift`

次级可能涉及：

- `MemoryPalace/Views/MemoryPanelView.swift`
- `MemoryPalace/Views/SettingsView.swift`
- `MemoryPalace/Views/ThemeSettingsTab.swift`
- `MemoryPalace/Views/ThemeEditorView.swift`
- `MemoryPalace/Views/ThemeBackgroundView.swift`

---

## 8. 实施顺序

严格按下面顺序做：

1. 先把当前 worktree 中的实验性改动和正式基线分开
2. 跑实验 A，验证 page surface alpha 的贡献
3. 跑实验 B，验证 root wallpaper 挂法的贡献
4. 跑实验 C，验证聊天页顶部 overlay 的贡献
5. 跑实验 D，验证底部页码 overlay 的贡献
6. 基于实验结果，定最终责任划分
7. 正式改 root 与 surface
8. 正式改左页 / 中页 / 右页最小必要结构
9. 收设置页 / 主题页 / 主题编辑页
10. 跑 build
11. 跑手动验证

原因：

- 先验证主因，避免再回到“凭感觉修”
- 先修 root 与 structure，再修页面放大器
- 设置页最后收，避免主界面链路没定就到处同步

---

## 9. 验证方案

## 9.1 构建验证

必须跑：

1. `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build`
2. `xcodebuild -scheme MemoryPalace build`

## 9.2 手动页面验证

至少验证：

1. iOS 左页
   - 顶部不再有明显 wallpaper 条带
   - 底部 footer / 页码附近不再有大块漏图
   - 列表卡区域不再显得像悬浮在巨大 wallpaper 上
2. iOS 中页
   - 空状态不再整片透 wallpaper
   - 聊天页顶部工具条下方不再有明显漏图
   - 底部输入区 / sticker 区不出现新回归
3. iOS 右页
   - 工具页整体不再显得整页通透漏图
4. 设置页 / 主题页 / 编辑主题页
   - 顶部底部不回退
   - 主题背景图仍能显示
5. 无背景图主题
   - 不能被修坏

## 9.3 截图验证

至少保留一组对比截图：

1. 带背景图主题，修复前
2. 带背景图主题，修复后
3. 无背景图主题，修复后

---

## 10. 成功标准

这轮修复只有同时满足下面条件才算完成：

1. 背景图 leak 不再是肉眼第一眼就能看到的 bug。
2. wallpaper 只出现在被允许出现的区域，不再从顶底大块留白中稳定透出。
3. 左页 / 中页 / 右页不回退到超宽或巨大 UI。
4. 设置页链路不回退。
5. 背景图功能继续可用。
6. iOS/macOS build 都通过。

---

## 11. Todo

- [x] 先确认当前 worktree 中哪些修改属于实验残留，哪些属于可保留基线
- [x] 做实验 A：切断背景图模式的 surface alpha 降级
- [x] 做实验 B：切换 root wallpaper 挂法，验证 safe-area 贡献
- [ ] 做实验 C：移除聊天页顶部“渐变到透明”，验证顶部 leak 来源
说明：最终结构修复后顶部 leak 已消失，这个单独实验本轮未再执行，也没有必要把聊天页 overlay 当成主修复点去动。
- [x] 做实验 D：把页码点拿回页面内，验证底部 leak 来源
- [x] 基于实验结果确定最终责任划分
- [x] 正式重建 root wallpaper 与 page surface 的职责边界
- [x] 正式修左页结构层
- [x] 正式修中页结构层
- [x] 正式修右页结构层
- [x] 收设置页 / 主题页 / 编辑主题页
- [x] 跑 `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build`
- [x] 跑 `xcodebuild -scheme MemoryPalace build`
- [x] 手动验证 iOS 左页 / 中页 / 右页 / 设置页 / 主题页 / 编辑主题页
