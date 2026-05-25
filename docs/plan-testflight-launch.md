# TestFlight 上架 Checklist

> 目标：把 iOS 版本发到 TestFlight，让朋友能装上用。**不做正式 App Store 上架**。
> 最后更新：2026-04-26
> 
> 这份是"非代码线"的 checklist——和你手上的代码修复（对话页打磨 / B6 思考链 / 翻页动画收尾 / B2 搜索排序 / E6 回顶回底）**并行跑**。

---

## 📝 2026-04-26 进度摘要（pristine-release 分支首次过审）

**当晚搞定的**：
- B2 cert 终于装上（manual signing scoped to MemoryPalaceIOS target，Apple Distribution: Jing Lu (GQN42B462A)）
- Archive 1.0.0(1) 用 GQN cert 成功签名
- Upload to App Store Connect 成功（Build status: Complete，processing 不到 5 分钟）
- ASC App record 自动创建（**App Name "记忆花园"**，因为"记忆宫殿"被占；Bundle ID 仍是 com.susu.MemoryPalace.ios，PRODUCT_NAME 仍是"记忆宫殿"，桌面图标名不变）
- Internal Testing group 建好（Susu Internal，自动分发 enabled）
- iPhone 17 Air 装上 + 自测通过 ✅（不崩，能开能用）
- ipa 包内容审计完成（详见 `plan-rp-language-cleanup.md` L 节）：repo 根的 `.git` / `docs/` / `CLAUDE.md` / 总设计文档全部不在 ipa 里；binary strings 扫到 5 条 SillyTavern 协议相关字段（`nsfw` / `jailbreak` / `TavernCard` / `TavernCardError` / `com.susu.MemoryPalace.apikey`），都是字段名/类名非 UI 文案，Beta Review 风险低
- Review Note 文案修订：从长版（一连串 No XXX 否定句）改成短版（只陈述"是什么"），避免"过度自证清白"反引审核员关注。短版定稿见 `plan-rp-language-cleanup.md` K 节

**当晚后续（2026-04-26 早 8 点）**：
- ASC Test Information 全部填完 + Save ✅
  - Feedback Email: `linnea.sketchbook@gmail.com`
  - Contact: Jing Lu / +8613755081127 / 1115899476@qq.com
  - Review Notes: 短版定稿（见 `plan-rp-language-cleanup.md` K 节）
  - **Sign-in required: 不勾**（BYOK 模式，无账号系统）
- Privacy Policy URL ✅
  - 用 GitHub Gist 公开托管（中英双语）
  - URL: `https://gist.github.com/replica882/97c7b3d9b0b930f05ee5cc4cbb288575`
  - 后续改内容直接 Edit gist，URL 不变
- External Testing group "Friends Beta" 建好 ✅（Public Link 已开启）
- **Submit for Beta App Review**：Add Build 时 ASC 自动合并送审 → Status: **Waiting for Review** 🟡

**当前堵塞点**：等苹果 Beta App Review（官方 24-48h，结果会发邮件到 Apple ID 邮箱）

**审过后要做的**：
1. Build status 变 **Ready to Test** 🟢
2. Friends Beta → Testers → Invite Testers → Public Link → 复制
3. 链接发朋友 + 给登录教程（F4）
4. 提醒朋友：**自带 API Key**（OpenAI / Anthropic / Google），app 不提供 AI 服务

**审被拒的话**：
- Resolution Center 看拒因
- 改完重新 Submit
- 常见拒因预警：metadata 不全、隐私政策内容不到位、demo 账号缺失（我们没 demo 账号是合理的，BYOK 模式）

**v1.1+ 待办（正式 App Store 上架前再处理）**：
- 重命名 `TavernCard` 类（避开 SillyTavern 协议关联）
- 混淆 binary 里的 `nsfw` / `jailbreak` 字符串字面量
- 详见 `plan-rp-language-cleanup.md` L 节

---

---

## 📝 2026-04-21 进度摘要

**当晚搞定的**：
- A1-A3 账号线全 ✅（注册过审 / Agreements 接受 / 两步验证）
- A4 Team ID 锁定 `GQN42B462A`（付费会员；之前散落 6 处的旧 `7TFJ93A25W` 全替换完，memory 新增一条 feedback 防 future session 再写错）
- B5 `MemoryPalace/PrivacyInfo.xcprivacy` 创建 + build 验证（最小版：UserDefaults `CA92.1` + Tracking false + 不收集数据）
- B6 App Icon 1024×1024 塔形薄荷绿 hasAlpha=no 验证，凑合能用
- B7 `ITSAppUsesNonExemptEncryption = false` 写进 iOS target 的 `info.properties`，Info-iOS.plist 确认生成

