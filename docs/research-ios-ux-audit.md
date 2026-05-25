# iOS UX 问题审计报告

> 审计日期: 2026-04-10
> 设备: iPhone 17 Pro 模拟器 (iOS 26.4)

## 致命级（完全不能用）

### 1. 滑动手势和 ScrollView 冲突
- **位置**: `ContentView.swift:134`
- **现状**: `DragGesture(minimumDistance: 18)` + `.simultaneousGesture` 和 ScrollView 同时抢手势
- **症状**: 滚动列表/聊天时意外翻页，翻页时意外滚动
- **修复**: 替换为 `TabView(.page)` — 原生处理手势优先级

### 2. 发送按钮 24x24pt
- **位置**: `CardFlowView.swift:281`
- **现状**: `frame(width: 24, height: 24)` — iOS 最小 44pt
- **症状**: 手指点不准，最高频操作变最痛苦操作

### 3. 键盘挡住输入框
- **位置**: `CardFlowView.swift` ChatInputBar
- **现状**: 无 keyboard avoidance
- **症状**: 键盘弹出后看不到打的字

## 严重级（能用但很痛苦）

### 4. 全场字号太小
- **现状**: macOS 的 10-13pt 直接用到手机上
- **关键违规**:
  - `CardFlowView.swift:316` — chevron 7pt（不可读）
  - `MemoryPanelView.swift:594` — meta 8pt
  - `MemoryPanelView.swift:614,621` — 标签 9pt
  - `SidebarView.swift:254` — 折叠箭头 9pt
  - 全场 13pt body 文本 — iOS 标准 17pt
- **修复**: iOS 字号映射 +2~3pt

### 5. 导航按钮太小
- **位置**: `ContentView.swift:174,202` — 36x36pt
- **位置**: `MemoryPanelView.swift:126` — 34x34pt
- **修复**: iOS 上扩大到 44x44pt

### 6. Popover 在 iPhone 上崩坏
- **位置**: `CardFlowView.swift:328` — Model 选择器
- **位置**: `SidebarView.swift:81` — 排序选项
- **修复**: iOS 上用 `.sheet` + `.presentationDetents([.medium])`

## 体验级（能忍但不舒服）

### 7. 三屏没有页面指示器
- 用户不知道有三页，不知道在哪页
- **修复**: 加小圆点或顶部指示

### 8. padding 没适配
- 聊天区 28pt horizontal 浪费 iPhone 宽度
- 侧边栏 12pt horizontal 太紧

### 9. 缺少 swipe actions
- 对话列表只有 contextMenu（长按），没有左滑删除/收藏

### 10. 没有触觉反馈
- 翻页、点击无 haptic

### 11. 固定宽度组件
- FolderPickerSheet `width: 300` — iPhone SE 可能溢出
- ModelPickerPopover `width: 220`

---

## 修复记录（2026-04-10）

### 已完成

| Commit | 改动 | 对应问题 |
|--------|------|----------|
| `5d7346a` | NavigationStack push 导致四屏 → 纯 onTapGesture；onChange dismiss keyboard | #1 四屏, #3 键盘 |
| `022229b` | HStack+DragGesture → TabView(.page)，原生处理滑动/滚动冲突 | #1 滑动冲突 |
| `204e228` | 导航按钮 36→44pt，发送按钮 24→32pt+44pt hitbox，工具按钮 34→44pt | #2 发送按钮, #5 导航按钮 |
| `6efeef0` | Model 选择器/排序 popover → sheet；翻页 sensoryFeedback | #6 Popover, #10 触觉 |
| `29d487d` | 全局 onTapGesture dismiss + ScrollView scrollDismissesKeyboard | #3 键盘 |
| `6861d9e` | TabView ignoresSafeArea 消白条；禁 UICollectionView bounce；iOS 去掉重复导入按钮 | 顶部白条, 过度滑动 |
| `6660058` | 排序控件从搜索栏移到筛选 chip 栏右侧 | UI 整理 |
| `cf9439e` | 排序合并进 AdvancedSearchPanel；搜索栏/chip/列表统一 iOS 20pt 边距 | UI 整理 |
| `2be87d4` | 高级面板去掉圆角框，iOS 上直接用 20pt padding | 边距对齐 |
| `af8cfc1` | 高级面板 frame(maxWidth: .infinity, alignment: .leading) | 左对齐 |
| `fcb847a` | 设置齿轮 13→16pt，底部栏边距统一 20pt | 控件大小 |
| `c15527a` | 键盘"完成"工具栏按钮 + scrollDismissesKeyboard(.immediately) + 去掉无效 ZStack onTapGesture | #3 键盘 P0 |
| `ef7a7a8` | 设置页加聊天字号滑块（0.5~2.0），替代 macOS cmd+/- | #4 字号 P1 |

### 未完成 / 待后续

| 问题 | 优先级 | 备注 |
| **顶部白条** | P1 | TabView ignoresSafeArea 在模拟器上修好了，真机待确认 |
| **TabView 边缘 bounce** | P1 | 用 disableBounceInSubviews 遍历 UICollectionView，真机效果待确认 |
| **页面指示器** | P2 | 用户不知道有三页。可加自定义圆点或顶部 segmented control |
| **swipe actions** | P2 | 对话列表无左滑删除/收藏，只有 contextMenu 长按 |
| **固定宽度组件** | P2 | FolderPickerSheet `width: 300`、ModelPickerPopover `width: 220`，iPhone SE 可能溢出 |
| **聊天页 padding** | P2 | 聊天区 `.padding(.horizontal, 28)` 在 macOS 合适但 iPhone 上浪费宽度（已有 16pt 的 iOS 分支） |
| **BubbleView 按钮** | P2 | 编辑/收藏/删除按钮尺寸偏小，需要在 iOS 上增大触控区域 |

### 设计决策记录

- **圆角胶囊风格**：粟粟确认按钮风格是圆角胶囊，不要改成大圆球
- **日期/条数小字就要小**：粟粟确认 meta 信息保持小号不需要放大
- **边距标准**：iOS 统一 20pt 水平边距（参考 Apple Settings inset grouped list）
- **排序放在高级面板里**：不单独弹 sheet，和时间/角色筛选合并在同一个展开面板
