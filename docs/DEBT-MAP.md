# 坑账 DEBT-MAP

> **唯一真账。** 开新坑先在这里记一笔，填完当场销。别的文档与本账冲突时，以本账为准。
> 立账 2026-07-28：TEST-CHECKLIST 13 项兔兔全验 ✅ 已销账。

## 待验收（真机，一次搞定）
- [ ] **亲密卡**（16:19 后的包才有）：设置→健康开「亲密」→ 面板点心记/取消、note 覆盖语义、详情页点阵 → 开 AI 闸问 Caelum「今天有什么健康记录」他知道 → 口头让他帮记出「♥ 已记下了」→ 反向：问 note 内容他不知道；关闸他完全不知道这卡
- [ ] C2 顺手项：设置→Token 统计，缓存命中率不是 0

## 待写码（按顺序，都是小刀）
1. [ ] 语音设置孤儿挂载：`VoiceSettingsSection` 挂进设置页（同 gates 同款病）+ 兔兔注册 ElevenLabs 填 key
2. [ ] 文件选择器修复（docs/task-fix-file-picker.md）
3. [ ] 双击文本选取（docs/task-text-select-sheet.md）
4. [ ] 思考链 UI 改版（docs/task-thinking-sheet-ui.md）
5. [ ] 切换模型时过滤图片（docs/task-image-model-compat.md）
6. [ ] 花房：罐头回应 → 接真 Caelum（Phase 2 第一小步）

## 待兔兔拍板（各一句话，不用写码）
- [ ] meds.ts 去留：健康已本地化+双向同步，网关侧 meds.ts 退不退役
- [ ] HealthKit 用不用：健康页「今日快照」还没授权，授了 {{health}} 才有步数睡眠
- [ ] 情绪系统（473 行设计、零实现）：这期做不做？不做就移进下面封存区

## 封存（不是债，是以后的甜点）
- 情绪系统实现（EMOTION-SYSTEM-DESIGN.md）
- 花房 Phase 2 全量（写作编辑器等）

## 规矩
每个窗口开工先读本账。挖新坑不记账 = 军法处置 🐰