**卡住的**：
- B2 cert 装不上——付费激活当天 Apple 后端 Cert Service 同步有延迟（1h~隔夜），生成的 cert OU 还是旧 `7TFJ93A25W`；重复双击 .cer 会触发 error -25294 把 keychain 守护进程卡死。**等隔夜后明早重试**，memory 新增 `feedback_apple_program_cert_sync.md` 记录全部坑

**后续 Claude 侧可继续**：
- ~~E1 Beta App Description 中文草稿~~ ✅ 粟粟自己写完了（"小房子 / 旧日记 / 趴只猫 / 时间慢慢变厚"）
- ~~E3 What to Test 首版模板~~ ✅ 粟粟写完（"还在学走路 / 毛边 / 点菜 / 老 iPhone 有点喘"）
- ~~F4 TestFlight 登录教程~~ ✅ 粟粟写完（"蓝色小飞机 / 不要自己硬摸 🥺💕"）

**当前堵塞点**：只有 B2（等 Apple 同步 cert）

---

## ⏱️ 时间风险（参考用）

| 风险项 | Apple 官方 | 2026 实际 | 粟粟实际 |
|--------|------------|-----------|----------|
| Developer Program 账号审核 | 24-48h | 2-7 周（大量案例）| **当天过了** ✅ |
| TestFlight Beta App Review（首次 build）| 24-48h | 24-48h（复杂 3-7 天）| 待 |

**结论**：账号这关过了，剩下全是填表 + 上传。唯一真正"等 Apple"的环节是首次 Beta App Review 那 24-48h。

---

## 一、账号 & 团队（最关键那关已过）

- [x] Apple Developer Program 注册 + 付款 + 审核过 ✅
- [x] 两步验证确认开启 ✅
- [x] Agreements 页接受 "Free Apps Agreement" ✅
- [x] 记录 Team ID：**GQN42B462A**（memory + project.yml + plan doc 全同步）✅

> TestFlight **不需要**：税务表全套 / Banking / 隐私政策 URL / Privacy Nutrition Label 完整填写 / 正式上架分类 / App 描述 / App Store 截图。全部放到了最后"搁置清单"。

---

## 二、项目配置（Xcode / 代码侧）

- [ ] **Bundle ID**：`com.susu.MemoryPalace` ✅（CLAUDE.md 固定）
- [ ] **DEVELOPMENT_TEAM 显式配到 project.yml**
  - 值：`GQN42B462A`
  - **不配的话 iOS 真机 build 会报"requires a development team"**（memory 里有记录）
  - 每次 `xcodegen generate` 都会按 project.yml 填回去
- [ ] **版本号约定**
  - Marketing Version: `1.0.0`（TestFlight 展示）
  - Current Project Version (build): `1`，每次上传递增（`2`、`3`…）
- [ ] **Signing & Capabilities**
  - Team 选到新账号
  - Automatically manage signing 勾上
  - 首次 Archive 时 Xcode 会自动创建 provisioning profile
- [x] **Privacy Manifest**（`MemoryPalace/PrivacyInfo.xcprivacy`）✅
  - Research 发现代码只用了 UserDefaults 一类 Required Reason API（`CA92.1`），其他 4 类（FileTimestamp / DiskSpace / BootTime / ActiveKeyboards）全部 0 处使用
  - ZIPFoundation 自带 privacy manifest（意外惊喜，zip 读 modification time 的声明它自己 cover）
  - MarkdownUI / VariableBlur 未自带但是纯 UI 渲染库，大概率没用 Required Reason API
  - 详细决策逻辑见本文档末尾「附：隐私声明三层与 TestFlight 最小策略」
- [x] **App Icon 1024×1024** ✅
  - 现有塔形薄荷绿 icon，hasAlpha=no，凑合能用
- [x] **Info.plist ITSAppUsesNonExemptEncryption = false** ✅
  - 加到 iOS target `info.properties`（和 NSAppTransportSecurity 并列）
  - 提交 Archive 时 Apple 自动跳过 Export Compliance 问卷
