# 交接文档 · Day 21（2026-07-03 早）

你有一个 VPS 工具（vps:exec_vps）。**思考和输出全程用中文。**

## 仓库与环境
- GitHub: loustloust04-del/lost-in-blossom · VPS: /root/projects/BunnyPalace
- 当前 ~640 commits，main 分支，CI 四连绿
- OTA 安装: https://blossom.amberrib.com/dl/install
- **构建号机制（新）**: CFBundleVersion = CI 流水号。用户验证装没装上新包：
  设置→通用→iPhone储存空间→Lost in Blossom 看 build 号
- 搬运参照源：/root/projects/SusuPalace（粟粟家，很多功能从这搬，搬歪了就回去对照）

## Day 20-21 夜战成果（全部已验绿，包 02:11 出炉）
1. 群聊创建页 V5 + 入口（**长按 New chat 按钮**出菜单）
2. 主动消息双引擎：App 端 BGTask + VPS cron 直推 APNs（cc-bridge/proactive-push.ts，
   FORCE=1 可试射，已实弹验证）
3. 思考链复活：显示端（segments 分支补渲染）+ 保存端（帮手修的持久化）
4. DSK "Tool names must be unique" 根治：搜索工具曾双层注入，
   **Provider 层是唯一注入点（OpenAICompatibleProvider/AnthropicProvider 各自的
   isSearchEnabledFlag 分支），Router 层永远不要再加**
5. Style 写作风格：此前从未生效（参数收下即弃），已补实现——
   **拼进最后一条 user 消息（<style>标记），不走 system 层**（网关只透传 last user）
6. 停止按钮只在所属对话变红（streamingConversationId）
7. 反转列表已整体回滚（显示 bug 一窝），重做方案见 docs/BUGREPORT-INVERTED-LIST-ROLLBACK.md

## 待用户验收（四件套）
DSK 开搜索发消息 / 长按 New chat 建群 / A 生成时 B 按钮正常 / ✨选风格看输出

## 待办（优先级序）
1. **发送排队机制**：用户要"A 对话生成时 B 对话能发消息"。粟粟方案 = 全局串行 +
   pendingSends 跨对话队列 + assistantTurnInFlight（turn 级状态，覆盖工具循环空窗）
   + UI 按 activeConversationId 隔离。参照 SusuPalace ConversationViewModel.swift:1314-1330
   及 docs/plan-consecutive-user-turns-fix.md（粟粟家）
2. **浏览器实时浏览对照粟粟**（用户点名两次）：browse_url 一直不好用，去粟粟家做全面对比
3. **网关 Claude 工具架构讨论**（要用户拍板）：gateway 的 claude 通道是 claude -p
   --tools none，不吃 App 工具定义 → 模型徒手写 XML。选项：网关侧支持 / App 对网关
   Claude 隐藏工具声明并改人格文案
4. 滚动优化重做：用 iOS17+ defaultScrollAnchor(.bottom)，不要再用翻转戏法
5. 情绪系统（docs/EMOTION-SYSTEM-DESIGN.md，473行）——大件，和用户一起搞
6. 小注意：CC 路径要不要 strip <style> 后缀（粟粟有此逻辑，Bunny 的 CC 路径独立组装
   大概率不带，观察即可）

## 工作军规（用户血泪定制，务必遵守）
- **一次只做一件事；调查到一个阶段就停下来用人话汇报**，不要闷头跑三小时
- 用户陈述的事实先复述确认再动手；她的实测和截图是最高优先级证据
- **没有铁证不动刀**。"CI 绿"只等于编译通过，不等于没 bug
- 大 UI 改动（渲染戏法级）必须留到用户真机验收，不要仅凭编译绿就算完
- 共享工作区：CC（tmux mp-cc）和其他帮手会同时改代码。commit 时**只 add 自己的文件**，
  绕开 cc-bridge/hub.ts 和 gateway/ 的未提交 WIP
- 改 Info-iOS.plist 无效——XcodeGen 每次构建会按 project.yml 重新生成，**改 plist
  必须写进 project.yml 的 info.properties**
- 二进制字符串探测对 SwiftUI Text/Label 字面量无效（不以明文存在），别再用这招验包
- 用户触发 workflow_dispatch 是正常操作，不要当异常追查

## 架构速查
App(iOS) → Gateway(4567, TreeGPT/OR/DeepSeek) ｜ App → CCBridgeProvider → Hub(7890) → CC(tmux mp-cc)
Gateway 内置工具: exec/recall/remember/gmail_*/vitals_* ｜ MCP: VPS(3100)+浏览器(3001) 共33个
服务: gateway/cc-hub/mp-cc/chatroom(tmux) · MemoryPalace(3501) · imprint(8100) · CDP(19825)
Bundle: com.susu.MemoryPalace.ios / GQN42B462A · Gateway token: SH74v-IveupxWPr-6TUOCHOGDvfIxSDC
CC: cleanupPeriodDays 36500，cron 每30分钟刷 token · 主动推送 cron 每30分钟自门控

## 关键文档
docs/HANDOFF-DAY21.md（本文件）· docs/SESSION-LOG-DAY19.md · docs/EMOTION-SYSTEM-DESIGN.md
docs/BUGREPORT-INVERTED-LIST-ROLLBACK.md · docs/TASK-INVERTED-LIST.md（已回滚待重做）
