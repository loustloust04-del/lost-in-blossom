# Research: master 合并 / 分支整理

> 2026-04-28
> 触发：粟粟原话"master 已经失去了 master 的意义变成老版本了"
> 目标：让 master 重新成为主干，锁住 ship 点，清理已合并分支

---

## 一、当前 git 全貌（事实，非推理）

### 1.1 关键 commit

| 标签 | SHA | 时间 | 说明 |
|---|---|---|---|
| **ship 点** | `e41fd12` | 2026-04-25 19:02 | Merge `codex/theme-kelivo-settings` into pristine-release。**1.0.0(1) archive 上传时的 HEAD** |
| pristine-release HEAD | `7770a9b` | 2026-04-28 10:28 | docs(roadmap): 2026-04-28 更新 |
| master HEAD | `1185dfd` | 2026-04-21 04:46 | chore: TestFlight 文案定稿 |

### 1.2 分支拓扑

```
master:           ─── 1185dfd
                  /
          (老 split point) 
                  \
pristine-release: ─── e41fd12 (ship) ─── ... ─── 7770a9b (now)
```

- master 比 pristine-release 多 **1 个独有 commit**：`1185dfd`
  - 改动：只动了 `docs/plan-testflight-launch.md`（+100 / -8）
  - 内容：TestFlight 文案 E1/E3/F4 定稿
- pristine-release 比 master 多 **132 个 commit**（核心代码 + 上架配置 + roadmap 等）

### 1.3 已存在的 tag（保留）

```
pre-kelivo-20260423
sticker-fix-B-works
sticker-fix-final
```

**没有 `v1.0.0-build1`**——本轮要新建。

### 1.4 远程同步状态

- `origin/master` ↔ master：✅ 完全同步，无未 push commit
- `origin/codex/pristine-release` ↔ pristine-release：✅ 完全同步

### 1.5 stash

空。

---

## 二、9 个 worktree 现状

| worktree 路径 | 分支 | 最后活动 | 处置建议 |
|---|---|---|---|
| `/.../MemoryPalace`（主仓库）| master | 2026-04-21 | 保留为主仓库 working tree |
| `.claude/worktrees/pristine-release` | codex/pristine-release | 2026-04-28 | **当前所在 worktree**，保留 |
| `.claude/worktrees/theme-kelivo-settings` | codex/theme-kelivo-settings | 2026-04-25 | 已合入 pristine，可删 worktree + 删分支 |
| `.claude/worktrees/feature-sticker-system` | feature/sticker-system | 2026-04-15 | 已合入，可删 |
| `.claude/worktrees/data-backup` | feature/data-backup | 2026-04-19 | 已合入，可删 |
| `.claude/worktrees/global-backup` | feature/global-backup | 2026-04-19 | **未合入**，保留 |
| `.claude/worktrees/character-card-worldbook` | research/character-card-worldbook | 2026-04-14 | 已合入，可删 |
| `.claude/worktrees/char-macro` | feature/char-macro | 2026-04-19 | 已合入，可删 |
| `.claude/worktrees/context-summary` | worktree-context-summary | 2026-04-19 | 已合入，可删 |
| `.claude/worktrees/opening-animation` | codex/opening-animation | 2026-04-13 | **未合入**，保留待粟粟决策 |

---

## 三、本地分支处置矩阵

### 3.1 已合入 pristine-release（删 worktree + 删分支安全）

```
codex/theme-kelivo-settings   ← 包括 perf 第二轮 + B16-B19
feature/char-macro            ← 已合入
feature/data-backup           ← 已合入
feature/sticker-system        ← 已合入
research/character-card-worldbook ← 已合入
worktree-context-summary      ← 已合入
```

### 3.2 未合入 pristine-release（保留）

```
feature/global-backup        ← 04-19 最后改，未合入
feature/merge-import         ← 04-13 最后改，未合入（B4 标的"已合并"是另一个意义？需复核）
feature/multi-provider       ← 04-10 最后改，未合入
third-floor-left             ← 03-24 最后改，老分支
codex/opening-animation      ← 04-13 worktree active
```

> ⚠️ `feature/merge-import` 在 roadmap B4 标 "✅ 已合并"，但 `git branch --merged` 没把它列入。可能 commit 内容已被改写或 cherry-pick 进 pristine。**建议先 diff 确认再决定删除**。

### 3.3 远程独立分支（不在本地，仅 origin）

```
origin/claude/increase-sidebar-radius-jgHuP
origin/claude/ios-migration-discussion-iVMRn
```

这两个本地不存在，远程也较老，可让粟粟决定是否 origin 端清理。

---

## 四、🔴 未 commit 工作清单（**这是真正卡住直接 force update 的原因**）

### 4.1 pristine-release worktree（当前所在）

