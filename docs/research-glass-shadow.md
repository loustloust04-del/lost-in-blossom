# Research: 左栏 glass 按钮阴影穿透 tab 栏

> 日期：2026-04-17

## 目标效果（用户红排线图）

```
[glass 搜索] [glass 新建]
  ↓ 阴影自然下扩
[sidebarBg 空间 - 可见阴影]
  ↓
[全部(selected,mainBg)]  [收藏(纯文字)]  [回收站(纯文字)]
                         ↑ 阴影在这里可见！tab 背后是 sidebarBg 页面，shadow 自然过渡
[mainBg 列表卡 - 覆盖阴影]
```

**核心原则：未选中 tab 只有文字，没有容器。shadow 穿过它的位置就像穿过空气一样。**

## 之前走错的方向

| 错误方案 | 为什么错 |
|---|---|
| bar-level `.background(sidebarBg)` | 整条不透明背景 = 硬切割线 |
| card 容器 `zIndex(1)` | 容器 rect 有边界 = 依然是硬切割线，只是位置变了 |
| 给按钮大量 padding 让阴影消散 | 本质是补丁，占用过多空间 |
| glassEffect `.clear` 变体 | 玻璃质感丢失 |
| `.interactive()` 去掉 | 只是副作用调节，不解决架构 |

## 现有代码的真实结构

```swift
sidebarTabBar = HStack {
    ForEach(tabs) { tab in
        Button {
            Text(tab.name)
                .background(
                    UnevenRoundedRectangle(topRadius: 16)
                        .fill(isSelected ? mainBg : sidebarBg)  // ← 问题在这里
                )
        }
    }
}
.background(sidebarBg)  // ← 这条也要去掉
```

**两个问题元素：**
1. **未选中 tab 的 `.fill(sidebarBg)`**：明确不透明绘制 sidebarBg，即使和页面背景同色，它仍然是一个独立绘制层 — shadow 到这个层的位置就被阻断了
2. **bar-level `.background(sidebarBg)`**：整条不透明层，shadow 到这里也被阻断

## 正确方案

### 方案：未选中 tab 完全透明，bar 也透明

```swift
.background(
    UnevenRoundedRectangle(topRadius: 16)
        .fill(isSelected ? mainBg : Color.clear)  // 未选中 = 透明
)
// bar 级别不加任何 background
```

这样：
- 未选中 tab = 纯文字，shape fill 透明，页面 sidebarBg 直接显示，shadow 自然穿透
- 选中 tab = mainBg fill 覆盖 shadow
- 没有 bar 级别的不透明层，shadow 无限制穿透

### 需要验证的问题

**Q1: Tab 之间还有视觉分隔吗？**
- 未选中 tab 没有 fill，tab 之间只有间距空白（页面 sidebarBg）
- 选中 tab 的 mainBg 在一群透明 tab 里显得突出，就是 Chrome 效果
- ✅ 符合设计意图

**Q2: Tab 圆角顶部的透明区在未选中 tab 上怎么样？**
- 未选中 tab 整体透明（不只是圆角），所以整个未选中 tab 都是 sidebarBg 页面
- ✅ 不会有局部透明造成的问题

**Q3: 反向圆角（InverseTabCorner）怎么办？**
- 反向圆角当前填充 mainBg，overlay 在选中 tab 底部两侧
- 未选中 tab 变透明后，反向圆角依然需要 — 它是从选中 tab 的 mainBg"流"到列表的 mainBg 的过渡
- 反向圆角覆盖的区域是 sidebarBg（未选中 tab 或 tab 间隙），所以 fill mainBg 是对的
- ✅ 不变

**Q4: shadow 会不会遮住未选中 tab 的文字？**
- shadow 本身是很淡的（glassEffect 自适应），即使落在文字下方也不会盖住文字
- 未选中 tab 文字是 textSecondary（深色），shadow 是浅深色，文字依然清晰
- ✅ 不遮挡

**Q5: sidebar 最外层 VStack 的 background 是 sidebarBg，这会不会有影响？**
```swift
.background {
    if isIOSStyle {
        Theme.sidebarBg.ignoresSafeArea()
    } else {
        Theme.sidebarBg
    }
}
```
- 这是整个 sidebar 的页面背景，shadow 落在它上面就是正常的 shadow 效果
- ✅ 正确，保留不动

## Apple 文档关键点

- `.glassEffect` 的 shadow 无法单独关闭
- 唯一控制方式：不要用不透明元素去遮挡它，让它自然扩散到页面背景上
- 内容卡应该是 shadow 的"终点"（被遮挡），不是 shadow 的"路径"（穿过）

## 决定

**不需要实验页，方案已经清晰。直接做：去掉两行：**
1. `sidebarTabBar` 的 `.background(Theme.sidebarBg)`
2. 未选中 tab 的 `UnevenRoundedRectangle.fill(Theme.sidebarBg)` → 改为 `Color.clear`

## 风险

- 之前我试过去掉 bar 背景但保留 tab 背景，结果 tab 圆角缝隙让 shadow 描出 tab 轮廓
- 这次两个都去掉，未选中 tab 完全透明，不会有轮廓描边问题
- 唯一可能的问题：Chrome 效果视觉依赖于"tab 有背景色"，完全透明后可能看起来像"三个独立文字 + 一个选中卡片"
- 但这正是用户要的 — "未选中的tag字直接浮在背景上"
