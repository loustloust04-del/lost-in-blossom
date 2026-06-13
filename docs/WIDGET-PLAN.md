# Lost in Blossom Widget 实现方案（WIDGET-PLAN）

> 目标：主屏小组件展示最近对话 / 角色卡，点击直达对应会话。
> 约束：iOS 18 deployment target,WidgetKit 全部用 iOS 17/18 已有 API,不碰 iOS 19+。

## 1. 现状与核心障碍

- 数据在 SwiftData unified store:`Application Support/MemoryPalace/unified.store`
  （MemoryPalaceApp.swift:141-146）。**该路径在 App 沙盒内,Widget extension 进程读不到。**
- 项目用 XcodeGen（project.yml）,只有一个 iOS app target,无 App Group entitlement。
- Release 为手动签名（`MP iOS Dev - Bunny` 描述文件）。Widget extension 是独立 bundle id,
  **需要新的 provisioning profile**,否则 GitHub Actions Release 构建直接挂——这是
  本方案最大的工程风险,放在第 7 节单独说。

## 2. 数据共享方案:App Group + JSON 快照（不迁移 SwiftData store）

两条路线对比:

| 路线 | 做法 | 评估 |
|---|---|---|
| A. 整个 unified.store 迁入 App Group 容器,Widget 直接开 ModelContainer | 一次文件迁移 + 两边共享 schema | 风险大:刚做过一次 UnifiedContainerMigration;Widget 进程拉起完整 SwiftData 栈又重又慢;App 与 Widget 并发开同一 SQLite 有锁竞争;schema 改一次 Widget 跟着重编 |
| **B. App 侧写轻量 JSON 快照到 App Group,Widget 只读 JSON（推荐）** | 新增 WidgetSnapshotService | 零迁移风险;Widget 不依赖 SwiftData schema;快照大小可控（几 KB）;代价是多一份冗余数据 |

选 **B**。Widget 是只读展示场景,快照天然够用。

### App Group 配置

- Group ID:`group.com.susu.MemoryPalace`
- project.yml 两个 target 的 entitlements 都加:

```yaml
com.apple.security.application-groups:
  - group.com.susu.MemoryPalace
```

### 快照格式

`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 下写
`widget-snapshot.json` + 封面图 `widget-cover-<profileId>.jpg`（图片单独存文件,
JSON 里只放文件名——WidgetKit timeline entry 有 ~几十 KB 的归档大小预算,
base64 内嵌图片会被系统丢弃）。

```json
{
  "generatedAt": "2026-06-13T01:00:00Z",
  "recentConversations": [
    {
      "id": "conv-uuid",
      "title": "新对话",
      "profileId": "profile-uuid",
      "profileName": "Caelum",
      "profileEmoji": "🐰",
      "lastMessagePreview": "今天过得怎么样？",
      "lastMessageRole": "assistant",
      "updateTime": "2026-06-13T00:58:00Z"
    }
  ],
  "characters": [
    { "id": "profile-uuid", "name": "Caelum", "emoji": "🐰",
      "coverImage": "widget-cover-<profileId>.jpg",
      "description": "..." }
  ]
}
```

- `recentConversations` 取最近 5 条（按 updateTime）,preview 截 80 字符并过
  `ContentCleaner`（去掉 [thinking] 块等标记）。
- 封面图缩到 ~400pt 宽再写文件（角色卡原图可能几 MB）。

### 快照写入时机（WidgetSnapshotService）

| 触发点 | 位置 |
|---|---|
| 助手消息完成（onComplete） | ConversationViewModel.swift:1414 一带 |
| 会话改名 / 新建 / 删除 | markConversationDirty 汇聚处 |
| Profile 增删改 | ProfileManager |
| App 进后台（兜底） | scenePhase == .background |

写完调 `WidgetCenter.shared.reloadTimelines(ofKind:)`。注意**节流**:流式期间不写,
只在 onComplete / 离场时写,避免每个 token 都刷盘。

## 3. Widget target（XcodeGen）

project.yml 新增:

```yaml
  MemoryPalaceWidget:
    type: app-extension
    platform: iOS
    deploymentTarget:
      iOS: "18.0"
    sources:
      - path: MemoryPalaceWidget        # 新目录
      - path: MemoryPalace/Shared/WidgetSnapshot.swift   # 快照模型双 target 共用
    entitlements:
      path: MemoryPalaceWidget/MemoryPalaceWidget.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.susu.MemoryPalace
    info:
      path: MemoryPalaceWidget/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.susu.MemoryPalace.ios.widget
        SWIFT_VERSION: "5.10"