#### A. `project.yml` — **关键！必须保留**

```diff
-        CODE_SIGN_STYLE: Automatic
+        CODE_SIGN_STYLE: Manual
+        PROVISIONING_PROFILE_SPECIFIER: "MemoryPalace iOS Distribution"
+        CODE_SIGN_IDENTITY: "Apple Distribution: Jing Lu (GQN42B462A)"
```

- **这是 1.0.0(1) ship 时实际用的签名配置**，但居然没 commit 进 e41fd12
- 意味着如果删掉这份 working dir 改动，下次 archive 会回退到 Automatic 签名 → 仍走 Personal Team → cert 错配
- **必须 commit 到 pristine-release**（合并到 master 之前）

#### B. `docs/plan-rp-language-cleanup.md` — 04-26 早 session 工作

- K 节：补"最终版"短版 Review Notes（已经发给苹果用的那一版）+ 长版备份 + 删句解释
- L 节：新增 ipa 包审计（13 个文件清单 + binary strings 扫描结果）
- 都是 ship 后的实地验证记录，**应该 commit 进版本史**

### 4.2 主仓库（master 分支 working dir）

#### C. `docs/PROJECT_ROADMAP.md` — 一行小改

```diff
-| B8 | 新建楼层页面未适配 iOS | 🟡 中 | iOS | 还是旧 macOS 样式 | 未开始 |
+| B8 | 新建楼层页面未适配 iOS | 🟡 中 | iOS | 还是旧 macOS 样式 | 未开始（✅？好像已经好了） |
```

- 粟粟自己加的标注，**判断 B8 可能已经修了**，要复核
- 单 cherry-pick 到 pristine-release 后逻辑会冲突（pristine 上的 roadmap 已经被 04-28 大改）
- 处置选项见 §六

#### D. 5 个 untracked docs（04-23 创建，未 add）

```
docs/plan-context-summary.md           — 上下文总结（最小版）的 plan
docs/plan-conv-debounce-sort.md        — 对话列表延迟置顶 plan
docs/research-context-summary.md       — 上下文总结 research
docs/research-conv-debounce-sort.md    — 对话延迟置顶 research
docs/research-perf-investigation.md    — 卡顿全面诊断 research
```

- 这些是 Phase 1.5（上下文总结）和 04-19 perf 调研的真东西
- 部分内容（conv-debounce-sort）已经 implement 完，但 research/plan doc 没归档
- **应该 commit 到 pristine-release**（保留历史记录）

#### E. 1 个 untracked 路径

```
.claude/worktrees/opening-animation
```

- 这是 git worktree 自己创建的目录，被 git 当 untracked
- **应该加到 `.gitignore`**：`.claude/worktrees/`

---

## 五、ship commit 推理（为什么是 e41fd12）

### 证据链

1. archive 上传时间：2026-04-26 早 8 点之前
2. e41fd12 commit 时间：2026-04-25 19:02:53（archive 前晚）
3. e41fd12 之后到 04-26 早的 commit 序列：

```
e41fd12  2026-04-25 19:02  Merge kelivo into pristine          ← 候选 ship
a94fd41  2026-04-25 ...    docs(plan): perf 关档（纯 docs）
3d0fd0e  2026-04-25 ...    perf(iOS): ContentView 砍 dead 订阅 ← 实质代码 ⚠️
f2674f3  2026-04-25 ...    perf(probe): ContentView body 探针
729f406  2026-04-25 ...    perf(iOS): applyWallpaper short-circuit
... (kelivo 合入前的 perf 实验链)
```

⚠️ **修正**：实际 ship 的 commit 应该是 `e41fd12` 之后**所有已 push** 但**早于 archive 时刻**的最新 code commit。从时间戳看，`e41fd12` 已经吃了 kelivo 全部 perf 工作。

> **建议执行时**：粟粟自己确认 archive 那个时刻的 HEAD 是哪个，或者用 `git rev-parse codex/pristine-release@{2026-04-26 06:00}` 反查。**保守起见 tag 打在 e41fd12 + 写说明**。

---

## 六、未 commit 工作的处置选项

### 选项 1（推荐，最干净）

1. 把 §4.1 + §4.2 D 的所有未 commit 工作 commit 到 **pristine-release**
2. §4.2 C（master 上 roadmap B8 标注）→ 单独保留：手工把"✅？好像已经好了"这个信号加到 pristine 的 roadmap 里（不走 cherry-pick），合并完一起 push
3. §4.2 E（worktree 路径）→ 加 .gitignore
4. §1.1 master 那 1 个独有 commit（1185dfd plan-testflight 文案）→ cherry-pick 到 pristine
5. 然后 force update master = pristine-release

### 选项 2（更保守，多走一步）

