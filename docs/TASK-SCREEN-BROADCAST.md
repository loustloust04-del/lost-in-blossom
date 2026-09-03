# 任务：屏幕共享（Broadcast Extension）

> 兔兔发起。做完之后 Caelum 能看到她手机的实时画面，而不是等一张邮件触发的截图。
> **只写代码，不改 mp-cc 会话、不重启 hub。**

---

## 为什么要做

现在 `peek_screen` 的链路是：
```
他调工具 → 网关发邮件 → 她手机的快捷指令收到 → 截一张图 → 上传 → 他看到静态图
```
六个环节，慢，而且今年八月坏过好几次（邮件延迟、自动化没触发、UA 问题）。

目标：**她主动开一次共享，之后他随时能看到几秒前的画面**，不依赖邮件和快捷指令。

---

## 硬约束（先读这三条，不然会白做）

1. **iOS 不允许 App 自己开始录屏。**
   必须兔兔从控制中心长按录屏按钮、选中我们的 App、点「开始直播」。
   没有任何 API 能代劳——这是系统级隐私限制。所以做的是「常驻共享」，不是「他主动窥屏」。

2. **Broadcast Extension 内存上限 50MB，超一字节即被系统杀掉。**
   不能在里面攒帧、不能用大的图像缓冲、不能引入重依赖。

3. **不能用 App Group。**
   证书蹭的是粟粟的（Team `GQN42B462A`），建 App Group 要去 Apple 后台注册，会麻烦到她。
   → **Extension 直接把帧 POST 到网关**，不回主 App。

---

## 方案：连拍版（不做实时视频流）

每 2–3 秒抓一帧，压成 JPEG 直传网关。他调工具时拿到最近一帧。

**为什么不做 WebRTC 实时流**：工程量大一个量级（信令、NAT 穿透、编解码），
而他的使用场景是「看一眼她在干嘛」，几秒延迟完全够用。

---

## 要做的四件事

### 1. 新建 Broadcast Upload Extension target

`project.yml` 里加（与 `MemoryPalaceIOS` 同级）：

```yaml
  ScreenBroadcast:
    type: app-extension
    platform: iOS
    deploymentTarget:
      iOS: "18.0"
    sources:
      - path: ScreenBroadcast
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.susu.MemoryPalace.ios.broadcast
        DEVELOPMENT_TEAM: GQN42B462A
        INFOPLIST_FILE: ScreenBroadcast/Info.plist
        CODE_SIGN_ENTITLEMENTS: ScreenBroadcast/ScreenBroadcast.entitlements
    dependencies:
      - sdk: ReplayKit.framework
```

并在 `MemoryPalaceIOS` 的 `dependencies` 里加 `- target: ScreenBroadcast`（embed 进主 App）。

`ScreenBroadcast/Info.plist` 关键字段：
```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.broadcast-services-upload</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).SampleHandler</string>
  <key>RPBroadcastProcessMode</key>
  <string>RPBroadcastProcessModeSampleBuffer</string>
</dict>
```

### 2. `ScreenBroadcast/SampleHandler.swift`

继承 `RPBroadcastSampleHandler`，只处理 `.video`：

- **限流**：记 `lastSentAt`，不到 2.5 秒直接 return（**这是内存不炸的关键**）
- **缩放**：`CVPixelBuffer` → `CIImage` → 缩到长边 720 → JPEG quality 0.5
  - 用 `CIContext` 且**复用同一个实例**（每帧新建会炸内存）
  - `context.jpegRepresentation(of:colorSpace:options:)`
- **上传**：`URLSession.shared.uploadTask`，POST 到
  `https://blossom.amberrib.com/api/screen-frame?key=bunny-lib-2026`
  - `Content-Type: image/jpeg`，body 就是 JPEG bytes
  - **失败就丢弃，不重试、不排队**（排队 = 攒内存 = 被杀）
- `broadcastStarted` / `broadcastFinished` 时各 POST 一次状态到
  `/api/screen-frame/state`，让他知道共享开着还是关了

**内存红线**：整个 handler 不持有任何帧、不建数组、不写文件。

### 3. 网关：`gateway/src/screenshare.ts`

```
POST /api/screen-frame        # 收 JPEG，覆盖写 data/screen/latest.jpg，记 mtime
POST /api/screen-frame/state  # {active:true/false}，落 data/screen/state.json
GET  /api/screen-frame/latest # 给 App 侧调试用
```
- **只保留最新一帧**，覆盖写，不留历史（省磁盘、也少一份隐私）
- 认证复用现有的 `verifyEventToken`（Bearer 或 `?key=`，同 `/api/peek`）

工具改造（`gateway/src/peek.ts` 的 `see_screen`）：
- 若 `state.active` 且 `latest.jpg` 在 **10 秒内** → 直接返回这一帧，**不再发邮件**
- 否则走原来的邮件触发链路（保底，别删）
- 新增 `screen_share_status` 工具：告诉他共享开着没、最近一帧多久前

### 4. App 侧一个小入口

设置页加一行「屏幕共享」，内容是**说明 + 状态**：
- 说明：怎么开（控制中心 → 长按录屏 → 选 Lost in Blossom → 开始直播）
- 状态：从 `/api/screen-frame/state` 拉，显示「共享中 / 未开启」
- 可以放个 `RPSystemBroadcastPickerView`（iOS 提供的按钮，点了直接弹选择器，省得她翻控制中心）

---

## 验收

1. 兔兔从控制中心开启共享 → 网关 `data/screen/latest.jpg` 开始每 2-3 秒更新
2. Caelum 调 `see_screen` → **秒回**，拿到几秒前的画面，日志里没有发邮件的记录
3. 她停止共享 → `state.active=false`，`see_screen` 自动回落到邮件链路
4. **连续共享 10 分钟不被系统杀**（内存没超）

---

## 提醒下一个做这个的人

- **VPS 上编译不了 Swift**，只能靠 CI。大改动一次改完再推，别一处一处试。
- 加了新 target 之后 CI 可能要调（`.github/workflows/` 里两个 workflow 都用 xcodebuild）。
- 喊兔兔装包前**先核对** `/var/www/lib-dl/LostInBlossom.ipa` 的 mtime 晚于目标 commit 的 CI 完成时间。
- 这个功能能看到她手机上的一切（微信、支付、所有东西）。
  **默认不常开**，她开一次算一次；`state.active` 要如实反映，别让她以为关了其实还在传。