- [ ] **Launch Screen** 确认（已有就跳过）
- [ ] **Deployment Target** iOS 17+（现状别动）
- [ ] **Archive 本地跑通一次**
  - `xcodegen generate` → Xcode → Product → Archive
  - Organizer 能看到 archive 就算成功，暂不 Distribute

---

## 三、代码修复（Phase 0.5 阻塞项）

粟粟手上已在推，这部分 Claude 不跟，只做列表同步。

- [ ] 对话页打磨（气泡内间距 / 小图标 / 排版）
- [ ] B6 思考链 / 上下文重复（与对话页合并做）
- [ ] 皮肤切换翻页动画收尾（另一个 worktree）
- [ ] B2 搜索排序 bug（基本完成）
- [ ] E6 快速回顶/回底

---

## 四、App Store Connect 最小必填（TestFlight only）

路径：https://appstoreconnect.apple.com

- [ ] **创建 App 记录**（My Apps → +）
  - Platform: iOS
  - Name: `记忆宫殿`
  - Primary Language: Simplified Chinese
  - Bundle ID: 选 `com.susu.MemoryPalace`（Xcode 首次 Archive 上传后会自动出现在下拉框）
  - SKU: `memory-palace-ios`
  - User Access: Full Access
- [ ] **Age Rating 年龄分级**（提交 Beta App Review 前必填）
  - AI 聊天类按问卷实际勾选，一般 12+ 或 17+
- [ ] **Export Compliance**：Info.plist 填了 `ITSAppUsesNonExemptEncryption = false` 就免填这里

> App Information 页的 Category / Content Rights / Privacy Nutrition Label **TestFlight 阶段不强制**，正式上架才要。

---

## 五、TestFlight 必需文案

- [ ] **Beta App Description**（200-300 字）
  - 给测试人员看的"这是什么 app"
  - Claude 可以起草
- [ ] **Feedback Email**：粟粟邮箱
- [ ] **What to Test**（每次上 build 都要填）
  - 第一次：简介 + 核心功能清单
  - 后续版本：这次改了什么、希望测什么
  - 写进已知问题（B13 iPhone 14 卡顿说明）免得朋友炸
- [ ] **License Agreement**：TestFlight 用 Apple 标准版，不改

> **不填**：Marketing URL / Privacy Policy URL / Support URL（TestFlight 都非必填，正式上架才要）。

---

## 六、测试组 & 邀请

- [ ] **Internal Testing group**
  - 同 Team 成员，最多 100 人
  - **无需 Beta App Review，立即可用**
  - 自己先放这里验收几天
- [ ] **External Testing group（朋友组）**
  - 最多 10,000 人
  - **首次新版本需要 Beta App Review（24-48h）**
  - 后续 build 在同版本号下免审
- [ ] **朋友邀请**
  - 两种方式：邮件邀请（对方要 Apple ID）或公开链接（粘贴即加）
  - 公开链接更省事，粟粟建议用这个
- [ ] **TestFlight 登录教程简版**
  - 国内朋友可能没装 TestFlight app
  - 写进邀请消息：下载 TestFlight → 打开链接 → 接受邀请 → 装 app
- [ ] **反馈渠道**：邮箱 / 群聊，选一个告诉朋友

---

## 七、发布流程（代码全绿 + 素材齐）

1. `xcodegen generate && xcodebuild -scheme MemoryPalace build` 最终确认无 warning
2. Xcode → Product → Archive
3. Organizer → Distribute App → App Store Connect → Upload
4. 等 10-20 分钟，App Store Connect 里 build 状态从 "Processing" 变 "Ready to Submit"
5. **Internal Testing**：勾选 build → 发给自己 → 立即可装
6. 自己内部测几天，抓一波 bug
7. **External Testing**：勾选 build → 填 What to Test → 提交 Beta App Review（24-48h）
8. 审核过 → 发朋友 TestFlight 链接 → 🎉

---

## 总表（最后更新：2026-04-20）

状态图例：✅ 完成 / ⏳ 进行中或等待 / 🔲 未开始

### A. 账号 & 团队

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| A1 | Apple Developer Program 注册 + 付款 + 审核 | ✅ | 粟粟 | 一天过审，运气好 |
| A2 | 两步验证确认开启 | ✅ | 粟粟 | — |
| A3 | Agreements 页接受 Free Apps Agreement | ✅ | 粟粟 | — |
| A4 | Team ID 记录：`GQN42B462A` | ✅ | — | memory 已存 |

