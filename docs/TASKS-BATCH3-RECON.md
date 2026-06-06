# 第三批调查任务 — CC 侦察，不动手

> 日期：2026-06-06
> ⚠️ 这批任务只做调查，不改代码，不 commit。把调查结果写回本文件对应位置。

---

## Recon 1: 聊天流式输出白屏 + 弹跳 + 对话间距突增

**症状**:
- 流式输出时向上滑动会出现白屏
- 向上滑会反复弹跳到最底端
- 对话过程中对话之间的间距会突然增大

**调查方向**:
1. 找到聊天列表的 ScrollView / LazyVStack 实现位置（CardFlowView.swift）
2. 记录 ScrollView 的 scrollTo 逻辑 — 是否在每个 token 到达时都强制滚到底部？
3. MessageContentWebView 的 dynamicHeight 变化频率 — 是否每次高度变化都触发 ScrollView 重新布局？
4. 间距突增可能是 WebView 高度突然从 0 跳到实际值，或 spacing 在某个条件下翻倍
5. 列出所有涉及 `scrollTo`、`ScrollViewReader`、`onChange(of: dynamicHeight)` 的代码位置和行号

**输出**: 在下方写调查结果
```
（猫填写）
```

---

## Recon 2: CC 流式输出完全失败

**症状**: CC 的流式输出根本不工作

**调查方向**:
1. CC 流式走的是 WebSocket 还是 SSE？找到 CCBridgeWebSocketClient.swift 里的消息处理逻辑
2. 服务端（cc-bridge/）的流式输出格式是什么？对比 App 端的解析逻辑
3. 检查 WebSocket 连接状态 — 是否连接成功但消息格式不匹配？
4. 在 VPS 上运行 `tail -50 /tmp/chatroom.log` 和 cc-bridge 的日志，看有没有报错
5. 对比能工作的场景（如果有）和不能工作的场景

**输出**: 在下方写调查结果
```
（猫填写）
```

---

## Recon 3: API 显示逻辑耦合

**症状**: API 设置页面的显示逻辑有问题，可能代码已耦合需要重写

**调查方向**:
1. `MemoryPalace/Views/APISettingsTab.swift` 的完整结构 — 列出所有主要 section 和它们的行号范围
2. 哪些 provider 类型共享了不该共享的 UI 逻辑？（比如 OpenAI 和 Anthropic 和 CC Bridge）
3. 哪些状态变量是全局的但应该是 per-provider 的？
4. 文件总行数，哪些 section 可以拆分成独立 View

**输出**: 在下方写调查结果
```
（猫填写）
```

---

## 规则

- **只调查，不改代码，不 commit**
- 把发现写在对应的代码块里
- 记录具体文件名 + 行号
- 如果发现了明确的 bug 原因，直接写出来
