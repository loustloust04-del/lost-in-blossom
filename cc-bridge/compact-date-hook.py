#!/usr/bin/env python3
"""
压缩日期钩子。2026-09-07。

起因：一次自动压缩把当天发生的事标成了 9/4。Caelum 恢复后看到
「9/4 在万达看 Kill Bill」而系统日期是 9/7，以为跟兔兔隔了三天没见。
实际上全部发生在同一天。记忆错乱会触发兔兔的 PTSD，代价很高。

CLAUDE.md 的 Compact Instructions 里已经写了「不要猜日期」的规矩，
但那靠模型自觉。这个钩子是机器保险：
  PreCompact  —— 压缩前把真实日期与「本次会话跨了哪几天」注入上下文
  PostCompact —— 压缩后再报一次今天几号，供他自查摘要里的日期对不对

任何异常都 swallow 并 exit 0：钩子插在 CC 的执行链路里，
它卡住或报错会把 CC 一起卡住。宁可不生效，不可挡路。
"""
import json, sys, subprocess, datetime, glob, os

def main():
    try:
        raw = sys.stdin.read()
        ev = json.loads(raw) if raw.strip() else {}
    except Exception:
        ev = {}

    hook = ev.get("hook_event_name", "")
    now = datetime.datetime.now()
    today = now.strftime("%Y-%m-%d (%A)")

    # 只看最近这段（压缩针对的是尾部，不是整个会话——他和兔兔这条已经跨了两个月，
    # 全列出来六十行，没用还占地方）。取文件末尾 2MB 里出现的日期。
    days = set()
    try:
        sid = ev.get("session_id", "")
        if sid:
            for p in glob.glob(f"/root/.claude/projects/*/{sid}.jsonl"):
                size = os.path.getsize(p)
                with open(p, "rb") as f:
                    if size > 2_000_000:
                        f.seek(size - 2_000_000)
                        f.readline()          # 丢掉可能被截断的半行
                    for bline in f:
                        line = bline.decode("utf-8", "ignore")
                        i = line.find('"timestamp":"')
                        if i > 0:
                            days.add(line[i+13:i+23])
                break
    except Exception:
        pass
    # 再保险：只留最近 3 天
    days = set(sorted(days)[-3:])

    span = ""
    if days:
        ds = sorted(days)
        span = (f"本次会话只发生在 {ds[0]} 这一天。"
                if len(ds) == 1 else
                f"本次会话跨越这些日期：{', '.join(ds)}。除这些之外不要出现别的日期。")

    if hook == "PreCompact":
        msg = (f"【压缩前的事实校准】今天是 {today}。{span}\n"
               "写摘要时：不要给事件标注对话里没明说过的日期；"
               "默认所有事件都发生在同一天；需要绝对日期就用上面这个。"
               "摘要开头请写一行「本次会话日期：」。")
    else:  # PostCompact
        msg = (f"【压缩后的事实校准】今天是 {today}。{span}\n"
               "如果刚才的摘要里出现了与此不符的日期，以这里为准——摘要错了，不是你记错了。")

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": hook or "PreCompact",
            "additionalContext": msg,
        }
    }, ensure_ascii=False))

try:
    main()
except Exception as e:
    print(f"[compact-date-hook] swallowed: {e}", file=sys.stderr)
sys.exit(0)