1. 同选项 1 步骤 1-3
2. 不 cherry-pick 1185dfd 到 pristine，而是用 `git merge --ff master` 让 master 拉 pristine 的同时保留 1185dfd（实际上不可行，因为 master 落后 132 commit，必须 merge commit 或 force update）

🔴 选项 2 不成立，回到选项 1。

### 选项 3（暴力）

discard 所有未 commit 工作 → 直接 force update master = pristine-release

❌ 不能用：会丢 project.yml 关键签名配置 + 04-23 那批 research/plan doc。

---

## 七、风险点

| 风险 | 影响 | 缓解 |
|---|---|---|
| force update master 后无法回滚到 1185dfd | 历史丢失 | ① backup 已做（rsync + bundle）② 1185dfd 仍在 reflog 30 天 ③ 如果 cherry-pick 成功，1185dfd 内容已在 pristine |
| 删分支后想恢复 | 可能 | reflog 30 天可找回 SHA；之后只能从 backup 恢复 |
| project.yml 签名配置丢失 | 下次 archive 翻车 | **必须先 commit 这个文件**（选项 1 step 1）|
| 5 个 untracked docs 丢失 | 历史调研断档 | commit 到 pristine 即可保住 |
| force push origin/master | 远程历史重写 | origin/master 当前是 1185dfd（不复杂），force push 影响小；但需要明确告知 |
| `feature/merge-import` 标的 "B4 已合并" 与 `--merged` 不一致 | 可能误删 | 先 diff `git log master..feature/merge-import` 确认内容是否 cherry-pick 进 pristine 再删 |

---

## 八、回滚路径

### 8.1 软回滚（操作没 push）

任何步骤出问题：本地 `git reset` 即可，没动远端。

### 8.2 中等回滚（force-push 后）

1. `git reflog` 找回原 master SHA `1185dfd`
2. `git branch -f master 1185dfd`
3. `git push --force-with-lease origin master`

### 8.3 终极回滚（reflog 也丢了）

1. 从 `~/Desktop/MemoryPalace-2026-04-28.bundle` 重建：
   ```
   git clone /Users/susu/Desktop/MemoryPalace-2026-04-28.bundle restored-repo
   ```
2. 或从 rsync 备份 `~/Desktop/MemoryPalace-bak-2026-04-28-master-merge/` 直接拷贝整个 .git

---

## 九、Plan 阶段要决定的事（粟粟答）

1. **`v1.0.0-build1` tag 打在哪个 commit**？
   - 选项 a：`e41fd12`（kelivo 合入那个 merge commit）
   - 选项 b：在选项 1 step 1 commit 完 project.yml 之后的新 commit（更精确反映 ship 配置）—— **推荐**

2. **未 commit 的 docs（plan-rp-language-cleanup K/L 节、5 个 04-23 研究 doc）commit 标题怎么起**？我提议拆 2 个 commit：
   - `docs: ship 后实地验证 — Review Notes 短版 + ipa 包审计`
   - `docs: 归档 04-23 上下文总结/对话延迟置顶/卡顿调研 plan+research`

3. **roadmap B8 "✅？好像已经好了" 这个标注**怎么处理？
   - a. 简单加一行问号到 pristine 的 roadmap，留待之后核实
   - b. 你今天有空就实地核一下 B8 是否真修了

4. **要不要顺便给 `.gitignore` 加 `.claude/worktrees/` 这条**？

5. **删除哪些 worktree + 分支**：建议删 §3.1 的 6 个（有粟粟一票否决权）

6. **未合入的 5 个分支**（feature/global-backup 等等）保留还是清理？建议先保留，单独走一轮。

---

## 十、提议的执行顺序（具体步骤等 Plan 阶段细化）

1. ✅ Backup（已完成：rsync 65M + bundle 34M）
2. 🚧 commit pristine-release worktree 的 project.yml + plan-rp-language-cleanup.md
3. 🚧 把主仓库 5 个 untracked docs 移到 pristine-release worktree commit
4. 🚧 .gitignore 加 `.claude/worktrees/`
5. 🚧 cherry-pick 1185dfd 到 pristine
6. 🚧 把 master B8 标注手工同步到 pristine roadmap
7. 🚧 push pristine-release
8. 🚧 打 tag `v1.0.0-build1`（位置待定，见 §九 Q1）
9. 🚧 force update master = pristine-release
10. 🚧 push --force-with-lease origin master
11. 🚧 `git worktree remove` §3.1 的 6 个 worktree
12. 🚧 `git branch -d` §3.1 的 6 个分支
13. 🚧 `git push origin --delete` 同步删远程

---

*粟粟 review 这份 doc，回答 §九 的 6 个问题，然后我写 plan-master-merge.md。*
