# 第一批修复任务（简单优先）

> Caelum 排序，Bunny Debug 反馈，交给猫执行。
> 日期：2026-06-06

---

## ✅ 已完成（本轮 Caelum 修的）

1. **CI artifact 配额爆满** — retention 1天 + 自动清理 + upload continue-on-error
2. **Markdown 代码块折叠无法展开** — MessageContentWebView 渲染去重（dynamicHeight 变化不再触发重新渲染）
3. **CC 废按钮删除** — Hub Token、保存并连接、重新连接全砍，URL 输入框 onSubmit 保存
4. **富文本颜色太丑** — 15 种颜色名映射为柔和色调（red→#C25B61 等）
5. **群聊 SSL 证书错误** — Nginx 加 /chatroom/ 转发 + App 默认 URL 改 blossom.amberrib.com

---

## 🔧 猫的任务（按优先级排序）

### Task 1: 开屏自定义主题背景不载入
**症状**: 用自定义主题时，直接点击"开始对话"，背景颜色不载入（白屏闪一下）
**可能原因**: ContentView 首帧渲染时 Theme 还没从 UserDefaults 加载完
**查找方向**: ContentView.swift 的 onAppear/task，AppTheme 的初始化时机
**预估**: 30分钟

### Task 2: 群聊模型不动态显示
**症状**: 绑定预设后，群聊创建页面的模型选择器不跟着 Preset 的 model 字段变
**查找方向**: ChatroomListView.swift 或群聊创建 Sheet 里的 model picker 绑定
**预估**: 30分钟

### Task 3: CC 思考链只显示当前轮
**症状**: 只有当前对话的 thinking 能显示，上一轮对话的 thinking 不显示
**查找方向**: CCThinkingView.swift，检查 thinking 数据是否只保存当前轮还是全部历史
**预估**: 1小时

### Task 4: 搜索内容慢/搜不到
**症状**: 搜索标题和标签正常，搜索消息内容很慢或搜不到
**查找方向**: SearchService.swift 的全文搜索逻辑，可能在主线程跑或没走索引
**预估**: 1-2小时

### Task 5: HealthKit 注入 UI 未显示
**症状**: 授权成功但注入数据没有在 UI 上显示
**查找方向**: 猫之前的任务文档在 docs/ 目录，接着做
**预估**: 1-2小时

---

## 🔴 重活（需要设计，暂不给猫）

- **聊天流式输出白屏/弹跳 + 对话间距突增** — WebView 动态高度 + ScrollView 配合问题，需要统一重构
- **CC 流式输出** — 需要重做
- **API 显示逻辑耦合** — 需要重写