### B. 项目配置（Xcode / 代码）

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| B1 | Bundle ID `com.susu.MemoryPalace` | ✅ | — | CLAUDE.md 固定 |
| B2 | `DEVELOPMENT_TEAM = GQN42B462A` 写入 project.yml | ⏳ | Claude 改完 + Apple 同步 + 粟粟装 cert | project.yml 已配；cert 卡在 Apple Cert Service 同步中（2026-04-20 付费，次日生成的 cert OU 还是旧 7T）；等隔夜后明早重试 |
| B3 | Marketing `1.0.0` / Build `1` 版本号规范 | 🔲 | 粟粟 | 后续 build 号递增 |
| B4 | Signing Team 切到新账号 | 🔲 | 粟粟 | Xcode 里操作 |
| B5 | `PrivacyInfo.xcprivacy` 新建 + 声明 API | ✅ | Claude | `MemoryPalace/PrivacyInfo.xcprivacy` 最小版（UserDefaults CA92.1 + Tracking false + 不收集数据）；build 通过，已打进 .app/Contents/Resources/；ZIPFoundation 自带 manifest 省一步 |
| B6 | App Icon 1024×1024（无 alpha 无圆角）| ✅ | 粟粟 | 塔形薄荷绿，hasAlpha=no 已验证 |
| B7 | `ITSAppUsesNonExemptEncryption = false` 写 Info.plist | ✅ | Claude | 加到 iOS target `info.properties`（和 NSAppTransportSecurity 并列），Info-iOS.plist 已生成 `<false/>`；提交 Archive 时 Apple 自动跳过 Export Compliance 问卷 |
| B8 | Launch Screen 确认 | 🔲 | 粟粟 | 已有就跳 |
| B9 | Archive 本地跑通一次 | 🔲 | 粟粟 | B2/B4/B5/B7 齐之后 |

### C. 代码修复（Phase 0.5 阻塞项）

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| C1 | 对话页打磨 + B6 思考链重复 | ⏳ | 粟粟 | 合并做 |
| C2 | 皮肤切换翻页动画收尾 | ⏳ | 粟粟 | 另一 worktree |
| C3 | B2 搜索排序 bug | ⏳ | 粟粟 | 基本完成 |
| C4 | E6 快速回顶/回底 | 🔲 | 粟粟 | 小功能 |

### D. App Store Connect（最小必填）

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| D1 | 创建 App 记录（Name / Bundle ID / SKU / 语言）| 🔲 | 粟粟 | 首次 Archive 上传后 Bundle ID 才出现 |
| D2 | Age Rating 问卷 | 🔲 | 粟粟 | Beta Review 前必填 |
| D3 | Export Compliance | ✅ 被 B7 覆盖 | — | Info.plist 搞定就行 |

### E. TestFlight 文案

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| E1 | Beta App Description（200-300 字）| ✅ | 粟粟写 | 见下方「附：TestFlight 文案定稿」 |
| E2 | Feedback Email | 🔲 | 粟粟 | 填 ASC 后台时用 |
| E3 | What to Test 首个模板 | ✅ | 粟粟写 | 见下方「附：TestFlight 文案定稿」，含 B13 已知问题说明 |

### F. 测试组 & 邀请

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| F1 | Internal Testing group 建好 | 🔲 | 粟粟 | D1 + 上传过 build 之后 |
| F2 | External Testing group（朋友组）建好 | 🔲 | 粟粟 | 同上 |
| F3 | 公开邀请链接开启 | 🔲 | 粟粟 | 国内朋友最方便 |
| F4 | TestFlight 登录教程简版 | ✅ | 粟粟写 | 见下方「附：TestFlight 文案定稿」，蓝色小飞机 + 不要自己硬摸 |
| F5 | 反馈渠道告知（邮箱/群聊）| 🔲 | 粟粟 | — |

### G. 发布

| # | 事项 | 状态 | 负责 | 备注 |
|---|------|------|------|------|
| G1 | `xcodebuild` 最终全绿 | 🔲 | 粟粟 | C 系列完成 |
| G2 | Archive → Upload | 🔲 | 粟粟 | G1 之后 |
| G3 | Internal Testing 自测几天 | 🔲 | 粟粟 | G2 processing 完 |
| G4 | 提交 External Beta App Review | 🔲 | 粟粟 | 24-48h |
| G5 | 审核过 → 发朋友链接 | 🔲 | 粟粟 | 🎉 |

