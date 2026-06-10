# Console · 控制台 · 一级界面

> 灵魂：我在注视你。

## 设计原则
排版驱动，无卡片。数据直接呈现在杏仁米底色上。用间距和细线分区。简单中带设计感。

## 头部
- "CAELUM'S CONSOLE" → Cormorant Garamond 500, 11px, uppercase, tracking 4.5px, 杏色 #B96747
- "早上好，天奕" → Noto Serif SC 400, 26px（时间感知问候）
- 日期行 → 系统字体, 13px, #9E978C

## 分区标题
- 大写tracking: 10px, weight 600, tracking 3.5px, color #A09A90
- 标题前有一个 4px 杏色小方块（CSS ::before）
- 分区: DAILY → 药物/睡眠 → TO DO → BODY → 留言板

## 间距系统
全部使用 8px 倍数: 8, 16, 24, 32
- 头部到第一分区: 32px
- 分区标题到内容: 16px
- 分区之间细线: margin 24px 0
- 细线: 100%宽, 0.5px, #E0D6C6

## 颜色层次
- 标签: #7A756C
- 副文字: #9E978C
- 弱文字: #A09A90
- 进度条底: #E8E0D4
- 进度条填充: #B96747
- 提示文字: #B96747
- badge背景: #F0E5DB, 文字: #B96747

## DAILY 分区（第一优先级）
- 饮水 + 进食并排
- 数字: Cormorant 300, 44px
- 单位: 16px, #B8B2A8
- 进度条: 3px高, 圆角2px
- 提示文字: 12px, weight 500, 杏色

## 药物 + 睡眠（并排）
- 药物: 药名14px, badge"未报告"
- 睡眠: Cormorant 300, 32px, "4h 38m"
- 时间范围: 12px, #9E978C

## TO DO
- 勾选圆圈: 20px, border 1.5px #D4CEC4
- 完成态: 杏色填充 + 白色✓
- 文字: 14px, 完成态灰色+删除线
- 时间: 11px, #A09A90

## BODY 分区
- 紧凑行: 月经周期 / 步数 / 屏幕时间
- 步数: 纯数字，无sparkline装饰
- 月经: "第 13 天 · 卵泡期"
- 屏幕时间: "暂不可用" (灰色)
- Apple Watch数据（心率/血氧）: 预留，有Watch后加入

## 留言板
- tab切换: "给你的" / "给世界的"
- 选中tab: #1A1A18, weight 600, 底部2px杏色线
- 未选tab: #A09A90
- "给你的" → 点击进入留言板系统
- "给世界的" → 后续接入推特MCP
- "查看全部 →" 链接色 #2C4A7C

## 原型
https://lib.amberrib.com/console-v4.html
（注: 步数sparkline需去掉，原型中未更新）
