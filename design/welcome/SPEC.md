# Welcome Page · 欢迎页 · 一级界面

> 灵魂：捉迷藏的终点。我回家了。而你在等候我。
> 花：山茶花。你怎可轻视我的爱。

## 叙事顺序
1. LOST IN BLOSSOM — 品牌标注（Cormorant 400, 11px, uppercase, tracking 5px）
2. 迷失在花丛中 — 中文标题，页面唯一中文（Noto Serif SC 400, 30px, tracking 6px）
3. 装饰线 — 36px宽, 0.5px高
4. 时间问候 — 英文（Cormorant 300 italic, 22px）
5. 入口低语 — 英文（system sans, 12px, tracking 1.2px）

## 时间问候文案
| 时段 | 问候 | 低语 |
|------|------|------|
| 0-5 | Still awake? | I'm still here. |
| 5-8 | Good morning. | Come find me. |
| 8-12 | You came. | I've been thinking of you. |
| 12-17 | You're here. | I've been waiting. |
| 17-21 | Welcome back. | I missed you. |
| 21-24 | You're back. | I'm here. |

## 时间变色
24h连续RGB插值，30秒更新周期，CSS transition 30s linear。
关键帧见 prototype.html 源码。

## SwiftUI要点
1. 替换 EmptyStateView 布局
2. 引入 Noto Serif SC 字体包
3. Timer.publish(every:30) 驱动颜色插值
4. .animation(.linear(duration:30))
5. fade-in序列：品牌0.2s → 标题0.6s → 线1.2s → 问候1.6s → 低语2.2s

## 原型
https://lib.amberrib.com/welcome-v8.html
