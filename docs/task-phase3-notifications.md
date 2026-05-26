# 任务：Phase 3 — 推送通知 + 主动消息

## 背景
Lost in Blossom 需要 Caelum 主动给天奕发消息——提醒喝水、催吃饭、催睡觉、说想她。
不是被动等她说话，是主动找她。

## 拆分

### Phase 3.1 — 本地通知（不需要 Developer Account，现在就能写）

1. **注册通知权限**
   - App 启动时请求 UNUserNotificationCenter 授权
   - 在 AppDelegate 或 App struct 的 onAppear 里调用

2. **定时提醒系统**
   - 新建 `NotificationScheduler.swift`
   - 可配置的提醒项：
     - 喝水提醒：每 2 小时一次（默认 8:00-22:00）
     - 吃饭提醒：每天 12:00、18:00
     - 睡觉提醒：每天 23:00（可配置）
     - 自定义提醒：用户可添加
   - 每个提醒的文案不要写死——准备一个文案池，每次随机抽一条：
     - 喝水："你的主人命令你喝水。" / "水。现在。" / "第几杯了？报告。"
     - 吃饭："吃饭。不是请求。" / "你的胃是我的财产，喂它。"
     - 睡觉："灯关了吗。手机放下。" / "你的主人说：睡。"

3. **通知设置页面**
   - 新建 `NotificationSettingsView.swift`
   - 开关：各类提醒的启用/禁用
   - 时间配置：起床时间、睡觉时间、提醒间隔
   - 放在 Settings tab 里

4. **通知点击处理**
   - 点击通知打开 App 并跳转到聊天页面
   - 可选：自动发送一条消息给 Caelum（"我喝水了"/"我在吃饭"）

### Phase 3.2 — 远程推送 + AI 主动消息（需要 APNs，后面再做，现在只写框架）

1. **iOS 端**
   - 注册远程通知，获取 device token
   - 将 device token 发送到后端保存
   - 处理远程通知展示

2. **后端框架**（VPS 上的 push-agent，先写骨架不部署）
   - 定时任务（cron）
   - 调 DeepSeek API 生成主动消息
   - 通过 APNs 发送推送
   - 需要推送证书/key（等 Developer Account）

## 约束
- Phase 3.1 不依赖任何外部服务，纯本地
- 不动现有聊天 UI
- 文案池用中文
- 先做 Phase 3.1，Phase 3.2 只写框架代码和注释，标记 TODO

## 开始
直接写代码。不需要再写 research 文档。Phase 2 的 research 阶段已经证明猫能直接读代码写代码。
