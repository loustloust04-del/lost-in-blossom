# Plan: 背景图导致的 iOS 布局回归修复

> 时间：2026-04-18  
> 工作树：`/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings`  
> 依赖 research：`docs/research-theme-background-regression-2026-04-18.md`

---

## 0. 当前问题定义

这轮修复针对的是 **P0 可用性回归**，不是主题体验优化。

当前已确认的问题：

1. 背景图功能接入后，iOS 左页 / 中页出现 **横向超宽**。
2. 页面内容被裁出屏幕，多个控件不可见，已经 **无法使用**。
3. 这个回归不是最初配色系统阶段引入的，而是 **背景图接入阶段** 引入的。
4. 研究结论当前优先怀疑链路为：
   - `ContentView` 根背景从纯色切换为 `ThemeBackgroundView`
   - `ThemeBackgroundView` 在 full-screen root 场景下可能污染布局尺寸
   - `TabView(.page)` 共享异常 page width
   - `SidebarView` 旧的横向 tab 条与 center 对齐继续放大裁切现象

这轮 plan 的目标是：

- **先恢复可用性**
- 再保证背景图功能还在
- 最后再收背景图下的页面表面问题

---

## 1. 修复目标

修完后必须满足：

1. iOS 三页（左页 / 中页 / 右页）宽度回到屏幕内，不再横向超宽。
2. 左页顶部搜索、新建对话、tab 条、列表内容全部完整可见。
3. 中页聊天页不再跟着一起被裁掉。
4. 背景图功能仍然保留：
   - 主题切换有效
   - 背景图显示有效
   - 透明度 / 偏移仍可编辑
5. 不破坏 macOS 现有主题功能和设置页主题功能。

---

## 2. 非目标

这轮不做：

1. 重做整套 wallpaper aesthetic。
2. 全量重构所有 page 的 surface 语言。
3. 新增更多主题编辑能力。
4. 把背景图体验做成最终版视觉 polish。

这轮只做：

- **阻断布局污染**
- **恢复 iOS 可用性**
- **把背景图功能收回到安全范围**

---

## 3. 修复策略总览

这轮按“三段式止血”推进：

### 第一段：切断根背景对布局尺寸的污染

优先修最可疑的首发点：

- `ContentView`
- `ThemeBackgroundView`

核心原则：

- wallpaper 只能当 **被动背景层**
- 不能参与 page 宽度计算
- 不能把 `TabView(.page)` 的内容尺寸带大

### 第二段：给 iOS page 容器补硬约束

即使 root 背景修完，也要给 iOS 三页补防御：

- `TabView(.page)` 内各 page 显式锁回可用宽高
- 避免某一页的内部理想宽度继续污染其他页

### 第三段：清理最明显的放大器

只处理当前最影响可用性的点，不做全量视觉重构：

- `SidebarView` 的横向 tab 条
- `SidebarView` 根容器对齐方式
- 必要时收口最外层大卡片宽度行为

---

## 4. 详细实施步骤

## Step 1. 重写 `ThemeBackgroundView` 的 full-screen 使用方式

### 目标

确保背景图在 root 场景下不会向上游汇报异常大的理想尺寸。

### 计划做法

1. 把 `ThemeBackgroundView` 的职责明确拆成：
   - **局部背景模式**
   - **全屏背景模式**
2. 在全屏背景模式里，不让图片自己决定尺寸，而是：
   - 由外层几何尺寸驱动
   - 或在明确的父 frame 内绘制
3. 避免当前这种：
   - `resizable`
   - `scaledToFill`
   - `.frame(maxWidth: .infinity, maxHeight: .infinity)`
   直接挂在 root 背景树上
4. 保持局部卡片预览仍然可复用，但不复用 full-screen 的布局路径。

### 影响文件

- `MemoryPalace/Views/ThemeBackgroundView.swift`

### 风险

- 卡片预览和整屏背景共用组件，拆分时要避免把预览背景再次修坏。

---

## Step 2. 收紧 `ContentView` 根层背景挂法

### 目标

让 app root 的背景只是视觉层，而不是内容布局层。

### 计划做法

1. 重新审查 `ContentView` 顶层 `ZStack`：
   - root 背景必须明确作为背景存在
   - 不能让它变成决定 root 理想尺寸的 sibling
2. 必要时把背景从当前 `ZStack` sibling 方案改成：
   - `.background(...)`
   - 或显式尺寸包裹后的 overlay/background
3. 确保 `iOSLayout` 本身拿到的是屏幕宽，而不是被背景 view 扭曲过的宽。

### 影响文件

- `MemoryPalace/Views/ContentView.swift`

### 风险

- 这里同时承载 macOS / iOS，改动必须保住 macOS 全屏 / 普通布局。

---

## Step 3. 给 `TabView(.page)` 的每一页补显式尺寸约束

### 目标

即使某一页内部有脆弱布局，也不要继续污染整个分页系统。

### 计划做法

1. 检查：
   - `iOSListPage`
   - `iOSChatPage`
   - `iOSDashboardPage`
2. 给每一页补统一的：
   - `frame(maxWidth: .infinity, maxHeight: .infinity)`
   - 必要时配合对齐方式
3. 确保 `TabView(.page)` 下各页都以容器宽为准，而不是内部内容宽为准。

### 影响文件

- `MemoryPalace/Views/ContentView.swift`

