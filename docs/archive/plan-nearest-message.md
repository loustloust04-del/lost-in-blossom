# Plan: 精确 nearestMessageId

---

- [ ] **1** CardFlowView 加 `BubblePositionKey: PreferenceKey`（`[String: CGFloat]` 字典）
- [ ] **2** 每个 BubbleView 的 background GeometryReader 写入 nodeId → centerY
- [ ] **3** ScrollView content 加 `.coordinateSpace(name: "scrollContent")`
- [ ] **4** `.onPreferenceChange` 收集到 `bubblePositions` 字典
- [ ] **5** `findNearestMessageId(y:)` 改为遍历 bubblePositions 找距离最小的
- [ ] **6** Build + 测试 + commit push
