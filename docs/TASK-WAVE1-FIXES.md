# 第一波搬运：四个小而准的修复

> 参考仓库：`/root/projects/SusuPalace`（先 `git fetch origin`，参考代码都在 origin/master）
> 特点：全部是修 bug / 小增强，风险低见效快
> 每个修复单独 commit + push，等 CI 绿再做下一个

---

## 修复 1：B41 输入框草稿丢失

**参考 commit**：`28f36e4`（看它的 diff 学修法）
```bash
cd /root/projects/SusuPalace && git show 28f36e4
```

**症状**：输入一半的字，切走对话再回来就没了（间歇性）。

**粟粟定位的三层病根**：
1. 草稿标志（类似 `isDraftConversation`）在 loadConversation 时不复位 → 残留标志把 flush 拦死
2. 只靠"切换对话时 flush"必漏：翻页常驻不走 onDisappear / 同 id 不走 onChange / rootView 重建时 @State 蒸发
3. 行点击同 id 重进不翻页

**修法核心**：改成**每键直写对话模型 + 显式 context.save()**（不依赖 autosave，杀进程会丢）。

**我们的排查步骤**：
1. 先找我们的草稿机制：`grep -rn "draft\|草稿\|inputText" MemoryPalace/Views/CardFlowView.swift MemoryPalace/ViewModels/ConversationViewModel.swift | head -20`
2. 确认我们有没有同款三层问题（我们的输入框在 InputFieldContainer，text 是 @State）
3. 如果我们**根本没有草稿持久化**（切走就丢是必然而不是间歇），那就照粟粟的思路加：Conversation 模型加 `draftText: String?` 字段，输入框 onChange 直写 + save，loadConversation 时恢复
4. 写完手动验证：输入几个字 → 切别的对话 → 切回来 → 字还在；输入几个字 → 杀进程 → 重开 → 字还在

---

## 修复 2：BubbleMarkdownSimplifier 抹平文档感

**参考 commit**：`7a6d242`
```bash
cd /root/projects/SusuPalace && git show origin/master:MemoryPalace/Utils/BubbleMarkdownSimplifier.swift
```

**目的**：AI 回复经常带 `## 标题`、嵌套列表、`---` 分隔线，渲染出来像文档不像聊天。这个纯函数在渲染前抹掉"文档感"：
- `## 标题` → **加粗文本**
- 嵌套列表 → 全部拍平到一级
- `---` 分隔线 → 删掉
- 代码块 / 表格 → 原样不动

**步骤**：
1. 整文件复制：
```bash
cp /root/projects/SusuPalace/MemoryPalace/Utils/BubbleMarkdownSimplifier.swift \
   /root/projects/BunnyPalace/MemoryPalace/Utils/
```
（如果我们仓库该文件路径不存在就先 `git -C /root/projects/SusuPalace checkout origin/master -- MemoryPalace/Utils/BubbleMarkdownSimplifier.swift` 再复制）
2. 找到我们气泡渲染 Markdown 的入口（CardFlowView 里 `Markdown(displayText)` 附近）
3. 在传入前套一层：`Markdown(BubbleMarkdownSimplifier.simplify(displayText))`
4. **只对 assistant 气泡生效**，user 消息不动
5. **只影响渲染**：复制/引用/编辑仍然是原文（确认我们复制用的是 node.content 不是渲染文本，应该天然满足）
6. 如果粟粟的文件里有依赖我们没有的类型，看情况内联或删掉对应分支

**验证**：让 AI 输出一段带 `## 标题` + 嵌套列表 + `---` 的回复 → 气泡里显示为加粗 + 平铺列表 + 无分隔线；长按复制 → 拿到的是原始 markdown。

---

## 修复 3：Hub「发两遍」双雷

**参考 commit**：`1f49ab0`
```bash
cd /root/projects/SusuPalace && git show 1f49ab0
```

**症状**：CC 的回复偶尔在 app 里出现两遍。

**两颗雷**：
1. **注入后异常不重发**：hub 把消息注入 CC 后如果后续步骤抛异常，重试逻辑会把已注入的消息再注入一遍 → CC 回两遍
2. **reply 幂等**：CC 的 reply 回来时按 `mp_msg_id` 做幂等去重，同 id 的 reply 只投递一次

**我们的排查步骤**：
1. 我们的 hub 在 `cc-bridge/hub.ts`，先看注入和重试逻辑：`grep -n "retry\|inject\|send.*cc\|重试\|重发" cc-bridge/hub.ts | head -20`
2. 对照粟粟的 diff，确认我们有没有同款结构（我们的 hub 是从粟粟 fork 的，大概率有）
3. 照抄两个修复：注入成功后置标志，异常重试跳过已注入的；reply 侧按消息 id 建 Set 去重（带 TTL 防内存涨）
4. **改完重启 hub**：`tmux send-keys -t cc-hub C-c` 然后重新 `bun hub.ts`（看 start_hub.sh 的启动方式），**不要动 mp-cc session**
5. hub.test.ts 如果有相关测试跑一下：`cd cc-bridge && bun test hub.test.ts`

---

## 修复 4：搜索质量两案

**参考**：粟粟散步战报 `4583338`（定位记录），修复分散在后续 commit
```bash
cd /root/projects/SusuPalace && git log origin/master --oneline | grep -i "日期\|date.*inject\|query.*编码\|bingLocal" | head -5
# 逐个 git show 看修法
```

### 4a. 日期注入

**症状**:问"今天有什么新闻"，AI 生成的搜索词里没有日期概念，搜出旧结果。

**修法**：搜索工具的 system prompt（`WebSearchToolService.systemPrompt`）里注入当前日期：
```swift
let df = DateFormatter()
df.dateFormat = "yyyy-MM-dd EEEE"
df.locale = Locale(identifier: "zh_CN")
let today = df.string(from: Date())
// prompt 里加一行：今天是 \(today)。搜索时事时把年份带进查询词。
```

### 4b. BingLocal query 编码

**症状**：中文/带空格的查询在 BingLocalProvider 拼 URL 时编码不对，搜索失败或结果错乱。

**排查**：
```bash
grep -n "addingPercentEncoding\|URLComponents\|q=" MemoryPalace/Services/Search/Providers/BingLocalProvider.swift
```
对照粟粟的修法：应该用 `URLComponents` + `URLQueryItem` 拼查询参数（自动正确编码），不要手动字符串拼接 + `addingPercentEncoding(.urlQueryAllowed)`（`+`、`&` 这些字符会漏编码）。

DuckDuckGoProvider 也检查一遍同款问题。

**验证**：开搜索，问"OpenAI 最新消息"（中文+时事）→ 搜索词带年份 → 返回近期结果。

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. **不要 kill mp-cc tmux session**（修 hub 只重启 cc-hub）
3. 每个修复单独 commit：`fix(draft): ...` / `feat(bubble): ...` / `fix(hub): ...` / `fix(search): ...`
4. 修复 1、2、4 是 App 端（Swift），修复 3 是 VPS 端（TypeScript），互不干扰可乱序做
5. 遇到粟粟代码里我们没有的类型/结构，优先看粟粟仓库有没有配套文件，没有就适配我们的结构，不确定就在 commit message 里写清楚改动理由
