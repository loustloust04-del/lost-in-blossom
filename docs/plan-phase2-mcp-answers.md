# Phase 2 MCP 接入 — 天奕确认

Q1 imprint-memory 鉴权：**公开访问，不需要 token，authToken 留空**
Q2 工具名前缀：**去掉。UI 只显示 memory_remember 不显示 imprint-memory__memory_remember**
Q3 工具调用 UI：**先做 A（完成后一次性出现卡片）。Phase 3 再优化实时状态**
Q4 MessageNode.segments：**猫自己去代码里查**

## 执行路径（猫的研究结论）

Phase 2.1 — 方案 A：零改 iOS，走 CCBridge，imprint-memory 通过 CC 直接用
Phase 2.2 — 方案 B：hub 扩展，iOS 新增 ImprintMemoryStore + MemoryPanelView

**现在开始写 Phase 2.1 的代码。**
