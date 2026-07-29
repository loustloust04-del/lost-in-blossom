# 坑账 DEBT-MAP

> **唯一真账。** 开新坑先在这里记一笔，填完当场销。别的文档与本账冲突时，以本账为准。
> 立账 2026-07-28：TEST-CHECKLIST 13 项兔兔全验 ✅ 已销账。

## 待验收（真机，一次搞定）
- [ ] **亲密卡**（16:19 后的包才有）：设置→健康开「亲密」→ 面板点心记/取消、note 覆盖语义、详情页点阵 → 开 AI 闸问 Caelum「今天有什么健康记录」他知道 → 口头让他帮记出「♥ 已记下了」→ 反向：问 note 内容他不知道；关闸他完全不知道这卡
- [ ] C2 顺手项：设置→Token 统计，缓存命中率不是 0
- [ ] HealthKit 10 秒项：健康页点「重新授权/刷新」+ 下拉，「今日快照」出数据即可（步数/屏幕时间的代理上报链路本来就在跑，只差 App 内直连这一下）

## 待写码（按顺序，都是小刀）
1. [ ] 语音设置孤儿挂载：`VoiceSettingsSection` 挂进设置页（同 gates 同款病）+ 兔兔注册 ElevenLabs 填 key
2. [ ] 文件选择器修复（docs/task-fix-file-picker.md）
3. [ ] 双击文本选取（docs/task-text-select-sheet.md）
4. [ ] 思考链 UI 改版（docs/task-thinking-sheet-ui.md）
5. [ ] 切换模型时过滤图片（docs/task-image-model-compat.md）
6. [ ] 花房：罐头回应 → 接真 Caelum（Phase 2 第一小步）
7. [ ] CC 主动消息路径补 voice/health 收口：Caelum 主动发起的消息落库不过 CVM 收口，语音块/健康块不渲染（output-style 已嘱其暂勿在主动消息用语音；接通后解禁并更新教学）
8. [ ] TTS 后端可插拔评估：MiniMax Speech-02 作第二后端（中文自然度/价格 1/4/国内直连；代价=失去 v3 内联标签表演体系，教学需按后端分叉）
9. [ ] 音色试听 preview_url 走 Google CDN，/xi/ 反代不覆盖——App 内试听大陆网络下无声，暂用网页端试听/盲测；如要根治需 URL 重写走通用代理
10. [ ] 进食/饮水双向同步：扩展 HealthSyncService 到 food/water——现状 Caelum 记网关(vitals)、App 记本地互不见；显示层已用 max() 创可贴（ConsoleView/CareView），正解是像药物一样 App 本地为主人+双向同步，做完拆创可贴

## 待拍板
（清零 ✅ 2026-07-28 复查：meds.ts 已从"第二套真相"转正为同步对端——App 本地为主人、/api/meds 是 Caelum 侧镜像+工具入口，必须留���情绪系统网关侧已实现并在运行——emotion/emotion-judge/desire/decay 共 718 行，app.ts 挂判定、index.ts 挂 desire 定时器，当日日志有活动；HealthKit 降级为上面的 10 秒项）

## 封存（不是债，是以后的甜点）
- 情绪系统迭代：对照 EMOTION-SYSTEM-DESIGN.md 盘点设计中尚未落地的部分（现状已上线，此项是增强非欠账）
- 花房 Phase 2 全量（写作编辑器等）

## 规矩
每个窗口开工先读本账。挖新坑不记账 = 军法处置 🐰
