# Plan: master 合并 / 分支整理

> 2026-04-28
> 基于：`docs/research-master-merge.md`
> 粟粟决策：「按建议来，没合入的暂时不动」
> **2026-04-28 关档** — 全 stage ✅，master 已 force push 对齐 pristine，13→7 分支 / 9→4 worktree，v1.0.0-build1 tag → d1c946b

---

## 目标

1. 救出未 commit 的 ship 配置 + 4 处 doc 工作
2. master 重新成为主干（追上 pristine-release）
3. 锁住 ship 点：`v1.0.0-build1` tag
4. 删 6 个已合并的 worktree + 分支
5. 未合入分支保持现状（5 个）

---

## Checklist

### 阶段 0：准备（已完成）

- [x] Backup：`~/Desktop/MemoryPalace-bak-2026-04-28-master-merge/` (65M)
- [x] git bundle：`~/Desktop/MemoryPalace-2026-04-28.bundle` (34M)
- [x] research doc 写完

### 阶段 1：抢救未 commit 工作（pristine-release worktree）

- [x] **1.1** commit project.yml 的 Manual signing 配置  
      标题：`build(ios): 锁定 ship 1.0.0(1) 的 Manual signing 配置到 project.yml`
- [x] **1.2** commit `docs/plan-rp-language-cleanup.md` K/L 节  
      标题：`docs: ship 后实地验证 — Review Notes 短版定稿 + ipa 包审计`

### 阶段 2：搬运主仓库未 commit 工作 → pristine-release

- [x] **2.1** 把 5 个 untracked doc 从主仓库（master）拷到 pristine-release worktree：
  - `docs/plan-context-summary.md`
  - `docs/plan-conv-debounce-sort.md`
  - `docs/research-context-summary.md`
  - `docs/research-conv-debounce-sort.md`
  - `docs/research-perf-investigation.md`
- [x] **2.2** commit 这 5 个 doc 到 pristine-release  
      标题：`docs: 归档 04-23 上下文总结 / 对话延迟置顶 / 卡顿调研 plan+research`
- [x] **2.3** 把 master 上的 roadmap B8 "✅？好像已经好了" 标注同步到 pristine 的 roadmap  
      合并到 commit 2.2 里（同一个 docs commit）

### 阶段 3：.gitignore 升级

- [x] **3.1** `.gitignore` 加 `.claude/worktrees/`
- [x] **3.2** commit  
      标题：`chore: gitignore .claude/worktrees/（worktree 自身路径）`

### 阶段 4：把 master 那个独有 commit cherry-pick 进 pristine

- [x] **4.1** cherry-pick `1185dfd` 到 pristine-release（只动 plan-testflight-launch.md，应该零冲突）
- [x] **4.2** 验证：`git log master..pristine-release` 应该不再有 1185dfd 的 inverse

### 阶段 5：push pristine + 打 ship tag

- [x] **5.1** push origin/codex/pristine-release（fast-forward）
- [x] **5.2** 打 tag `v1.0.0-build1` 在 push 完后的某个 commit
  - tag 在 **阶段 1.1 完成之后的 commit**（精确反映 ship 配置）
  - tag message：`苹果 Beta App Review Approved 2026-04-27 — Memory Garden 1.0.0 build 1`
- [x] **5.3** push tag：`git push origin v1.0.0-build1`

### 阶段 6：master 快进到 pristine-release

- [x] **6.1** 切到主仓库（cwd: `/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace`）
- [x] **6.2** 主仓库 working dir 已经清空（roadmap M 已转到 pristine + 5 个 untracked 已搬走 + 1 个 worktree 路径已 gitignore）→ 验证 `git status -s` 是干净的
- [x] **6.3** `git fetch` + `git reset --hard origin/codex/pristine-release` 把 master 拉到 pristine 头
- [x] **6.4** `git push --force-with-lease origin master`

### 阶段 7：删 6 个已合并 worktree + 分支

按顺序删：

- [x] **7.1** `git worktree remove .claude/worktrees/theme-kelivo-settings`
- [x] **7.2** `git worktree remove .claude/worktrees/feature-sticker-system`
- [x] **7.3** `git worktree remove .claude/worktrees/data-backup`
- [x] **7.4** `git worktree remove .claude/worktrees/character-card-worldbook`
- [x] **7.5** `git worktree remove .claude/worktrees/char-macro`
- [x] **7.6** `git worktree remove .claude/worktrees/context-summary`
- [x] **7.7** 删本地分支：
  - `git branch -d codex/theme-kelivo-settings`
  - `git branch -d feature/sticker-system`
  - `git branch -d feature/data-backup`
  - `git branch -d research/character-card-worldbook`
  - `git branch -d feature/char-macro`
  - `git branch -d worktree-context-summary`
- [x] **7.8** 删远程分支（如果想，可选；先不做留作复议）

### 阶段 8：验证

- [x] **8.1** `git branch -a` 看分支清单干净
- [x] **8.2** `git worktree list` 看只剩 4 个：
  - 主仓库 (master, 现 = pristine-release)
  - pristine-release
  - global-backup（未合入）
  - opening-animation（未合入）
- [x] **8.3** `git log master..codex/pristine-release` 应该为空（master == pristine）
- [x] **8.4** `git tag -l v1.0.0-build1` 看 tag 在
- [x] **8.5** `git rev-parse v1.0.0-build1` 看指向哪个 SHA，记录到这份 plan 文档

---

## 风险与回滚

| 阶段 | 风险 | 回滚 |
|---|---|---|
| 1-4 | commit 错 | `git reset HEAD~` 撤销 |
| 5 | push 后想撤 | `git push --force-with-lease origin codex/pristine-release` 配合 reflog |
| 6.4 | force push master 把 1185dfd 推没了 | reflog 找回 1185dfd → 重新 force push 回去 |
| 7 | 删 worktree 出错 | `.git/worktrees/<name>` 内有 metadata，重建 worktree 即可 |
| 7 | 删分支出错 | reflog 30 天可恢复 |
| 全 | 终极崩盘 | `~/Desktop/MemoryPalace-2026-04-28.bundle` 重建整个 repo |

---

## 完成标志

- master 和 pristine-release HEAD 一致
- `v1.0.0-build1` tag 存在并指向 ship commit
- 9 个 worktree → 4 个
- 13 个本地分支 → 7 个
- backup 不动，留观至少 2 周
- roadmap 第八节"分支策略"决策更新为 ✅ 已完成

---

## 不做（明确）

- ❌ 删 origin/master 或重命名分支（master 名字保持不变，只是内容快进）
- ❌ 动 5 个未合入的本地分支（global-backup / merge-import / multi-provider / third-floor-left / opening-animation）
- ❌ 删 origin 端的远程分支（阶段 7.8 暂跳过，下次单独议）
- ❌ rebase / amend 任何已 push 的 commit

---

*粟粟批 → 我执行 → 阶段 8 完成后 ✅ 关档。*
