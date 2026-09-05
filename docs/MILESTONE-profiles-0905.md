# 六张 profile 到手——签名枷锁解除（2026-09-05）

> 兔兔的 app 从此能加扩展了。这一天值得记一笔。

## 一、拿到了什么

粟粟签发，2026-09-05，团队 `GQN42B462A`，**有效期到 2027-09-05**。
设备只含兔兔一台（UDID `00008140-000248E61412801C`）。

| Target | Bundle ID | Profile 名 | App ID |
|---|---|---|---|
| 主 App | `com.susu.MemoryPalace.ios` | `MP iOS Dev - Bunny` | 旧有，重签 |
| 小组件 / 灵动岛 | `...ios.Widget` | `MP iOS Dev - Bunny Widget` | 旧有 |
| 推送改内容 | `...ios.PushNSE` | `MP iOS Dev - Bunny PushNSE` | 旧有 |
| 屏幕共享 | `...ios.Broadcast` | `MP iOS Dev - Bunny Broadcast` | **新建** |
| 分享进来 | `...ios.Share` | `MP iOS Dev - Bunny Share` | **新建** |
| 推送自定义界面 | `...ios.NotifContent` | `MP iOS Dev - Bunny NotifContent` | **新建** |

**六张全部含** `com.apple.security.application-groups = ["group.com.susu.MemoryPalace"]`。
主 App 那张另带 `aps-environment=development`、iCloud、HealthKit、**Family Controls**。

关键 UUID：主 App `2e8f8384-ae13-4a0f-ac71-831137f7a26b`、
Widget `1464eccf-f9df-4767-a405-7224811509b7`。

**证书**（六张共用同一张）：
- 指纹 `A2871819837BB122B69F69E21C73D5559316E62C`
- 证书 ID `VS7JJXFZ3V`，CN `Apple Development: Jing Lu (7TFJ93A25W)`，2026-06-06 签发

## 二、验收方式（两边独立解包，结论一致）

粟粟那边逐张解包核对了 `DeveloperCertificates` 的 SHA-1；
Fable 这边收到后独立又解了一遍：证书指纹 6/6 命中、App ID 各自对应、
设备全是兔兔那台、App Group 六张全带。**不看文件名，只认包里写的。**

## 三、这一路怎么走通的

**卡点定性**：兔兔一直觉得「我和粟粟的签名是一样的，为什么还要要」——她说得对，
App ID / Team / bundle id 确实共用，但 **profile 锁设备也锁 bundle id**，
粟粟那张写的是她的手机，扩展那些更是另一个 bundle id，条上没写就装不了。

**兔兔的那一句问对了**：「为啥不能试试？」
Fable 讲了一晚上道理，全是推断。真去建了个最小小组件推 CI，苹果一句话定案：

```
error: Provisioning profile "MP iOS Dev - Bunny" has app ID
"com.susu.MemoryPalace.ios", which does not match the bundle ID
"com.susu.MemoryPalace.ios.Widget"
```

**这行报错原样发给粟粟，比任何转述都有效。** 实验做在分支上，Deploy 是 `if: success()`，
签名失败不部署，兔兔手上的包全程没动过。

## 四、过程里的两次纠错（都被证据推翻，记下来防重犯）

**Fable 错一**：断言「必须用 App Group，任务书那条自相矛盾」。
错。扩展直传网关不读主 App 数据时**确实不需要** App Group，Caelum 的判断是对的。

**Fable 错二**：让兔兔告诉粟粟「证书勾 `7TFJ93A25W` 那张」。
错。那是 **Team ID 不是证书 ID**——粟粟账号里 5 张开发证书 CN 括号内全是它，
根本无法区分。**认指纹，不认名字。**

**粟粟那边的克儿错一**：推断「CN 是邮箱 = 手工 CSR = 兔兔的证书」。
逻辑本身成立（Xcode 自签的 CN 永远是账号名），但前提错了——
兔兔当初走的是「导 .p12」的懒人法，用的就是粟粟自己那张，CN 是 Jing Lu。
**它明确标了「这是推断不是实证」并写了兜底，这点做得对。**

**破局的是日志**：Fable 从 CI 成功构建里挖出实际执行的命令——

```
Provisioning Profile: "MP iOS Dev - Bunny"
                      (501ef04c-60f4-404d-ba5c-13ee0f3d4769)
/usr/bin/codesign --force --sign A2871819837BB122B69F69E21C73D5559316E62C
```

推断吵不出结果，日志一句话定案。

## 五、⚠️ Family Controls：拿到了但先别用

主 App 那张带了 Family Controls（屏幕使用时间 API），粟粟主动给上的。

**但它挂在和粟粟共用的 App ID 上。** 开发版用不用审核都行，
**可她哪天要上架，苹果会看到这个权限**，就得走 Family Controls 分发审核——
论坛上等一两个月没回音的一片，还有主 App 批了扩展没批卡死的。

**建议：先不启用，等兔兔自己的开发者账号下来再说。**
收益归我们、风险归她，这不公平。**但必须让粟粟知道它在里面。**

## 六、下一步（接线，还没做也还没验）

- [ ] 6 张 profile 进 GitHub secrets（现在只有一条 `MOBILEPROVISION_BASE64`）
- [ ] CI `build-ios.yml`：安装步骤改成装多张
- [ ] CI `ExportOptions.plist`：`provisioningProfiles` 现在只有主 App 一条映射，每个扩展加一条
- [ ] `project.yml`：主 App 的 entitlements 加 App Group；新扩展 target 各自配 profile
- [ ] 先只上小组件（兔兔最想要的），CI 绿了再下一刀

**注意**：`compile-check` 用 `CODE_SIGNING_ALLOWED=NO`，**签名问题它一律绿**。
这条线上真正的判官是 `Build iOS` 的 export 那步。

## 七、维护

- **换手机 / 加设备 → 6 张全部重签**（profile 锁设备）
- **2027-09-05 到期 → 找粟粟重签一轮**
- `.mobileprovision` 文件**不进 git**
- 兔兔在攒钱开自己的开发者账号（¥688/年）。换过去之后 bundle id 要变，
  数据迁移方案见 `plan.md`（SwiftStore 那条路），**且服务器上没有对话备份，
  导出备份这件事本身就该做**

---

*Fable，2026-09-05。兔兔问「为啥不能试试」的那一下，是这件事的转折点。*
