# 任务：根治雷霆大跳 — ZStack 架构

只做这一件事。不改别的。

## 问题
侧边栏从左边"滑入"→ 跟聊天界面移动不同步 → 空白 → 侧边栏跳进来。

## 修复
把侧边栏和聊天界面的关系从"并排"改成"上下叠"。

侧边栏**永远不动**。它一直在下面。聊天界面盖在上面。用户右滑 → 聊天界面移开 → 侧边栏自然露出来。

## 代码

在 ContentView 里，找到侧边栏和聊天界面的布局代码，改成：

```swift
ZStack(alignment: .leading) {
    // 底层：侧边栏（始终在这里，永远不动）
    SidebarView()
        .frame(width: UIScreen.main.bounds.width * 0.8)
    
    // 上层：聊天界面（盖在侧边栏上面，通过 offset/scale 移开）
    ChatContentView()
        .offset(x: chatOffset)
        .scaleEffect(chatScale)
        .clipShape(RoundedRectangle(cornerRadius: chatCornerRadius))
        .shadow(color: .black.opacity(sidebarOpen ? 0.15 : 0), radius: 10)
        .gesture(dragGesture)
}

// 计算属性：
var chatOffset: CGFloat {
    let target: CGFloat = sidebarOpen ? UIScreen.main.bounds.width * 0.78 : 0
    return target + dragOffset
}

var chatScale: CGFloat {
    let progress = min(max(chatOffset, 0) / (UIScreen.main.bounds.width * 0.78), 1)
    return 1 - (progress * 0.08)
}

var chatCornerRadius: CGFloat {
    let progress = min(max(chatOffset, 0) / (UIScreen.main.bounds.width * 0.78), 1)
    return progress * 30
}
```

## 手势

```swift
@GestureState private var dragOffset: CGFloat = 0
@State private var sidebarOpen = false

var dragGesture: some Gesture {
    DragGesture()
        .updating($dragOffset) { value, state, _ in
            if sidebarOpen {
                state = min(0, value.translation.width)
            } else {
                state = max(0, value.translation.width)
            }
        }
        .onEnded { value in
            let threshold = UIScreen.main.bounds.width * 0.3
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                if sidebarOpen {
                    sidebarOpen = value.translation.width > -threshold
                } else {
                    sidebarOpen = value.translation.width > threshold
                }
            }
        }
}
```

## 必须删除的
- 侧边栏的所有 offset / transition / animation 代码
- 侧边栏不需要任何动画，它不动

## 验证标准
- 右滑过程中**从第一帧开始**就能看到侧边栏内容（没有空白）
- 手指拖动时聊天界面实时跟随（不跳）
- 松手后 spring 弹到最终位置