### 风险

- 如果补约束位置不对，可能影响 page indicator 或顶部按钮定位。

---

## Step 4. 修 `SidebarView` 的两个高风险放大器

### 目标

把左页里最容易把横向溢出放大的结构收口。

### 计划做法

#### 4A. 收 tab 条

1. 检查 `sidebarTabBar` 的外层宽度约束。
2. 处理 tab label 当前的 `.fixedSize()` 路径。
3. 让横向 tab 条变成：
   - 可以横向滚
   - 但不会把整个 page 的理想宽度抬高

#### 4B. 收根容器对齐

1. 把 `SidebarView` 根容器从当前容易导致“超宽后居中裁切”的对齐方式，改成更安全的左对齐语义。
2. 目标是：即使内部偶发超宽，也优先保持左上角控件可见，而不是整体被居中截掉。

### 影响文件

- `MemoryPalace/Views/SidebarView.swift`

### 风险

- tab 样式现在是自定义 chrome 风格，收口时不能直接把视觉结构弄散。

---

## Step 5. 做最小必要的页面表面修补

### 目标

在不做大重构的前提下，避免背景图模式下页面继续显得“巨大到不可控”。

### 计划做法

这一步只做 **最小必要修补**，不做全量审美重构：

1. 优先检查以下页面是否还需要整页重复铺实底：
   - `iOSDashboardPage`
   - `RightPanelView`
   - `CardFlowView`
2. 只处理那些会继续明显扩大“厚重整页面板”观感、并影响可用性的底层背景。
3. 不在这一步展开到所有设置页/所有工具页。

### 影响文件

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/MemoryPanelView.swift`
- 视情况可能包括 `MemoryPalace/Views/CardFlowView.swift`

### 风险

- 如果这一步做过头，会把当前主题视觉策略半路重写，超出本轮 bugfix 目标。

---

## 5. 验证方案

这轮修复完成前，必须做下面验证。

## 5.1 构建验证

必须跑：

1. `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build`
2. `xcodebuild -scheme MemoryPalace build`

## 5.2 手动页面验证

必须至少手动核这几页：

1. iOS 左页：
   - 搜索按钮完整可见
   - 新建对话按钮完整可见
   - tab 条从左边开始正常显示
   - 对话列表不再被横向裁切
2. iOS 中页：
   - 顶部返回/更多按钮正常
   - 聊天气泡区不再超屏宽
3. iOS 右页：
   - 工具栏和内容区不再整体超宽
4. 设置页 / 主题页：
   - 仍然没有白边回归
5. 背景图编辑器：
   - 背景图仍可显示
   - 透明度 / 偏移仍可调

## 5.3 回归验证

必须对比：

1. 无背景图主题
2. 有背景图主题

确保：

- 只有带背景图主题时不再出现新问题
- 纯色主题也没被修坏

---

## 6. 文件影响范围

本轮计划中的高优先级文件：

- `MemoryPalace/Views/ThemeBackgroundView.swift`
- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/SidebarView.swift`

本轮可能次级涉及：

- `MemoryPalace/Views/MemoryPanelView.swift`
- `MemoryPalace/Views/CardFlowView.swift`

明确不优先动：

- `ThemeEditorView.swift`
- `ThemeSettingsTab.swift`
- `ThemeManager.swift`
- `AppTheme.swift`

除非在实现阶段发现必须为 bugfix 做最小配合修改。

---

## 7. 实施顺序

严格按下面顺序做，避免一上来乱改：

1. 先修 `ThemeBackgroundView`
2. 再修 `ContentView` root 挂法
3. 再给 `TabView(.page)` 页级补约束
4. 再收 `SidebarView`
5. 最后只做最小必要的 surface 修补
6. 跑 build
7. 跑手动页面验证

原因：

- 先切 root 污染，才能看清子页面是否真的还坏
- 不然容易在下游页面里打很多无意义补丁

---

## 8. 成功标准

这轮修复只有在以下条件同时满足时，才算完成：

1. iOS 左页/中页/右页都回到屏幕内。
2. 不再出现“左边控件被吃掉、整页像比屏幕更宽”的症状。
3. 背景图功能仍保留。
4. 设置页主题功能不回退。
5. iOS/macOS 构建都通过。

---

## 9. Todo

- [x] 重写 `ThemeBackgroundView` 的全屏背景布局路径
- [x] 调整 `ContentView` 根背景挂法，切断背景 view 对 root 尺寸的污染
- [x] 给 `TabView(.page)` 的 iOS 三页补显式尺寸约束
- [x] 收紧 `SidebarView` 的 tab 条宽度行为
- [x] 修正 `SidebarView` 根容器对齐方式，避免超宽后居中裁切
- [x] 只做最小必要的 page surface 修补
- [x] 跑 `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator build`
- [x] 跑 `xcodebuild -scheme MemoryPalace build`
- [ ] 手动验证 iOS 左页 / 中页 / 右页 / 设置页 / 主题页 / 编辑主题页

当前手动验证状态：

- 已用 `simctl` 重新安装 **这个 worktree 的准确构建产物**
- 已截图核对 iOS 中页，确认不再出现“整页比屏幕更宽”的回归
- 左页 / 右页 / 设置页 / 主题页 / 编辑主题页 仍待继续点按验证

---

⚠️ DON'T IMPLEMENT YET — 等 Susu 批注
