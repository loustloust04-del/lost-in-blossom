# API Key 存不住 — 诊断报告 + 业界顶尖存储方案

范围：只回答「Mac 上存一个 API Key，重启后还在」。不扩大。

---

## 一、哪里出了问题（已坐实，非推测）

**存储代码本身没错——存的地方（Keychain）是对的。坏的是 app 没有稳定的签名身份。**

证据链：
| 证据 | 结论 |
|---|---|
| `codesign -dv 记忆宫殿.app` → `Signature=adhoc`、`TeamIdentifier=not set`、entitlements 为空 | macOS 包是 **ad-hoc 签名**，没有稳定身份 |
| 钥匙串里查得到写入的条目（`custom-b2827fa5`） | **写得进** |
| 你实测：重启后清空，每次重输 | **读不回** |
| iOS（有 `DEVELOPMENT_TEAM=GQN42B462A` 稳定身份）正常持久 | 差异就在「签名身份稳不稳」 |

**机理**：当前 `KeychainStore` 用的是 **legacy（文件型）钥匙串**。legacy 钥匙串给每条凭证挂一个 ACL，**绑死在创建它的那个代码签名上**。ad-hoc 签名每次 build 的身份会变 → 下次启动签名对不上 → `SecItemCopyMatching` 拿不回条目（`getAll()` 静默返回空）→ app 以为「没存过」→ 你重输。

> 一句话：**写进去的锁，只有「写它的那把签名钥匙」能开；ad-hoc 每次换钥匙，所以再也开不开。**

---

## 二、业界顶尖方案是什么

**Keychain Services + Data Protection Keychain + 稳定签名身份。**
这就是 Apple 自家 app、1Password、所有正经 macOS 应用存密钥的标准做法。不是「多存几个地方」，不是「自己加密文件」——那些是降级 workaround，安全性更低还要自己管加密密钥（密钥又得存哪？绕回钥匙串）。**正道是把钥匙串用对，而用对的前提是 app 有稳定身份。**

落地只有两处改动，范围极小：

### 改动 1：给 macOS 包稳定签名身份（`project.yml`）
用你**已经在 iOS 上验证过、能正常工作的同一个 team**：
```yaml
# MemoryPalace (macOS) target，settings.configs:
Debug:
  CODE_SIGN_STYLE: Automatic
  DEVELOPMENT_TEAM: GQN42B462A
Release:
  CODE_SIGN_STYLE: Automatic
  DEVELOPMENT_TEAM: GQN42B462A
```
自动签名会注入稳定的 `application-identifier`（team+bundle）。从此本地 rebuild 也用「Apple Development: Jing Lu」这同一把钥匙签 → 身份不再变。

### 改动 2：`KeychainStore` 切到 Data Protection Keychain
所有 query（`set`/`get`/`getAll`/`remove`/`allAccounts`/`anyQuery`）统一加：
```swift
kSecUseDataProtectionKeychain as String: true
kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
```
这让 macOS 的钥匙串行为**和 iOS 完全一致**：条目按 `application-identifier` 锁，**不再绑 per-build 签名 ACL** → 跨 rebuild、跨重启都稳。

> 注：改动 2 依赖改动 1。Data Protection Keychain 需要 `application-identifier` entitlement（来自 team 签名）；纯 ad-hoc 无 entitlement 会返回 `errSecMissingEntitlement`。**所以签名身份是地基，绕不开。**

---

## 三、回答你的两个质疑

**Q：「别人没有 team 签名怎么办？」**
team 是 **你（开发者）** 签包用的，签进 app 后对**所有下载用户都是同一个稳定身份**。用户运行的是你签好的包，**他们不自己 build，不需要 team**。只有「开发者本地 ad-hoc build」会身份不稳——而改动 1 配上 team 自动签名后，连你本地 build 都稳了。所以这方案对用户零负担。

**Q：「我没勾 iCloud Keychain 同步，是不是没存进钥匙串？」**
不是。那个开关只管「key 要不要跨设备同步到 iCloud」。**关着，key 照样存本机钥匙串。** 你存不住跟这个开关无关，纯粹是上面的签名 ACL 问题。

---

## 四、一次性副作用（要知道）
切到 Data Protection Keychain 后，旧 legacy 条目在新存储里查不到 = 视觉上「现有 key 全没了」，**需重输一次**，之后永久持久、再不丢。

---

## 五、附带发现（不在本次范围，仅记录）
存 key 后「已保存的 API」列表当场不刷新，是另一个独立小 bug（`ProviderManager.apiKeyCache` 标了 `@ObservationIgnored`，`setApiKey` 不触发重渲染）。**与持久化无关**，要不要顺手修由你定，不影响本报告主结论。

---

## 六、结论
- **病灶**：ad-hoc 签名 + legacy 钥匙串 ACL，不是你的存储逻辑。
- **顶尖解**：Data Protection Keychain + 稳定 team 签名（= iOS 现在的做法搬到 macOS）。
- **不推荐**：自管加密文件 / 多处冗余——降级方案，非业界标准。

---

## 七、实际落地（2026-06-13）—— 为什么没走完整 DP Keychain

