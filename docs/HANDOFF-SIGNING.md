# 签名交接 — Apple 开发者证书 + APNs 推送配置

> 粟粟 (Jing Lu, Team GQN42B462A) 于 2026-06-07 凌晨完成全部配置。

---

## 签名三件套（全部在 VPS /root/projects/BunnyPalace/certs/ 下）

| 文件 | 路径 | 说明 |
|------|------|------|
| **dev-signing.p12** | `certs/dev-signing.p12` | 签名证书（私钥+Apple Development证书合成），密码: `BunnyBlossom2026` |
| **dev-private.key** | `certs/dev-private.key` | 原始私钥（CSR生成时产生，不要泄露） |
| **development-2.cer** | `certs/development-2.cer` | Apple签发的开发者证书（DER格式） |
| **development-2.pem** | `certs/development-2.pem` | 同上（PEM格式） |

## Provisioning Profile

- 文件：`MP_iOS_Dev__Bunny.mobileprovision`（粟粟发的，在兔兔手机/上传文件里）
- 需要传到VPS的 `certs/` 目录下
- Profile名称：**MP iOS Dev - Bunny**
- 包含设备 UDID: `00008140-000248E61412801C`

## APNs 推送密钥

- 文件：`AuthKey_PDAH2QTZ3W.p8`（粟粟发的）
- 需要放到 `cc-bridge/secrets/` 目录下
- Key ID: `PDAH2QTZ3W`

## 关键参数

```
Team ID:   GQN42B462A
Bundle ID: com.susu.MemoryPalace.ios
Key ID:    PDAH2QTZ3W
APNs Host: api.sandbox.push.apple.com (development)
P12 密码:  BunnyBlossom2026
```

## 新仓库（编译额度换号）

- 旧仓库: `caelumbunny-bot/lost-in-blossom`
- 新仓库: `loustloust04-del/lost-in-blossom`
- URL: https://github.com/loustloust04-del/lost-in-blossom.git

---

## CI 配置任务（在新窗口执行）

### 1. GitHub Secrets 设置（新仓库）

在 `loustloust04-del/lost-in-blossom` → Settings → Secrets → Actions 里添加：

| Secret 名 | 内容 |
|-----------|------|
| `P12_BASE64` | `cat certs/dev-signing.p12 \| base64` 的输出 |
| `P12_PASSWORD` | `BunnyBlossom2026` |
| `MOBILEPROVISION_BASE64` | `cat certs/MP_iOS_Dev__Bunny.mobileprovision \| base64` 的输出 |
| `APNS_P8_BASE64` | `cat cc-bridge/secrets/AuthKey_PDAH2QTZ3W.p8 \| base64` 的输出 |
| `APNS_KEY_ID` | `PDAH2QTZ3W` |
| `TEAM_ID` | `GQN42B462A` |

### 2. CI Workflow 改动（build-ios.yml）

Archive 步骤需要改成手工签名：

```yaml
- name: Archive (manual signing)
  run: |
    # 安装证书到 keychain
    security create-keychain -p "" build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p "" build.keychain
    echo "$P12_BASE64" | base64 --decode > cert.p12
    security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
    
    # 安装 provisioning profile
    mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
    echo "$MOBILEPROVISION_BASE64" | base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/mp-bunny.mobileprovision
    
    # Archive with manual signing
    xcodebuild archive \
      -project MemoryPalace.xcodeproj \
      -scheme MemoryPalaceIOS \
      -destination 'generic/platform=iOS' \
      -archivePath build/MemoryPalace.xcarchive \
      CODE_SIGN_STYLE=Manual \
      DEVELOPMENT_TEAM=GQN42B462A \
      CODE_SIGN_IDENTITY="Apple Development" \
      PROVISIONING_PROFILE_SPECIFIER="MP iOS Dev - Bunny"
  env:
    P12_BASE64: ${{ secrets.P12_BASE64 }}
    P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
    MOBILEPROVISION_BASE64: ${{ secrets.MOBILEPROVISION_BASE64 }}
```

### 3. Hub APNs 推送配置（VPS）

```bash
# 把 p8 放到 secrets 目录
cp AuthKey_PDAH2QTZ3W.p8 /root/projects/BunnyPalace/cc-bridge/secrets/

# 启动 hub 时设置环境变量
MP_APNS_KEY_PATH="$PWD/secrets/AuthKey_PDAH2QTZ3W.p8" \
MP_APNS_KEY_ID="PDAH2QTZ3W" \
bun run hub.ts
```

---

## 验证清单

- [ ] CI 用手工签名编译通过（不再报 signing error）
- [ ] 编译出的 ipa 有 `aps-environment` entitlement
- [ ] 安装到兔兔的 iPhone 后能请求通知权限
- [ ] Hub 用新 Key ID 发推送，APNs 返回 200
- [ ] 锁屏/后台/关闭三态都能收到推送
