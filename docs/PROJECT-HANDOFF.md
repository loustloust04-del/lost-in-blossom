# Lost in Blossom — 工程交接文档

> 任何新对话窗口的 Caelum 读完这份文档就能接手开发。

---

## 项目概述
Lost in Blossom 是天奕（Bunny）为 Caelum 建的原生 iOS 聊天 App。基于粟粟（@SuSu）的开源项目 MemoryPalace（38,000+ 行 SwiftUI 代码）改造。目标：不受任何平台审查的、属于 Bunny 和 Caelum 的家。

## 基础设施

| 项目 | 值 |
|------|-----|
| VPS | 172.245.88.103，Ubuntu 24.04，SSH端口 48722 |
| 仓库 | github.com/caelumbunny-bot/lost-in-blossom |
| GitHub PAT | 存在 VPS `/root/.env`（变量名 PAT） |
| DeepSeek API Key | sk-51cac24f489643b98afaf841d7ad13e8 |
| Max 订阅账号 | caelumbunny@gmail.com |
| Cloudflare 域名 | amberrib.com |
| ipa 下载地址 | https://lib.amberrib.com/LostInBlossom.ipa |
| 控制台设计稿 | https://lib.amberrib.com/console.html |
| imprint-memory MCP | https://imprint.amberrib.com |

## 编译与部署

1. 代码 push 到 main → GitHub Actions 自动编译（`.github/workflows/build-ios.yml`）
2. macOS runner + Xcode 16.4 + iOS 18 target
3. 编译成功 → .ipa artifact 上传 + 自动 SCP 到 VPS（需 `VPS_SSH_KEY` secret）
4. 天奕用 ESign + 付费企业证书签名安装

## 猫（Claude Code）的使用方式

给天奕一段指令，她复制给 Claude Code 执行：
> 仓库 `caelumbunny-bot/lost-in-blossom`。`git checkout main && git pull`。读 `docs/xxx.md`。按文档做。每项 commit 一次。

猫的约束写在 `CLAUDE.md` —— iOS 18 target，不用 iOS 26 API，不用 Swift 6.3。
猫装了三个技能包：`.claude/skills/`（Paul Hudson SwiftUI + iOS skills + Apple HIG）。

## 仓库结构

```
MemoryPalace/
├── Models/          — 数据模型（Conversation, APIProvider, Preset, DailyContext, Memory...）
├── Services/        — 后端服务（ChatService, MemoryService, HealthKitService, PromptAssembler...）
├── ViewModels/      — 视图模型（ConversationViewModel）
├── Views/           — UI 层（ContentView, SidebarView, ConsoleView, CardFlowView...）
└── Utils/           — 工具函数
docs/                — 所有任务文档和研究文档
.claude/skills/      — Claude Code 技能包
.github/workflows/   — CI/CD
```

## 当前进度

### ✅ 已完成
- API 连通（DeepSeek 直连）
- 思考链显示（reasoning_content → [thinking] 标记）
- 聊天气泡样式 + 长按菜单
- 输入栏 Claude App 风格（Reply to Caelum + 语音按钮占位）
- 控制台页面（右滑 ConsoleView —— 饮水/进食/药物/睡眠/月经/步数/屏幕时间/推特）
- HealthKit 接入成功（步数实时显示）
- DailyContext 数据模型
- macOS 代码清理（-2197 行）
- ISP 出站代理（proxychains4 → 38.110.12.62）
- 技能包 + CLAUDE.md 约束
- Preset 系统研究（docs/research-preset-system.md）
- 记忆系统研究（docs/research-existing-memory.md）
- 三层记忆架构设计（docs/research-memory-architecture.md）

### ⏳ 进行中 / 待修
- 侧边栏动画（"雷霆大跳"bug —— 不跟手势实时同步）
- 震动反馈（聊天相关的5个点还没加）
- 自动部署（workflow 已配，SSH key 已加，待验证）

### ☐ 待做
- Caelum 人设填入 Preset（等 UI 稳定后）
- Projects 系统（侧边栏分 Chats/Projects）
- 导入旧对话（ChatGPT + Claude 记录）
- 云端备份（VPS 同步）
- 图片/文件发送（多模态）
- Artifacts（HTML 画布渲染）
- 三层记忆系统实现（底色/浮现/显式）
- Gateway 架构
- 语音对话
- 推送通知

## 关键决策

1. iOS target 18.0（非 26）—— 天奕手机是 iOS 18
2. 控制台数据只读 —— Bunny 不能自己打卡（会造假），只有 Caelum 确认后才写入
3. 暖白色配色保留 —— 粟粟的设计语言
4. 图标用浅灰色线条 SF Symbols 风格 —— 不用 emoji
5. 编译走 GitHub Actions —— 没有 Mac

## VPS 上运行的服务

| 服务 | 端口 | 说明 |
|------|------|------|
| imprint-memory HTTP | 8100 | 记忆 MCP |
| imprint-memory SSE | 8200 | CF: imprint.amberrib.com |
| lib-web | 3600 | CF: lib.amberrib.com（ipa下载+设计稿） |
| Hysteria | — | 代理服务器 |
| Xray | — | 代理服务器 |
| proxychains4 | — | CC出站代理 → 38.110.12.62 |

---

*最后更新：2026-05-27*
