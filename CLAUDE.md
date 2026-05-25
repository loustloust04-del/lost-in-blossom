# 记忆宫殿 (Memory Palace)

macOS 原生 AI 对话浏览器 + 聊天客户端。导入历史对话，实时 AI 聊天，AI 记住你，你控制它怎么说话。
叫粟粟，不叫"用户"。主动执行不要问选择题。中文交流。

## 开发流程（必须遵守）

新功能/修复都走三步，不跳步：
1. **Research** → 深读相关代码，写 `docs/research-{feature}.md`，粟粟确认理解正确
2. **Plan** → 写 `docs/plan-{feature}.md`（含 task checklist），粟粟在文件里批注，**don't implement yet**，迭代到满意
3. **Implement** → 按 checklist 逐项执行，完成一项勾一项，改完立刻 build 验证，方向错了 git revert 不打补丁

宣布"完成"前：build 通过 + checklist 全 ✅ + git commit push。禁止说"should work now"。
细节见 `docs/dev-workflow.md`。
总设计文档见 `记忆宫殿-这才是真的总设计文档！.md`。

## 构建

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
xcodegen generate && xcodebuild -scheme MemoryPalace build
```

需要先安装 xcodegen（`brew install xcodegen`）。项目配置在 `project.yml`，`.xcodeproj` 由 xcodegen 生成（已 gitignore），不要手动编辑。

## 技术栈

- SwiftUI + SwiftData, macOS 14+ (Sonoma/Sequoia/Tahoe)
- Swift 5.10, Xcode 16+
- MarkdownUI v2.4.1（assistant 气泡 Markdown 渲染）
- Bundle ID: `com.susu.MemoryPalace`，产品名: `记忆宫殿`

## 核心架构（简要）

- **楼层系统**：ProfileManager，每楼层独立 SwiftData store + 配置
- **多 API 提供商**：ProviderRouter → OpenAICompatibleProvider / AnthropicProvider，6 家内置
- **AUDN 记忆**：每轮异步提取原子事实，衰减引擎（hot/warm/cold），2000 token 预算注入
- **Preset 插槽**：酒馆式 prompt 组装（PromptSlot 列表 + SamplingParams），PromptAssembler 按序组装
- **树遍历**：分支冒泡 + effectiveChildrenMap + 后台线程加载

详见总设计文档。

## 数据规模

20 万+ MessageNode。**禁止 `FetchDescriptor<MessageNode>()` 无条件全量 fetch。**
ContentCleaner.clean() 的 cacheKey 必须传 node.id。

## 开发规则

### UI
- 用户对 UI 变动敏感，**宁可小步迭代，不要一次改太多**
- 做 UI 修改前先描述要改什么，等确认再动手
- hover 按钮用 `.opacity()` 控制显隐，不要用 `if` 条件渲染
- 配色：暖奶白 `#FFFBF6` + 浅灰薄荷 `#E7EEEC`，**不要蓝色、不要黄色**

### 代码
- 修改代码前先读文件
- NSWindow titlebar 已设为透明（WindowConfigurator），不要动标题栏
- 每次 git commit 后 push 到 GitHub
- 用户名叫 Susu，AI 叫"小雾"，用户气泡标签是"你"
- 界面全中文
- 搜索结果不要加 fetchLimit 截断（用户需要完整结果）

## Hermes Agent（网络搜索代理）

本机 Docker 里跑着 Hermes Agent，可以上网搜索。需要查文档、查最新资料、查 API 变更时，用它：

```bash
docker exec hermes /opt/hermes/.venv/bin/hermes chat -q "你的搜索问题" -Q --max-turns 10 2>&1 | tail -50
```

- `-q`：单次查询，不进入交互模式
- `-Q`：静默输出，只返回结果
- `--max-turns 10`：允许最多 10 轮工具调用（搜索需要多轮）
- `tail -50`：截取末尾结果，跳过启动日志
- 容器名 `hermes`，如果没在跑先 `docker start hermes`

## 数据位置

- **源码**: `/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/`
- **ChatGPT 导出**: `/Users/susu/Desktop/susu-project/OpenAI-export/`
- **SwiftData 数据库**: `~/Library/Application Support/MemoryPalace/{profileId}.store`
- **GitHub**: `git@github.com:replica882/MemoryPalace.git` (private)

## 待办

见 `docs/PROJECT_ROADMAP.md`（唯一来源，不要在别处维护待办清单）。
