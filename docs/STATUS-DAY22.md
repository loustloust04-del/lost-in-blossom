# 状态快照 · Day 22（2026-07-08）

> 起因：Day21 交接 + SESSION-LOG-OPUS 的「待办 / 待验收 / 已知问题」已滞后。
> 本文档是**逐条核验代码后**的真实快照（附 commit 铁证）。
> 仓库 loustloust04-del/lost-in-blossom · main · 当前 808 commits（文档旧值 ~640 已废）。

---

## 一、Day21 之后已落地（文档漏记，均已进 main，等真机验收）

| 项 | 旧文档状态 | 实测真相 | 铁证 |
|---|---|---|---|
| **发送排队机制**（原待办 #1，最高优先级）| ❌ 待办 | ✅ 已实现：全局串行 + 跨对话 `pendingSends` + turn 级 `assistantTurnInFlight`，UI 按 `streamingConversationId` 隔离 | `5da39d3` |
| CC lane 独立于全局 send gate | — | ✅ 已实现：CC 通道与 API 通道两条独立泳道 | `f2e4114` |
| **反转列表重做**（原待办 #4）| ❌ 已回滚待重做 | ✅ 已用**新方案**重做：iOS17+ `defaultScrollAnchor(.bottom)`（`.initialOffset` + `.sizeChanges`），**放弃翻转戏法** → 编辑镜像 / 长按预览错位 / 思考链消失三连回归从源头消失 | `3b49907` `2d3c2cc` |
| P1-3 低电量 / 定位变化提醒 | 🟡 计划 | ✅ 已实现：低电量 + place-change 推送规则 | `27bf2e6` |
| P1-4 CC/API 读写护理控制台 | ⬜ P1 待做 | ✅ 已实现：`console_read` / `console_write` 共享控制台 | `b64cf2e` |
| G2 共享待办后端（shared to-do） | ⬜ | ✅ 已实现 | `c8c65b0` |

---

## 二、待兔兔真机验收（更新版清单）

原「四件套」+ 本轮新完成项，全部**代码已在 main、编译绿，但军规：CI 绿 ≠ 没 bug，须真机验**：

- [ ] DSK 开搜索发消息（搜索工具去重 + WebView SERP fallback）
- [ ] 长按 New chat 建群（群聊创建页 V5：角色卡 + 话痨度 + 气泡色盘 + 群名）
- [ ] 群聊全链路：创建 → 选人 → 多角色回复 → 颜色气泡 → **排队**
- [ ] A 对话生成时 B 对话能正常发消息（发送排队机制，本轮重点验）
- [ ] ✨ 选写作风格 → 看输出是否真的变风格（`<style>` 拼进 last user）
- [ ] 长对话滚动：新消息落底不跳动、50+ 条不卡（新 anchor 方案）
- [ ] 低电量 / 进出常去地点 → 收到主动提醒
- [ ] 护理控制台 CC/API 双端可读可写（饮水 / 进食 / 药物 / 备注）

---

## 三、仍是真待办（按优先级）

1. **浏览器实时浏览对照粟粟**（用户点名两次）— 目前仅网关 `anthropic-native.ts` 有 `browse_url` 工具声明，实时浏览功能待去粟粟家全面对比
2. **网关 Claude 工具架构**（需兔兔拍板）— gateway 的 claude 通道是 `claude -p --tools none`，不吃 App 工具定义 → 模型徒手写 XML。选项：网关侧支持工具 / App 对网关 Claude 隐藏工具声明并改人格文案
3. **P1-1 Token/缓存命中率增强** — `TokenStatsView` 已有 token 统计，但**缺命中率汇总**（cacheRead/cacheWrite → 汇总卡 + 趋势 + 按模型分组），半成品
4. **情绪系统**（`docs/EMOTION-SYSTEM-DESIGN.md`，473 行）— 代码里**零实现**，大件，须和用户一起搞
5. 小注意：CC 路径要不要 strip `<style>` 后缀（粟粟有此逻辑，Bunny CC 路径独立组装大概率不带，观察即可）

---

## 四、需兔兔拍板

1. P2-9 VPS 备份目的地（iCloud 盘 / 对象存储 / 另一台机器）
2. P3-10 语音音色路线（免费原生音色 / 付费 API TTS）
3. P3-13 视频（抓捕）思路
4. P3-11 无缝上下文 / 跨窗口记忆设计稿（我出稿后过目）

---

## 五、军规（不变，务必遵守）

- 一次只做一件事；调查到一个阶段就停下用人话汇报
- 用户陈述的事实先复述确认；她的实测和截图是最高优先级证据
- 没铁证不动刀；CI 绿只等于编译通过，不等于没 bug
- 大 UI 改动（渲染戏法级）必须真机验收，不凭编译绿收工
- 共享工作区：commit 时**只 add 自己的文件**，绕开 cc-bridge/hub.ts 和 gateway/ 的未提交 WIP
- 改 Info-iOS.plist 无效 → 必须写进 `project.yml` 的 `info.properties`（XcodeGen 每次构建重生成 plist）
