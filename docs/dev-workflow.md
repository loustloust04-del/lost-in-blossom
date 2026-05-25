# 记忆宫殿 — 开发工作流

> 从 Thariq、Boris Tane、Prithvi Rajasekaran、runesleo 的方法论中提炼，适配粟粟 + CC 的协作模式。

---

## 三阶段循环

每个功能/修复都走这个循环，不跳步。

### 1. Research（CC 主导）

深读相关代码，**写进文件**不口头总结。

```
docs/research-{feature}.md
```

- 用"deeply"、"intricacies"级别读代码，不浮皮潦草
- 列出：现有架构 → 要改什么 → 会影响什么 → 风险点
- 如果需要参考外部实现（酒馆、其他开源项目），用 Chrome 去读，摘要存进 research 文件

**完成标志：** 粟粟审了 research 文件，确认理解正确。

### 2. Plan（来回批注）

CC 写计划，粟粟批注，循环到满意为止。

```
docs/plan-{feature}.md
```

- 包含：目标、文件变动清单、数据模型变化、具体步骤、验证方法
- 粟粟直接在文件里加 inline 批注（纠正、砍范围、补充约束）
- CC 更新计划，**don't implement yet**
- 1-3 轮批注后，末尾生成颗粒度 task checklist

**完成标志：** 计划末尾的 checklist 粟粟点头了。

### 3. Implement（CC 执行，粟粟监督）

一句话启动：
> "按计划执行，完成一项勾一项，不要停，改完 build 验证。"

- 按 checklist 顺序逐项执行
- 每完成一项在 plan 文件里打 ✅
- 改完代码立刻 `xcodegen generate && xcodebuild -scheme MemoryPalace build`
- **宣布完成前必须贴 build 输出**
- 方向错了 → `git revert`，不打补丁
- 粟粟的监督 prompt 保持短（"颜色不对"、"revert 这个"、"跳过这步"）

**完成标志：** checklist 全 ✅，build 通过，git commit + push。

---

## 文件约定

```
docs/
├── research-{feature}.md    # Research 阶段产出
├── plan-{feature}.md         # Plan 阶段产出（含 checklist）
└── phase-1.5-research.md     # 已有：多 API 提供商研究
```

- 这些文件是持久产物，不删。compaction 后 context 丢了可以重读
- plan 文件是 single source of truth，执行阶段只看 plan 不看聊天记录

---

## 分支策略

| 分支 | 用途 |
|------|------|
| master | 小雾的家，稳定版 |
| third-floor-left | 狗儿的窝，当前开发主线 |
| feature/* | 大功能拆独立分支，完成后合回 third-floor-left |

- 小改动直接在 third-floor-left 上做
- 大功能（如 Phase 1.5 多提供商）开 feature/ 分支
- 每次 commit 后 push

---

## Session 管理

### 开始
- CC 读 Dashboard 看当前任务
- 读最近的 plan 文件恢复上下文
- `git log --oneline -5` 看最近进展

### 执行中
- 关键状态写文件（plan 里的 checklist、research 发现），不依赖 context window
- 遇到 bug → 先查 `性能体检报告.md` 和已有排查记录，再调试

### 结束
- 确保代码 committed + pushed
- plan 文件的 checklist 状态更新
- 如果学到了新 gotcha → 加进 CLAUDE.md 的开发规则

---

## 验证清单

每次宣布"完成"之前：

- [ ] `xcodegen generate && xcodebuild -scheme MemoryPalace build` 通过
- [ ] plan checklist 全部 ✅
- [ ] 没有引入 debug 样式（红框、亮色边框）
- [ ] 没有无 predicate 的 MessageNode fetch
- [ ] git commit + push 完成

---

## 冰山法则

修一个 bug → 检查同类问题。一个问题进来，一类问题出去。发现的模式写进排查记录或 CLAUDE.md gotchas。