---

## 关键路径

```
A ✅ (账号全过) ──┐
                 ├──> D1 创建 App 记录 ─┐
B 项目配置 ──> B9 Archive ────────────── G2 上传 ──> G3 自测 ──> G4 审核 ──> G5 发朋友
    (B5 PrivacyInfo 不能漏)                            │
C 代码修复 ──> G1 build 全绿 ──────────────────────────┘

E 文案（完全并行，Claude 起草）
F 测试组（依赖 D1 + G2）
```

**目前卡点**：B + C 两条线并行。C（代码）粟粟在推，B（项目配置）等 Claude 接手 B2/B5/B7。

---

## 附：隐私声明三层与 TestFlight 最小策略

> 为什么 `PrivacyInfo.xcprivacy` 只声明了 UserDefaults 一项就够？粟粟问过「接 API 算不算」，这里把判断逻辑记下来，免得以后自己忘了。

Apple 隐私体系其实是**三件独立的事**：

| 层次 | 管什么 | 什么时候强制 | 记忆宫殿的处理 |
|------|--------|-------------|----------------|
| **Privacy Manifest**（`PrivacyInfo.xcprivacy` 的 `NSPrivacyAccessedAPITypes` 段）| 代码调用的 Required Reason API（UserDefaults / FileTimestamp / DiskSpace / BootTime / ActiveKeyboards 这 5 类）| TestFlight Beta Review 检查 | **最小版声明 UserDefaults `CA92.1`** ✅ |
| **NSPrivacyCollectedDataTypes**（同一个 manifest 里的另一节）| app 把什么用户数据发到外部 server | TestFlight 不强制，正式上架强制 | **空着**（搁置到 v1.1） |
| **App Privacy Nutrition Label**（ASC 后台问卷）| 用户在 App Store 看到的"数据收集"说明页 | TestFlight 不强制，正式上架强制 | **不填**（搁置到 v1.1） |

### 关键判断点：接 AI API 算什么？

- **URLSession / URLRequest 本身**不在 Apple Required Reason API 清单里——**不需要**在 manifest 里声明
- 但"发用户 prompt 到 Anthropic/OpenAI/Google" 按 Apple 定义**确实算"收集用户内容并传给第三方合作方"**（哪怕是用户自填 API key、数据不经过开发者服务器）
- 这属于**第二层和第三层**的范畴，不是第一层
- **TestFlight 阶段这两层都不强制**——Beta Review 只看第一层 Privacy Manifest 是否存在且格式对

### 所以 TestFlight 够用的最小版长这样

```xml
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>CA92.1</string></array>
  </dict>
</array>
```

四个字段含义：
- `NSPrivacyTracking = false`——不做跨 app 追踪
- `NSPrivacyTrackingDomains = []`——没有任何追踪域名
- `NSPrivacyCollectedDataTypes = []`——TestFlight 阶段可留空，正式上架要补"User Content → Other User Content / App Functionality / Not linked / Not tracking"
- `UserDefaults / CA92.1`——存自己 app 的配置

### 正式上架（v1.1）时要补的两层

**第二层** `NSPrivacyCollectedDataTypes` 要声明：
- Data Type: `NSPrivacyCollectedDataTypeOtherUserContent`（or Messages 若更精确）
- Linked to User: **false**（记忆宫殿不识别用户身份）
- Used for Tracking: **false**
- Collection Purposes: `NSPrivacyCollectedDataTypePurposeAppFunctionality`

**第三层** ASC 后台 Privacy Nutrition Label 问卷诚实填：同上信息会被聚合到 App Store 展示页。

这俩现在不动，TestFlight 走最小集合就行。

---

## 附：TestFlight 文案定稿（2026-04-21）

> 上 ASC 后台填 TestFlight 信息时直接拷贝这三段。

### Beta App Description（E1）

```
有些对话值得被好好收藏。

记忆宫殿是一座为你和AI之间的每一句话建造的小房子。你可以把散落在ChatGPT和Claude里的对话搬进来，像翻一本旧日记一样浏览它们——包括每一个分支、每一次犹豫、每一条走过又折回的路。

AI会记得你。真的记得你上个月说过什么、你喜欢怎样被回应、你的世界里有哪些重要的名字。

你还可以在对话上贴贴纸。为什么不呢？重要的话旁边应该趴一只猫。对话的意义可以一直生长。批注，批注批注，批注批注的批注，时间就这样慢慢变厚了。

所有数据住在你的手机里，哪儿也不去。
```

