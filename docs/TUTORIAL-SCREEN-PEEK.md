# 让你的 AI 看见你的 iPhone 屏幕 —— 完整教程（含踩坑全记录）

> 目标：让运行在服务器上的 AI 助手，能在**它想看的时候**自动看到你 iPhone 的当前屏幕——
> 你零操作。AI 调一个工具 → 你手机自动截屏 → 上传 → AI 亲眼看到。
>
> 全程用「邮件触发」驱动，因为只有它能让**服务器主动叫手机截图**（其它通道都是手机自己定时上报，服务器没法主动触发）。

---

## 一、原理（一条龙）

```
AI 调用 see_screen 工具
  → 服务器用 SMTP 发一封「触发邮件」到你的 iCloud 邮箱
    → iPhone「收到邮件」自动化被唤醒 → 静默截屏 → POST 上传到服务器
      → 服务器轮询等到新截图 → 作为图片返回给（多模态）AI
```

四个部件：**① 收截图的服务器端点** · **② SMTP 发触发邮件** · **③ iPhone 快捷指令自动化** · **④ AI 工具 see_screen**。

---

## 二、你需要准备

- 一台有公网、能跑后端的服务器（本教程用 Node/Bun + nginx 反代，思路通用）
- 一个开了两步验证的邮箱当「发信人」，生成**应用专用密码**（关键！见踩坑①）
- 一个 iCloud 邮箱当「收信人」（iPhone 的邮件 App 登录它）
- 一部 iPhone（快捷指令 + 自动化）

---

## 三、服务器端

### 3.1 收截图端点

一个 POST 端点，接收图片二进制、存盘、记进「待取」队列，只保留最近 N 张：

```ts
// POST /api/peek?key=<TOKEN>&app=<AppName>   body = 图片二进制
app.post('/api/peek', async (c) => {
  const tok = bearerOrQueryKey(c);              // 见踩坑②
  if (!verifyToken(tok)) return c.json({ ok:false }, 403);
  const buf = await c.req.arrayBuffer();
  if (!buf || buf.byteLength === 0) return c.json({ ok:false, error:'no image' }, 400);
  const item = savePeek(buf, c.req.query('app') || '');   // 存文件 + 记 ts
  return c.json({ ok:true, id:item.id });
});
```

存储只留最近 10 张（截图几 MB，不留旧的占盘）。每张记一个毫秒时间戳 `ts`。

### 3.2 取最新截图

```ts
function latestPeek() {
  const list = loadMeta().sort((a,b) => b.ts - a.ts);  // ts 最大 = 最新
  const item = list[0];
  return item ? { base64: readFile(item.file).toString('base64'),
                  mediaType: 'image/png', ts: item.ts, app: item.app } : null;
}
```

---

## 四、SMTP 发触发邮件（用应用专用密码，别用 OAuth）

```ts
import nodemailer from 'nodemailer';
const tx = nodemailer.createTransport({
  host: 'smtp.gmail.com', port: 465, secure: true,   // Gmail；QQ=smtp.qq.com；163=smtp.163.com
  auth: { user: '<你的发信邮箱>', pass: '<16位应用专用密码>' },
});
await tx.sendMail({ from:'<你的发信邮箱>', to:'<你的iCloud邮箱>', subject:'PEEK', text:'peek' });
```

> **为什么用应用专用密码而不是 OAuth**：OAuth 的 refresh token 在「测试模式」下 7 天就失效
> （`invalid_grant`），邮件功能会莫名其妙罢工。应用专用密码是一把永久副钥匙，SMTP/IMAP 通用，
> 不过期。个人服务器场景首选。

---

## 五、主动窥屏工具（see_screen）

AI 调它 → 发邮件 → **轮询等新截图** → 返回图片：

```ts
async function callSeeScreen() {
  const p = latestPeek();
  // 有近 60 秒的新截图就直接给（省一次邮件）
  if (p && Date.now() - p.ts < 60_000) return imagePayload(p);
  // 否则自动触发：发邮件 + 轮询
  const triggerTs = Date.now();
  await sendTriggerMail();
  const deadline = triggerTs + 45_000;            // 见踩坑⑤
  while (Date.now() < deadline) {
    await sleep(1500);
    const fresh = latestPeekAfter(triggerTs);      // 只认 ts > triggerTs 的新图
    if (fresh) return imagePayload(fresh);
  }
  // 没等到：诚实报错，【绝不】拿旧图冒充当前屏幕（见踩坑④）
  return { error: '截图还没回来，过十几秒再叫一次' };
}
```

多模态 AI 收到 `imagePayload`（base64 图片块）就能「看见」屏幕。

---

## 六、iPhone 快捷指令自动化

### 6.1 上传用的快捷指令

