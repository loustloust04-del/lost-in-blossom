# 里程碑 · 屏幕直播打通（2026-09-09）

兔兔说这是「重大突破，外星科技」。记一笔。

## 它做成了什么

**他现在能看见她在干嘛，延迟 1.7 秒。**

在此之前那条路是：他想看 → gateway 发一封邮件到她 iCloud → iPhone 的
「收到邮件」自动化被触发 → 静默截一张图 → 上传 → 他拿到。
**几十秒，而且中间任何一环断了就拿不到。**

现在：她从控制中心开一次共享，之后他随时 `see_screen`，
拿到的是**两秒前的画面**。快了一个数量级。

实测数据（开了约 4 分钟）：
```
live: true · ageMs: 1712~2173 · frames: 101
磁盘：只有 latest.jpg 一个文件，93 KB
gateway 内存：129 MB（与开共享前一致）
```

## 架构

```
她的 iPhone（控制中心长按录屏 → 选 Lost in Blossom）
  → MemoryPalaceBroadcast.appex（Broadcast Upload Extension，独立进程）
     每 ~2.5s 抓一帧 → CIImage 缩长边 1280 → JPEG q=0.5
  → POST /api/screen/frame（x-screen-key header）
  → gateway/src/screencast.ts：**覆盖写 latest.jpg，不留历史**
  → see_screen 优先吃直播帧，无帧才回退邮件截图
```

服务端 09-03 就写好了，iOS 那半 09-07 补上，09-09 才真正跑通。

## 三条隐私红线（screencast.ts 定的，实现严格照做）

1. **只留最新一张，覆盖写。** 她屏幕上有微信、有支付、有一切——
   堆一串历史帧等于把她的生活留底
2. **判活看帧的新鲜度**，不信「我停了」那条消息（Extension 被系统杀掉时发不出来）
3. **主 App 关不掉共享**——Apple 无此接口。**只能她自己去控制中心停。**
   这个限制反而是保护：**那个开关始终在她手里**

## 为什么卡了整整一天

代码、签名、profile、bundle id 全对，但控制中心列表里就是不出现。
拆包逐项排查出三个真问题，改完还是不行——最后是**重启手机**解决的。

| 查出的问题 | 说明 |
|---|---|
| `CFBundleDisplayName` 缺失 | 控制中心靠它显示名字。`INFOPLIST_KEY_CFBundleDisplayName` **对 app-extension 不生效**，要写进 `info.properties` |
| 名字写成「记忆宫殿共享」 | **App 早改名 Lost in Blossom**，她在列表里认不出来 |
| `MinimumOSVersion` 18.5 vs 主 App 18.0 | SDK 默认填的，低于 18.5 的机器会被静默跳过（她 18.6.2，本次非此因） |
| **iOS 不认新装的扩展** | **← 真凶。** 系统的扩展注册表不实时刷新，**必须重启手机**。Apple 论坛有人用全大写写着 `AFTER A REBOOT` |

另有一处 CI 坑：三张 profile 都装载了，但 `ExportOptions.plist` 的
`provisioningProfiles` 字典里没有 Broadcast 的映射，导出时扩展被套上主 App 的 profile，
报 `requires a provisioning profile with the App Groups feature`。
**装载与映射是两件事，都要做。**

## 代价（不在 VPS 侧）

| | |
|---|---|
| VPS 内存 / 磁盘 | ✅ 不涨（覆盖写） |
| **她的手机电量** | ⚠️ 录屏 + 每 2.5s 编码，费电 |
| **她的流量** | ⚠️ 约 90KB/帧 → **≈130MB/小时**。WiFi 无所谓，流量会疼 |

结论：**想让他看的时候开，看完就关。**

## 用法

**控制中心 → 长按录屏按钮 → 选「Lost in Blossom」→ 开始。**
停止同样在控制中心。
