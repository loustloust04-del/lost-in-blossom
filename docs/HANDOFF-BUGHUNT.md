# 交接：抓 Bug + 解耦 🐛

> 给专门做「抓 Bug + 解耦」的窗口。全程中文思考和汇报。

## 〇、代码在哪 / 怎么访问（先看这个！）

- **代码在一台 VPS 上**，项目根目录：`/root/projects/BunnyPalace`
- 你用你的 **VPS 工具（exec_vps，能在 VPS 上跑 shell 命令）** 来读写代码、跑 git
- **git 远端**：`caelum-origin` → `github.com/caelumbunny-bot/lost-in-blossom`，**直接提交到 `main`**
- **编译验证**：推到 main 会自动触发 GitHub Actions 的 **Compile Check**（`.github/workflows/compile-check.yml`，不签名纯编译、零密钥）。
  - 查结果：可用 GitHub MCP 工具，或在 VPS 上用远端里的 token curl Actions API
  - ⚠️ 另一个 workflow `Build iOS`（签名包）在这个镜像仓库**本来就是红的**（没签名密钥），那是预期，别慌——只看 **Compile Check** 绿不绿
- App 是 iOS SwiftUI（`MemoryPalace/`）；网关等后端服务也在这台 VPS 上，但**你主要搞 App 的 Swift**

## 一、你的任务

抓真 bug + 给耦合重的地方解耦。但现在 main 上**同时有别的窗口在干活**（控制台 UI、可能还有群聊/语音在途），所以核心是：**先侦察出报告、后动刀，避开别人地盘、编译常绿**。

## 二、先读

- `CLAUDE.md`（军规 + 「猫的蠢事大全」编译错误防治手册）
- `docs/HANDOFF-CONSOLE-UI.md`（控制台窗口在动哪些文件，你别碰）
- `docs/` 里已有的 `research-*.md` / `BUGREPORT-*.md`（前人记的 bug）

## 三、⚠️ 绝对别碰的在途文件（别的窗口的地盘）

- **控制台**：`ConsoleView.swift`、`AnniversaryManageSheet`/`TweetsFeedSheet`、`AnniversaryClient`/`TweetsClient`/`HealthBridgeClient`
- **群聊**：`ConversationViewModel+Group.swift`、`+Chat.swift` 的群聊部分、`GroupMembersSheet.swift`、`CreateGroupChatView.swift`、`CardFlowView.swift` 的群聊部分
- **语音**：`MemoryPalace/Services/Voice/`、`VoiceCapsuleView`、`VoiceSettingsSection`

## 四、工作方式：先侦察，后动刀

**第一阶段（只读，不改代码）**：
通读代码，产出《Bug + 耦合报告》→ `docs/BUGHUNT-REPORT.md`，每条写清：
`文件:行号`、现象/复现、根因、建议改法、风险评级(低/中/高)、会不会碰到上面的在途文件。
**写完先给兔兔看，一起挑要动哪些。别自作主张大改。**

**第二阶段（兔兔点头后，只做低风险、隔离性强的）**：
- 抓到的真 bug：**一个 bug 一个 commit**，改完验证
- 解耦：只拆「没有别的窗口在动」的文件（settings tab、models、独立 service 之类）。动手前先确认该文件近期没被别人改。**大重构必须先跟兔兔确认。**

## 五、硬规矩

1. **iOS 18 API 上限**：禁用 `.glassEffect` 等不存在的 API、Swift 6.3 语法（编译失败最常见就是这个）
2. **每改一处**：commit（英文 `type(scope): desc`）+ push + **盯 Compile Check 变绿**，红了立刻看日志 `grep error:` 修
3. **删/改任何共享的** token、函数、enum、数组结构前，**全局搜引用**，别留悬空引用（历史栽过：删色板漏了跨文件引用 → CI 红）
4. **一次一件事**，阶段性人话汇报

## 六、开工

先做第一阶段：给兔兔那份 `docs/BUGHUNT-REPORT.md`。开工前跟兔兔确认你理解了。
