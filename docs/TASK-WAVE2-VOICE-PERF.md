# 第二波搬运：语音消息系统 + B9 侧栏性能

> 参考仓库：`/root/projects/SusuPalace`（先 `git fetch origin`，代码在 origin/master）
> 两个任务互相独立，可乱序做

---

## 任务一：语音消息系统

### 目标
让 Caelum 能发语音条。AI 在回复里写 ```voice 代码块 → 自动走 ElevenLabs TTS 生成 mp3 → 气泡变语音条胶囊。

### 核心设计（零新工具！）

AI 不需要学新工具，只需要在回复里写：
````
```voice
晚安小兔，今天辛苦了。记得吃药，早点睡。
```
````
turn 结束后 VoiceMessageWriter 自动识别、提取脚本、调 TTS、挂回 node。

### 从粟粟复制的文件

```bash
cd /root/projects/SusuPalace && git checkout origin/master

# 创建目录
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Services/Voice

# 核心 5 文件
cp MemoryPalace/Services/Voice/ElevenLabsClient.swift \
   MemoryPalace/Services/Voice/VoiceMessagePlayer.swift \
   MemoryPalace/Services/Voice/VoiceMessageWriter.swift \
   MemoryPalace/Services/Voice/VoicePromptInjector.swift \
   MemoryPalace/Services/Voice/VoiceTuning.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/Voice/

# Views 2 文件
cp MemoryPalace/Views/VoiceCapsuleView.swift \
   MemoryPalace/Views/VoiceSettingsSection.swift \
   /root/projects/BunnyPalace/MemoryPalace/Views/
```

### 接线（6 步）

#### 1. MessageSegment 加 audioRef case

找 `MessageSegment` 枚举（可能在 `Conversation.swift` 或 `MessageNode` 附近），加：
```swift
case audioRef(fileName: String, script: String, durationMs: Int)
```

参考：
```bash
grep -n "enum MessageSegment\|case.*audioRef" /root/projects/SusuPalace/MemoryPalace/Models/Conversation.swift
```

#### 2. turn 收口时调 VoiceMessageWriter

找到 assistant 回复完成的地方（`onComplete` 里 `node.content = fullText` 之后），加：
```swift
// 语音条意向处理
VoiceMessageWriter.processChatIntents(
    nodeId: node.id,
    context: context,
    profiles: ProfileManager.loadProfiles()
)
```

三个 onComplete 路径（send / regenerate / editAndResend）都要加。

#### 3. 气泡渲染语音条胶囊

在 `CardFlowView.swift` 的 BubbleView body 里，检查 node 有没有 audioRef segment：
```swift
if let segs = node.segments,
   segs.contains(where: { if case .audioRef = $0 { return true } else { return false } }) {
    VoiceCapsuleView(node: node)
}
```

放在 Markdown 渲染之后（或替代正文渲染，取决于 node.content 是否只有占位行）。

#### 4. VoicePromptInjector 注入 system prompt

在 PromptAssembler 的 system prompt 末尾注入语音指令：
```swift
// 语音意向提示
let voiceHint = VoicePromptInjector.promptFragment(
    voiceEnabled: VoiceTuning.isProactiveEnabled,
    voiceName: profile.elevenVoiceName ?? "默认"
)
if !voiceHint.isEmpty {
    // 加到 volatile 层不影响缓存
}
```

#### 5. Profile 加语音设置字段

Profile 结构体加：
```swift
var elevenVoiceId: String?
var elevenVoiceName: String?
```

#### 6. 设置页加语音设置

在设置页合适位置加 `VoiceSettingsSection()`。它需要：
- ElevenLabs API Key 输入（存 Keychain）
- 声音选择列表（从 ElevenLabs API 拉）
- 主动语音开关

### 编译适配

- `KeychainStore`：粟粟有专门的 Keychain 工具类。如果我们没有，用简单的 `UserDefaults` 临时替代（key 不敏感的话），或者加一个最小 Keychain 封装：
```bash
grep -rn "struct KeychainStore\|enum KeychainStore\|class KeychainStore" /root/projects/SusuPalace/MemoryPalace/ --include="*.swift"
```
如果找到就一起复制过来。

- `FileLibraryManager`：语音 mp3 存到文件库。如果我们没有同名类，找到我们的文件存储 API 适配。

### 验证

1. 编译通过
2. 设置页能输入 ElevenLabs API Key + 选声音
3. 给 Caelum 发"用语音跟我说晚安" → AI 回复带 ```voice 块 → 占位行出现 → mp3 生成 → 变语音条胶囊
4. 点语音条能播放
5. 长按菜单有"换一版"

