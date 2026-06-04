# 喂猫指令（最终版）— Day 10

> 一个任务一个 commit。做完测再做下一个。编译额度省着用。

---

## App 代码改动（攒一次编译）

### P0

**1. 思考链 UI 重设计**
📄 `docs/task-thinking-ui-redesign.md`
📁 `CardFlowView.swift`
sheet弹出 → 内联折叠展开。修空白框bug。

**2. API 选择器加空选项**
📄 `docs/task-api-picker-cc-default.md`
📁 `APISettingsTab.swift`
Picker加空选项，选了显示CC+收藏模型。OR收藏逻辑不碰。

**3. 正则编辑器适配**
📄 `docs/task-fix-regex-editor-layout.md`
📁 `RegexScriptEditor.swift` 第118行
width:460 → maxWidth自适应。

**4. 删A社MCP UI**
📁 `APISettingsTab.swift`
Anthropic提供商下的"MCP工具服务器"整块删掉。

### P1

**5. Projects 管理**
📄 `docs/task-projects-management.md`
数据模型 → CRUD UI → 对话归属 → 项目指令注入 → 侧边栏列表。

**6. Artifacts 画布**
📄 `docs/task-artifacts-canvas.md`
WKWebView渲染HTML/CSS/JS。代码块识别 → Artifact卡片 → sheet渲染。做不成就砍。

---

## VPS 端

**7. CC思考链 stop hook**
📄 `docs/task-cc-thinking-to-app.md`
extract-thinking.sh + hub.ts加thinking文件检测 + CC settings加hooks。

---

## 已完成（不需要做）

- ✅ WebSocket按钮修复（commit 08edfd1，代码已改）
- ✅ 富文本正则修复（猫之前改好，分支待merge）
- ✅ Supergateway crash修复（已上线）
- ✅ CC流式hub.ts（代码改好，hub重启后生效）

---

## 猫的纪律

- 一个任务一个commit
- App改动攒到一次编译
- macOS runner每分钟10x扣费，省着用
- 富文本修复的分支先merge到main再做新任务