```

主 target `dependencies` 加 `- target: MemoryPalaceWidget`（embed: true）。
共享代码只放纯 Foundation 的快照模型 + 读写工具,**不**把 SwiftData model 拖进 Widget。

## 4. Widget 实现

### TimelineProvider

数据驱动是"App 写快照 → reloadTimelines",不是时间驱动,所以 timeline 策略很简单:

```swift
struct RecentChatProvider: TimelineProvider {
    func placeholder(in: Context) -> RecentChatEntry { .placeholder }

    func getSnapshot(in: Context, completion: @escaping (RecentChatEntry) -> Void) {
        completion(RecentChatEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in: Context, completion: @escaping (Timeline<RecentChatEntry>) -> Void) {
        let entry = RecentChatEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        // .never:只靠 App 侧 reloadTimelines 刷新。
        // 若要"x 分钟前"相对时间戳,改用 Text(date, style: .relative) 让系统自动走字,
        // 仍然不需要多 entry。
        completion(Timeline(entries: [entry], policy: .never))
    }
}
```

### Widget 种类与 family

| Widget kind | family | 内容 |
|---|---|---|
| `RecentChatWidget` | systemSmall / systemMedium | small:当前角色 emoji/头像 + 最新一条消息预览;medium:最近 2-3 条会话列表 |
| `CharacterCardWidget` | systemLarge | 角色卡封面图 + 名字 + 最新消息,氛围感排版（参考 docs/console-design-reference.html 的卡片风格） |
| （可选二期）`accessoryRectangular` | 锁屏 | 最新消息一行 |

可配置性:`AppIntentConfiguration` + `WidgetConfigurationIntent`（iOS 17 API,安全）,
让用户长按 Widget 选择固定展示某个角色,默认"最近活跃"。角色列表用
`AppEntity` + `EntityQuery` 从快照 JSON 读。

### 深链跳转

1. App 注册 URL scheme:Info-iOS.plist 加 `CFBundleURLTypes` →
   `lostinblossom://conversation/<id>`。
2. Widget 侧:整卡 `.widgetURL(URL(string: "lostinblossom://conversation/\(conv.id)"))`;
   systemMedium 列表行用 `Link(destination:)`（systemSmall 只允许 widgetURL）。
3. App 侧:`MemoryPalaceApp` 加 `.onOpenURL`,解析出 conversationId 后复用现成管线——
   post `.notificationNavigationRequested`（userInfo: conversationId）。该管线已含
   冷启动 pending 兜底和 `loadConversation` 完整加载（任务 3 刚修过）,零新逻辑。

### 渲染注意（猫的蠢事预防）

- Widget 进程**不能**用 UIKit window/手势那套,纯 SwiftUI;不要 import 主 App 的
  Theme/UIKit 依赖文件,Widget 内自备一份极简配色。
- iOS 18 下 `containerBackground(for: .widget)` 是必须的（iOS 17 起强制）,忘了会
  在 StandBy/锁屏下出黑底。
- 不用 `.glassEffect`/`MeshGradient`,渐变用 LinearGradient。
- 日期显示用 `Text(date, style:)` 系列,不要自己开 Timer。

## 5. 刷新与预算

- 主刷新路径:App 写快照后 `reloadTimelines`。WidgetKit 对 App 主动 reload 相对宽松
  （非无限,但聊天频率级别没问题）;对 timeline 自刷新预算才是每天 ~40-70 次,
  我们用 `.never` 不消耗这个预算。
- 推送到达时 App 没被拉起,Widget 不会更新——可接受;若要推送也刷新,
  二期用 Notification Service Extension 写快照（同 App Group）再 reload。

## 6. 实施顺序

1. App Group entitlement（两个 target）+ WidgetSnapshot 模型 + WidgetSnapshotService
   写入/节流（纯 App 侧,可先行合入并验证 JSON 内容）
2. XcodeGen 新增 widget target + 占位 Widget（静态文本）,打通 CI 构建/签名
3. RecentChatWidget(small/medium)+ 深链 onOpenURL
4. CharacterCardWidget(large)+ 封面图管线
5. AppIntent 配置(选角色)
6. (二期)锁屏 accessory + 推送刷新

## 7. 风险

- **签名(最大风险)**:Release 手动签名,`com.susu.MemoryPalace.ios.widget` 需要
  单独的 provisioning profile 且 profile 里要带 App Group capability;主 App 的
  profile 也要重新生成(加 App Group)。CI(GitHub Actions)的证书/profile 配置
  需同步更新。**建议第 2 步单独提 PR,确认 CI 绿了再继续。**
- HealthKit entitlement 只在主 App,Widget 不需要,别复制。
- 快照含聊天内容,落在 App Group 容器属设备本地、沙盒保护,与现有 store 同级别;
  但锁屏 Widget(二期)会把消息预览暴露在锁屏上,需要加"锁屏隐藏内容"开关。
- Widget 内存上限 ~30MB:封面图必须用缩小后的文件,禁止加载角色卡原图。