---

## 任务二：B9 侧栏性能优化

### 目标
229 条对话的侧栏滚动卡顿 → 标签分页 + 搜索 N+1 修复 + 杂项瘦身。

### 参考 commits

```bash
cd /root/projects/SusuPalace
# 按顺序看这四个 commit：
git show 3fa80b5   # P1-1: 标签 tab 真分页
git show a5169fc   # P1-7: 搜索 N+1 修复
git show b73aa20   # P1-7: 删死函数
git show 53c6276   # P2: 四件小刀
```

### 改动 1：标签 tab 真分页（最重要）

**参考**：`3fa80b5`

**问题**：选标签时把所有对话加载进来再过滤，对话多了极慢。

**修法**：`SidebarView.swift` 里标签过滤逻辑改成 SwiftData 层面分页：
- 先查该标签关联的 conversationIds（tagPredicate 4 分支）
- 用 `IN` 收窄 FetchDescriptor predicate
- 加 `fetchOffset` / `fetchLimit`（每页 50）
- `loadMore` 下一页追加

关键代码模式（参考粟粟 diff）：
```swift
var desc = FetchDescriptor<Conversation>(
    predicate: #Predicate { convIds.contains($0.id) && $0.profileId == pid },
    sortBy: [SortDescriptor(\Conversation.updateTime, order: .reverse)]
)
desc.fetchLimit = 50
desc.fetchOffset = currentPage * 50
```

### 改动 2：搜索 N+1 修复

**参考**：`a5169fc`

**问题**：搜索命中 300 条 → 每条单独查一次 MessageNode 判断是否在主线上 = 300 次 SwiftData 查询。

**修法**：在 `SearchService.swift`（或我们搜索用的文件）里把逐条查改成每 20 条分批 IN：
```swift
// 旧：for id in hitIds { fetchOne(id) }
// 新：
for start in stride(from: 0, to: hitIds.count, by: 20) {
    let chunk = Array(hitIds[start..<min(start+20, hitIds.count)])
    let desc = FetchDescriptor<MessageNode>(
        predicate: #Predicate { chunk.contains($0.id) }
    )
    let batch = try context.fetch(desc)
    // 处理 batch...
}
```

找我们的搜索代码：
```bash
grep -rn "computeMainPathSet\|isOnMainPath\|searchResults.*filter" MemoryPalace/Services/ MemoryPalace/ViewModels/ --include="*.swift" | head -10
```

### 改动 3：titleMap 瘦身

**参考**：`53c6276`

FetchDescriptor 拉对话列表时加 `propertiesToFetch`，只拉标题和日期，不拉整个对象：
```swift
desc.propertiesToFetch = [\Conversation.title, \Conversation.updateTime]
```

减少内存占用和查询时间。

### 改动 4：EmptyStateView fetchLimit=1

空态检测（"你还没有对话"）只需要知道有没有，不需要全拉：
```swift
var emptyCheck = FetchDescriptor<Conversation>(predicate: ...)
emptyCheck.fetchLimit = 1
let isEmpty = (try? context.fetch(emptyCheck))?.isEmpty ?? true
```

### 改动 5：列表过滤 300ms 防抖

标签/搜索切换时加 300ms debounce，防止快速点击连续触发重查：
```swift
.onChange(of: selectedTag) { _, _ in
    filterTask?.cancel()
    filterTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await reloadList()
    }
}
```

### 验证

1. 编译通过
2. 229+ 条对话列表滚动流畅
3. 标签切换响应 < 500ms
4. 搜索 300 条命中不卡顿
5. 空列表状态正常显示

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. 语音任务和性能任务互相独立，可乱序做
3. 每个改动单独 commit
4. 语音系统：`feat(voice): ...`
5. 侧栏性能：`perf(sidebar): ...`
