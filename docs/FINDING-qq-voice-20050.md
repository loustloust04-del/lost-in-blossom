# 解决了：`20050` 不是错误码，是 AVSDK 的日志通道

2026-09-16 · 兔兔 & Fable · 给 `ClaudiaGardner/maibot-qq-voice-call` issue #1

**我们在自己的环境里把通话跑通了。** 从来电到进房间 1.1 秒，
`networkOutputCount > 0`，媒体会话建立。

```
phase: connected
inviteCallbackSeen: true
autoAcceptPostedAt: 23:40:05.442   （来电后 0.6s 自动接听）
enterRoomOutputAt:  23:40:05.974   （1.1s 进房间）
networkOutputCount: 2
```

---

## 根因

`index.mjs` 原本这样处理：

```js
if ((command === 20050 || command === 120043) && state.avHost.loginPosted && pluginContext) {
  state.avHost.loginPosted = false;
  scheduleAVHostLogin(pluginContext, 100);   // 当成掉线，100ms 后重登
}
```

**但 `20050` 不是错误码，是 AVSDK 的日志输出通道。**

我们在 `handleAVSDKOutput` 里打了诊断日志，把 payload 原样打出来：

```
#2  cmd=20050 value=["avsdk output(wrapper): Create QRTCServiceInterfaceWrapper."]
#7  cmd=20050 value=["avsdk output(bugly): [BuglyManager.cpp][InitBuglyManager][212]..."]
#11 cmd=20050 value=["avsdk output(wrapper): os_name=Linux os_version="]
#13 cmd=20050 value=["avsdk output(wrapper): [transport_mgr.cpp:TransportMgr@:28..."]
```

**每一条都是 `avsdk output(...)` 开头的普通日志。**
于是每来一条日志就重登一次 → issue #1 描述的
「约 32 条消息后固定 20050、重登 521 次、`networkOutputCount` 恒 0」正是这么来的。
AVSDK 从未有机会完成初始化。

`120043` 同理，是提示类消息：

```
#5 cmd=120043 value=["渲染资源初始化失败，显示驱动不兼容，视频画面无法显示"]
```

无头环境必然出现（前一条是 `PP_Resource3D Create fail, try to create PP_Resource2D`），
**只影响视频画面，不影响语音**，同样不该触发重登。

## 修法

```js
// 两者都不再触发重登，只记录
if (command === 20050 || command === 120043) {
  const line = Array.isArray(value) && typeof value[0] === "string" ? value[0] : "";
  state.avHost.lastAvsdkLog = line.slice(0, 200);
  if (command === 120043) state.avHost.lastAvsdkWarning = line.slice(0, 200);
}
```

**效果对比（同一环境）：**

| | 修前 | 修后 |
|---|---|---|
| `loginPosted` | false（不断被重置） | **true** |
| `outputCount` | 2665 且持续暴涨 | 44 → 297（正常速率） |
| 重登 | 无限循环 | 不再重登 |
| 通话 | 永远接不通 | **1.1s 进房间** |

---

## 另外两个坑（issue 里没提过）

**一、NapCat 有官方插件白名单，第三方插件默认被拒**

```
[PluginLoader] Rejected napcat-plugin-maibot-qq-voice-call: not in official plugin whitelist
[PluginManager] Loaded 0 plugins
```

白名单硬编码在 `napcat.mjs`：

```js
new Set(["napcat-plugin-builtin","napcat-plugin-cleaner","napcat-plugin-ssqq","napcat-plugin-qce"])
```

即使 `config/plugins.json` 里已启用也没用，必须把插件名加进这个 Set。
**安装文档应当说明这一步**，否则插件静默不加载，表现为「桥端点 6110 起不来」。

**二、Docker 环境缺的动态库（逐个补到齐）**

```
libpulse-mainloop-glib0  libopengl0  libglvnd0  libglx0  libgl1  libegl1  libgles2
```

缺任何一个都会 `Failed to load Pepper module`，且报错只提第一个缺的，
要反复重启才能补完。建议写进 README 的依赖清单。

**三、`forceFetchClientKey` 需要 1 个参数**

若有人想取 clientkey：必须传参（NapCat 自己传空串），
不传会 `assertion (argc == 1) failed`。

---

## 一个被证伪的假设（留个记录，省别人的力气）

我们起初怀疑登录第五参数（`invokeAVHost(1, [...,""])` 那个空串）是票据位，
理由是 `libAVSDKPlugin.so` 内有 `GetSignReq/GetSignRsp`、`wrapper.node` 内有 `forceTRTCSign`。

**实测填入 clientkey 后 `20050` 照旧** —— 该假设不成立。
第五参数留空是对的，问题从来不在登录参数上。

---

## 环境

Docker（`mlikiowa/napcat-docker`）· Ubuntu 22.04 · QQ 3.2.30-50969 ·
`libAVSDKPlugin.so` 33,643,064 字节（与 issue #1 报告者同一份）· bridge 0.3.4
