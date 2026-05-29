# 任务：碎碎念卡片 + A页侧边栏手势修复

## Task 1: 侧边栏手势仅在 page 0 生效

**问题**：控制台（page 1）上也能触发侧边栏的边缘手势，产生一个半开的侧边栏。应该只在聊天页（page 0）上触发。

**修复**：在 `PagingViewController.swift` 的 `handleSidebarEdgePan` 方法开头，检查当前 scrollView 的 page index。如果不是 page 0，直接 return，不发送 notification。

```swift
// 在 handleSidebarEdgePan 方法开头添加：
let pageWidth = scrollView.frame.width
let currentPage = Int(round(scrollView.contentOffset.x / max(pageWidth, 1)))
guard currentPage == 0 else { return }
```

## Task 2: 碎碎念卡片

在控制台（ConsoleView / iOSDashboardPage）的**屏幕使用时间卡片下面**，添加一个新卡片。

### 卡片设计

- 卡片名称区域有两个 tab：**"给你的"** 和 **"给世界的"**
- 默认选中 "给你的"
- tab 用小型文字按钮实现，选中态加粗 + 下划线或底色，未选中态灰色
- 卡片样式跟其他卡片一致（白色底、圆角 16、阴影 0 2 8 rgba(0,0,0,0.04)）
- 卡片占满整行（grid-column: 1 / -1）

### "给你的" tab 内容

显示最新一条留言/碎碎念：
- 留言文本（最多显示 2 行，超出截断）
- 底部小字显示时间（如 "3 分钟前"）
- 右下角 "查看全部 →" 链接文字
- 点击整张卡片进入留言板全屏页面（暂时用一个空的 placeholder 页面，后续接入粟粟的贴纸系统）

### "给世界的" tab 内容

把**原来的推特动态卡片**的内容移到这里：
- 显示跟原来推特卡片一样的内容
- 原来推特卡片的位置删除（不再单独显示）

### 位置

在 ConsoleView 中找到卡片的排列顺序，在屏幕使用时间（Screen Time）卡片之后、推特动态卡片之前插入碎碎念卡片。然后删除原来的推特动态卡片（内容已合并到碎碎念的"给世界的"tab）。

最终顺序从上到下：
1. 标题区（CAELUM'S CONSOLE）
2. 饮水 + 进食
3. 药物 + 睡眠
4. 月经周期
5. 步数
6. 屏幕使用时间
7. **碎碎念**（新增）

---

两个 task 做完，一个 commit：`feat(console): add memo card with dual-tab + fix sidebar gesture on page 1`

读 CLAUDE.md 的猫的蠢事大全。不要犯。