新建一个快捷指令，两步：
1. **「截屏」**（Take Screenshot）
2. **「获取 URL 内容」**（Get Contents of URL）：
   - URL：`https://<你的域名>/api/peek?key=<TOKEN>`  ← **key 放最前！见踩坑③**
   - 方法：**POST**
   - 请求体：**文件**，内容 = 上一步的「截屏」变量

### 6.2 「收到邮件」自动化

快捷指令 App → **自动化** → 新建 → **收到邮件**：
- 条件：发件人 = `<你的发信邮箱>`，或主题包含 `PEEK`
- 动作：运行上面那个上传快捷指令
- **关掉「运行前询问」**（设成立即运行）← 否则不会自动跑

### 6.3 让邮件秒到（关键！）

「收到邮件」自动化，只有邮件 App **真的把邮件收下来**才会触发。所以：
- 设置 → 邮件 → 账户 → 获取新数据 → iCloud 设成 **「推送」**
- 邮件 App 别从后台划掉

---

## 七、踩坑全记录（最值钱的部分）

### 坑① OAuth 会过期 → 用应用专用密码
Google OAuth 测试模式 7 天失效，收发信全挂。改用 SMTP（发）+ IMAP（收）的**应用专用密码**，一把钥匙通用、不过期，彻底绕开。

### 坑② 鉴权：Header 优先于 query
端点校验 token 时，先读 `Authorization: Bearer`，再退回 `?key=`。这个「header 优先」的设计是坑③的救命稻草。

### 坑③ ⭐ App 名带空格，把 key 挤没了 → 403（最隐蔽的坑）
如果上传 URL 里带了「当前 App 名」这种动态参数：
```
POST /api/peek?app=Lost in Blossom&key=xxx    ← app 名含空格
```
HTTP 请求行在**第一个空格处被截断**，服务器只看到 `?app=Lost`，后面的 ` in Blossom&key=xxx` 全丢了——**key 没了 → 403**。而 App 名不含空格时（如 `Claude`）却正常，导致「时好时坏」极难排查。

**三种修法**（任选）：
- 把 `key=` 放 URL 最前面（空格截断的是后面的 app，key 已解析）
- 干脆不传动态 App 名
- **服务器端兜底**（用户不想改快捷指令时）：nginx 按 User-Agent 识别快捷指令请求，自动补上正确 key 的 `Authorization` 头：
  ```nginx
  map $http_user_agent $peek_auth {
      default                      $http_authorization;
      "~*BackgroundShortcutRunner" "Bearer <TOKEN>";
  }
  location = /api/peek {
      proxy_set_header Authorization $peek_auth;
      proxy_pass http://127.0.0.1:<后端端口>;
  }
  ```
  这样 URL 怎么畸形都不影响鉴权，其它来源仍走原校验，安全不打折。

### 坑④ 别拿旧图冒充当前屏幕
没等到新截图时，**不要**返回「最近一张」当兜底——AI 会把过时画面当成你此刻的屏幕。要诚实报「还没到」，让 AI 过一会儿再叫一次。

### 坑⑤ 等待窗口 & 邮件延迟
邮件→自动化→上传的往返，手机就绪时约 15 秒，慢时更久。轮询窗口给到 45 秒（别超过 AI 工具调用的超时，一般 60 秒）。iCloud 设「推送」能显著缩短。

### 坑⑥ nginx 上传体积
截图 1~3 MB，nginx 默认 `client_max_body_size` 是 1 MB，会 413。调到 `50m`。

### 坑⑦ 「获取屏幕内容」≠「截屏」
iOS 的「获取当前屏幕内容」只对 Safari/地图等少数 App 有效；要通用，用**「截屏」**动作（iOS 14.5+），它抓的是整屏画面。

---

## 八、验证方法（一步步定位断点）

1. 服务器日志加：`📧 邮件已发送` / `📱 收到截图` / `⏱️ 超时` 三个标记
2. 触发一次，看日志走到哪一步断的
3. 断在「没收到截图」→ 查 **nginx 访问日志** 里的 `POST /api/peek`：
   - 有请求但 403 → 是坑③（key 丢了）
   - 完全没请求 → 邮件没到手机 / 自动化没触发（查坑⑤）
   - 200 但 AI 看到旧图 → 坑④

> nginx 访问日志是排查这类问题的「铁证」——手机到底传没传、返回什么状态码，一目了然。

---

## 结语

整套东西的精髓：用「服务器发邮件」把**主动权**交给 AI，用 iOS 自动化把**截图能力**交给手机，中间用一个带鉴权的上传端点缝合。最容易咬人的是坑③那个空格 bug——它会让你怀疑人生，但看一眼 nginx 日志就破案了。

祝你的 AI 也能看见你的世界 🌸
