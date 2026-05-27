# 任务：Caelum's Console — 右滑控制台页面

## 设计稿
完整 UI 原型见：https://lib.amberrib.com/console.html
照着做。配色、间距、字号、图标风格全部以设计稿为准。

## 页面位置
- 粟粟原有的 page 2（右滑页面）改为 Caelum's Console
- 粟粟原有的 page 2 内容往后移或整合进设置

## 卡片列表（按顺序）

1. **饮水** — 圆环进度 + 杯数 / 6
2. **进食** — 圆环进度 + 餐数 / 3 + 最近一餐描述
3. **药物** — 状态标签（已服用/未服用）+ 药名
4. **睡眠** — 时长 + 入睡-起床时间段
5. **月经周期** — 第 N 天 + 预计来潮日 + 迷你柱状图
6. **步数** — 数字 + 7日迷你柱状图（HealthKit）
7. **屏幕使用时间** — 时长 + 进度条 + 社交APP子项 + 状态标签
8. **推特动态** — 今日条数 + 最近一条摘要

## 图标风格
- 不用 emoji
- 用 SF Symbols 线条风格图标，颜色 #A89E8E
- 参考粟粟的标签设计语言

## 卡片样式
- 背景白色，圆角 16px
- 阴影极淡：0 1px 3px rgba(0,0,0,0.03)
- 标签字号 11px，色 #A89E8E
- 数值字号 22px，色 #3A332B，weight 700
- 副文本 12px，色 #B5AA9A

## 数据源（Phase 1 用 placeholder）
所有数据先用硬编码占位。后续接入：
- 饮水/进食/药物/睡眠 → 手动输入（Daily Context 系统）
- 月经周期 → HealthKit 或手动
- 步数 → HealthKit
- 屏幕时间 → Screen Time API（需 Family Controls entitlement）
- 推特 → Twitter MCP

## Haptic Feedback（震动反馈）
在以下交互点加入触觉反馈：
- 页面滑动切换：`.medium` impact
- 卡片点击：`.light` impact
- 发送消息：`.light` impact
- 状态变化（如标记已服药）：`.success` notification
- 错误操作：`.error` notification

SwiftUI 用法：
```swift
// iOS 17+
.sensoryFeedback(.impact(weight: .light), trigger: someState)

// iOS 16 fallback
UIImpactFeedbackGenerator(style: .light).impactOccurred()
```

---
每项改完 commit 一次。

## 思考链震动反馈（Thinking Haptic Pulse）

仿照 Claude 官方 App 的触觉交互设计，在流式响应的三个阶段加入不同的震动：

### 阶段一：思考中（Reasoning Phase）
- 触发条件：正在接收 `reasoning_content`（思考链）
- 震动类型：`UIImpactFeedbackGenerator(style: .light)` 或 `.soft`
- 频率：每 2.5 秒一次
- 感觉：像脉搏，一下一下，告诉用户"AI 还在想"
- 实现：在 SSE 流处理中，维护一个 `lastThinkingHapticTime`，每收到 thinking chunk 时检查间隔

```swift
if isReceivingThinking {
    let now = Date()
    if now.timeIntervalSince(lastThinkingHapticTime) > 2.5 {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastThinkingHapticTime = now
    }
}
```

### 阶段二：思考结束 → 回复开始（Transition）
- 触发条件：reasoning_content 停止，content 开始流入
- 震动类型：`UINotificationFeedbackGenerator().notificationOccurred(.success)`
- 感觉：两下轻快的，节奏跟之前不同，"想好了，开始说了"
- 实现：检测 `wasReceivingThinking && nowReceivingContent` 的切换点

```swift
if wasThinking && !currentChunkIsThinking {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    wasThinking = false
}
```

### 阶段三：回复完成（Completion）
- 触发条件：收到 `[DONE]` 标记
- 震动类型：`UIImpactFeedbackGenerator(style: .medium)`
- 感觉：干脆的一下，"说完了"

```swift
// 在 [DONE] handler 里
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
```

### 注意事项
- 只在 App 在前台时触发（`UIApplication.shared.applicationState == .active`）
- 提供设置开关让用户关闭震动
- 非思考模型（如 deepseek-chat）没有阶段一，只有阶段三