落地时发现：macOS 上 Data Protection Keychain 要拿到稳定 access group，必须有 `keychain-access-groups`/`application-identifier` entitlement → 触发 **Mac App Development 描述文件** → 要求**把这台 MacBook Air 注册进开发者账号**（`error: Device "MacBook Air" isn't registered`）。这是额外 provisioning 摩擦，粟粟明确想避开。

**关键认知**：病根是「签名不稳」，不是「用了 legacy keychain」。legacy 钥匙串的条目 ACL 绑在签名的 **designated requirement** 上——
- ad-hoc 的 DR 是 `cdhash H"…"`，每次 build 变 → 丢。
- Developer 证书的 DR 基于 **team + bundle + Apple anchor**，**跨 rebuild 稳定** → 条目持久。

所以**只要签名从 ad-hoc 换成稳定 Developer 签名，连 legacy 钥匙串都不再丢**，不需要 DP keychain、不需要描述文件、不需要注册设备。

### 实际改动（极小）
- `project.yml`：macOS target 加 `DEVELOPMENT_TEAM: GQN42B462A` + `CODE_SIGN_STYLE: Automatic`（Debug+Release）。**仅此一处。**
- `KeychainStore.swift`：**保持原样**（DP keychain 改动已回退——无 access group entitlement 时它反而会让保存报 `errSecMissingEntitlement`）。

### 验证状态
- ✅ `BUILD SUCCEEDED`
- ✅ 签名验证：`TeamIdentifier=GQN42B462A`，非 ad-hoc（原来是 `Signature=adhoc / TeamIdentifier=not set`）。
- ⏳ 端到端「重启后 key 还在」需真人 GUI 实测（见下）。

### 一次性代价（不变）
旧 ad-hoc 签名写的钥匙串条目锁在旧 DR 上，新 Developer 签名读不到 → **重输一次** key，之后用新签名写的条目永久持久。首次访问可能弹一次钥匙串授权，点「始终允许」。

### 真人验收步骤
1. 跑**这个新 build**（确认不是旧的 ad-hoc 包在跑）。
2. 设置→API→输 key→保存。
3. 完全退出 app（⌘Q），重新打开。
4. key 还在 = 成功。

### 日后可选升级
若哪天想要完整 DP Keychain（跨设备 iCloud Keychain 同步更顺、更现代）：把 Mac 注册进开发者账号 + 加回 `keychain-access-groups` entitlement + KeychainStore 加回 `kSecUseDataProtectionKeychain`。非必需，当前方案已解决「存不住」。

---

## 八、探针实测后的真根因修正（2026-06-13，最终）

上面第七节把病根归在「签名不稳」——**实测探针证明那只是次因，主凶是 `getAll()` 的查询 bug**。教训：早该上探针，别先信理论链。

### 探针数据（落盘 keychain-probe.log）
```
GETALL status=-50                          ← 批量读钥匙串失败(errSecParam)
SELFTEST prevRoundtrip=rt-1781335329       ← 单条 get() 跨重启读得回！钥匙串本身正常
SET account=siliconflow addStatus=0        ← 写入成功
```

### 真正的三层根因（按杀伤力排序）
1. **主凶 `getAll()` 返回 -50**：原查询同时用 `kSecMatchLimitAll` + `kSecReturnData`，**macOS legacy 钥匙串不支持一次性返回所有条目的 data**，直接 errSecParam → `warmUpApiKeyCache` 拿空字典 → 启动后全部 key 像被清空。**这才是「每次重启重输」的直接原因**，且与签名无关。iOS 支持该组合，故 iOS 正常——这才是真正的平台不对称根源。
2. **次因 签名不稳**：ad-hoc 下重 build 会让 legacy ACL 失效（影响开发者重 build 场景），稳定 Developer 签名修掉。
3. **修主凶时引出的狂弹**：把 `getAll` 改成逐条 `get()` 后，旧 ad-hoc 签名创建的「外来」条目（如 `custom-b2827fa5`）读 data 需弹 login 密码框 → 启动主线程被一串模态框堵死卡死。

### 最终改动（KeychainStore.swift）
- `getAll()`：批量查询**只取 account 名（去掉 `kSecReturnData`）→ 逐条 `get()` 取值**，绕开 -50。
- 逐条读时 `#if os(macOS)` 包 `SecKeychainSetUserInteractionAllowed(false)/(true)`：外来条目静默失败被跳过，自己写的条目照常静默读出，**不弹、不卡**。
- 配合第七节的稳定签名，三层全堵。

### 验证（真人实测通过）
- ✅ build 通过；✅ 探针 `prevRoundtrip` 证明单条往返持久；✅ 粟粟实测「一打开 key 就在」，不弹不卡。

### 残留技术债
- 钥匙串里旧 ad-hoc 外来条目（`custom-b2827fa5` 等）仍在，现被静默跳过、无害；日后可做一次性清理。
- `SecKeychainSetUserInteractionAllowed` 在 macOS 10.10 起 deprecated（仍可用），有编译 warning。彻底现代化要走 DP Keychain（见第七节升级路径）。