### What to Test（E3）

```
这是记忆宫殿的第一个可以被摸到的版本。它还在学走路，可能会摔跤，可能有点毛边，但我会继续打磨。><

如果你愿意帮忙，试试这些：打开一段对话，左右翻翻页，感受一下手感。随便贴几张贴纸玩玩。试试搜索功能能不能找到你记得的那句话。如果某个瞬间你觉得"这里怪怪的"，或者想吃什么功能但是没有，截图告诉我点菜就好。

已知的小毛病：老一点的iPhone可能会有点喘。我在修了！
```

### TestFlight 登录教程（F4）— 发给朋友的说明

```
你会收到一封来自Apple的邮件，或者一个链接。不要害怕，这不是诈骗。

第一步：去App Store搜"TestFlight"，下载。它是Apple官方的试玩工具，长得像一个蓝色的小飞机。

第二步：打开我发你的邀请链接。TestFlight会弹出来问你要不要接受。点接受。

第三步：等一小会儿，"记忆宫殿"会出现在TestFlight的列表里。点安装。

第四步：回到手机桌面，你会看到一个新的图标。点开它。你的宫殿到了。

如果中间任何一步卡住了，截图发给我，不要自己硬摸。🥺💕
```

---

## 附：TestFlight 文案定稿（2026-04-21）

> 上 ASC 后台填 TestFlight 信息时直接拷贝这三段。

### Beta App Description（E1）

```
有些对话值得被好好收藏。

记忆宫殿是一座为你和AI之间的每一句话建造的小房子。你可以把散落在ChatGPT和Claude里的对话搬进来，像翻一本旧日记一样浏览它们——包括每一个分支、每一次犹豫、每一条走过又折回的路。

AI会记得你。真的记得你上个月说过什么、你喜欢怎样被回应、你的世界里有哪些重要的名字。

你还可以在对话上贴贴纸。为什么不呢？重要的话旁边应该趴一只猫。对话的意义可以一直生长。批注，批注批注，批注批注的批注，时间就这样慢慢变厚了。

所有数据住在你的手机里，哪儿也不去。
```

### What to Test（E3）

```
这是记忆宫殿的第一个可以被摸到的版本。它还在学走路，可能会摔跤，可能有点毛边，但我会继续打磨。><

如果你愿意帮忙，试试这些：打开一段对话，左右翻翻页，感受一下手感。随便贴几张贴纸玩玩。试试搜索功能能不能找到你记得的那句话。如果某个瞬间你觉得"这里怪怪的"，或者想吃什么功能但是没有，截图告诉我点菜就好。

已知的小毛病：老一点的iPhone可能会有点喘。我在修了！
```

### TestFlight 登录教程（F4）— 发给朋友的说明

```
你会收到一封来自Apple的邮件，或者一个链接。不要害怕，这不是诈骗。

第一步：去App Store搜"TestFlight"，下载。它是Apple官方的试玩工具，长得像一个蓝色的小飞机。

第二步：打开我发你的邀请链接。TestFlight会弹出来问你要不要接受。点接受。

第三步：等一小会儿，"记忆宫殿"会出现在TestFlight的列表里。点安装。

第四步：回到手机桌面，你会看到一个新的图标。点开它。你的宫殿到了。

如果中间任何一步卡住了，截图发给我，不要自己硬摸。🥺💕
```

---

## 搁置清单（v1.1 正式上架再做，现在不碰）

- ~~隐私政策 URL + GitHub Pages 占位页~~
- ~~App Information 分类（Productivity / Utilities）~~
- ~~Content Rights 内容版权声明~~
- ~~Privacy Nutrition Label 隐私问卷完整填写~~
- ~~App 描述（中文长文案）~~
- ~~6.9" iPhone 截图 3-5 张~~
- ~~iPad 13" 截图~~
- ~~App 预览视频~~
- ~~Marketing URL / Support URL~~
- ~~税务表 W-8BEN / Banking 完整信息~~
- ~~macOS 版本发布~~

---

*TestFlight 上架 Apple 官方 help 写得比 SDK 文档清楚，遇到卡点直接搜 "App Store Connect Help [具体问题]"。*
