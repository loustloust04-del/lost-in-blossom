# docs/ 目录索引

> 最后更新：2026-04-12
>
> 按功能域分类，标注状态。Research/Plan 配对列在一起。

---

## 导航

- [路线图](PROJECT_ROADMAP.md) — 接下来做什么、为什么
- [总设计文档](../记忆宫殿-这才是真的总设计文档！.md) — 架构和技术栈
- [开发流程](dev-workflow.md) — Research → Plan → Implement 三步走
- [设计语言](design-dna.json) — 配色/字体/间距 token
- [聊天 UI 设计决策](CHAT_DESIGN.md) — 气泡、布局、交互决策记录

---

## 按功能域分类

### Prompt & 预设系统 ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-prompt-pipeline.md](research-prompt-pipeline.md) | Research | 五层 pipeline 架构分析 |
| [plan-five-tab-pipeline.md](plan-five-tab-pipeline.md) | Plan | 五 Tab pipeline 实现 checklist |
| [research-prompt-system.md](research-prompt-system.md) | Research | Prompt 系统现状 |
| [plan-prompt-tab-redesign.md](plan-prompt-tab-redesign.md) | Plan | Prompt Tab 重设计 |
| [research-persona-system.md](research-persona-system.md) | Research | 人格/预设系统设计 |
| [plan-persona-system.md](plan-persona-system.md) | Plan | 人格系统实现 |
| [research-preset-management-and-sync.md](research-preset-management-and-sync.md) | Research | 预设管理与同步 |
| [plan-three-mode-sync.md](plan-three-mode-sync.md) | Plan | 三模式同步实现 |
| [research-sampling-params-gap.md](research-sampling-params-gap.md) | Research | 采样参数 gap 分析 |

### API & 提供商 ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-api-and-settings.md](research-api-and-settings.md) | Research | API 系统 + 设置页分析 |
| [research-api-management-ux.md](research-api-management-ux.md) | Research | API 管理 UX 研究 |
| [plan-api-tab-redesign.md](plan-api-tab-redesign.md) | Plan | API Tab 重设计 |
| [research-multi-provider.md](research-multi-provider.md) | Research | 多提供商架构 |
| [plan-multi-provider.md](plan-multi-provider.md) | Plan | 多提供商实现 |
| [plan-custom-provider.md](plan-custom-provider.md) | Plan | 自定义提供商实现 |

### 记忆系统 ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-memory-system-v2.md](research-memory-system-v2.md) | Research | AUDN 记忆系统 v2 设计 |
| [plan-memory-system-v2.md](plan-memory-system-v2.md) | Plan | AUDN 实现 |
| [research-memory-panel.md](research-memory-panel.md) | Research | 记忆面板研究 |
| [plan-memory-panel.md](plan-memory-panel.md) | Plan | 记忆面板实现 |
| [Persistent memory systems...md](Persistent%20memory%20systems%20for%20AI%20chat%20applications.md) | 参考 | 外部论文/文章 |
| [Making AI memory feel alive...md](Making%20AI%20memory%20feel%20alive,%20not%20filed.md) | 参考 | 外部论文/文章 |

### 搜索 ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-advanced-search.md](research-advanced-search.md) | Research | 搜索功能研究 |
| [plan-advanced-search.md](plan-advanced-search.md) | Plan | 搜索实现 |
| [research-search-competitors.md](research-search-competitors.md) | Research | 竞品搜索功能对比 |
| [plan-search-qithmiao-features.md](plan-search-qithmiao-features.md) | Plan | 搜索进阶功能 |
| [postmortem-advanced-search.md](postmortem-advanced-search.md) | 复盘 | 搜索功能事后分析 |

### 角色卡 & 世界书 ✅ Phase 1 完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-character-card-worldbook.md](research-character-card-worldbook.md) | Research | TavernCard 格式分析 + 现有架构对接 |
| [plan-character-card-worldbook.md](plan-character-card-worldbook.md) | Plan | Phase 1 全量实现 checklist |
| [plan-worldbook-management.md](plan-worldbook-management.md) | Plan | 世界书管理 Phase 2（编辑/新增/删除） |
| [plan-asset-library.md](plan-asset-library.md) | Plan | 角色卡库 + 世界书独立导入 |
| [plan-memory-toggle.md](plan-memory-toggle.md) | Plan | 对话记忆开关 |
| [postmortem-character-card-worldbook.md](postmortem-character-card-worldbook.md) | 复盘 | 架构文档 vs 实现对照 + 遗留项 |

### 右栏工具抽屉 ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [plan-tool-drawer.md](plan-tool-drawer.md) | Plan | 插件注册制 + 一条 bar + 长按抽屉 |

### 导入 🔄 进行中

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-duplicate-import.md](research-duplicate-import.md) | Research | 导入去重策略 |
| [plan-duplicate-import.md](plan-duplicate-import.md) | Plan | 导入去重实现 |

### iOS 🔄 进行中

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-ios-crossplatform.md](research-ios-crossplatform.md) | Research | 跨平台架构 |
| [plan-ios-crossplatform.md](plan-ios-crossplatform.md) | Plan | iOS 跨平台实现 |
| [research-ios-ux-audit.md](research-ios-ux-audit.md) | Research | iOS UX 审计 |
| [research-ios-white-bands-kelivo.md](research-ios-white-bands-kelivo.md) | Research | iOS 白条排查 |
| [research-ios-white-bands-root-causes.md](research-ios-white-bands-root-causes.md) | Research | iOS 白条根因 |
| [plan-ios-white-bands-kelivo.md](plan-ios-white-bands-kelivo.md) | Plan | iOS 白条修复 |
| [plan-ios-white-bands-root-causes.md](plan-ios-white-bands-root-causes.md) | Plan | iOS 白条根因修复 |
| [research-imprint-dashboard-ios.md](research-imprint-dashboard-ios.md) | Research | iOS 印记面板 |
| [plan-imprint-dashboard-ios.md](plan-imprint-dashboard-ios.md) | Plan | iOS 印记面板实现 |
| [research-ios-import-view.md](research-ios-import-view.md) | Research | iOS 导入界面 |
| [plan-ios-import-view.md](plan-ios-import-view.md) | Plan | iOS 导入界面 |
| [research-ios-font-slider.md](research-ios-font-slider.md) | Research | iOS 字号滑块 |

### 设置 & UI ✅ 已完成

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-settings-redesign.md](research-settings-redesign.md) | Research | 设置页重设计 |
| [plan-settings-redesign.md](plan-settings-redesign.md) | Plan | 设置页实现 |
| [review-settings-redesign.md](review-settings-redesign.md) | 复盘 | 设置页设计评审 |

### 设计参考

| 文件 | 类型 | 说明 |
|------|------|------|
| [research-design-dna-adaptation.md](research-design-dna-adaptation.md) | Research | design-dna 适配方案 |
| [research-ai-frontends.md](research-ai-frontends.md) | Research | AI 前端竞品分析 |
| [design-dna.json](design-dna.json) | 数据 | 设计语言 token |

### 排查记录 📋

| 文件 | 说明 |
|------|------|
| [白条排查记录.md](白条排查记录.md) | macOS 全屏白条排查 |
| [右侧面板样式排查记录.md](右侧面板样式排查记录.md) | 右侧面板样式问题 |
| [性能体检报告.md](性能体检报告.md) | 性能审计报告 |

### 其他

| 文件 | 说明 |
|------|------|
| [爱人灵魂归家-小白手把手指引.docx](爱人灵魂归家-小白手把手指引.docx) | 用户指南（Word 文档）|

---

## 文件统计

- 总文件数：53
- Research 文档：20
- Plan 文档：18
- 复盘/评审：3
- 参考/设计：6
- 排查记录：3
- 其他：3
