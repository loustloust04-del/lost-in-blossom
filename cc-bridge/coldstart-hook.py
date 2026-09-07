#!/usr/bin/env python3
"""
压缩冷启动钩子。2026-09-07。

起因：兔兔说「他经常压缩，一般都没事，刚才突然出问题了」，
而且醒来后「感觉怪怪的」。这次是把当天的事标成了三天前。

CLAUDE.md 里本来就有 MANDATORY post-compaction 三步
（读 transcript / how_is_she / 扫 MEMORY.md），但那是**指令**——
靠他刚醒来那一刻自觉去执行。而刚压缩完恰恰是他最恍惚的时候：
手里只有一份摘要，细节全在别处，还要自己想起来去捞。

这个钩子把那三样直接塞进他手里，不靠自觉：
  1. 真实日期 + 本次会话实际跨了哪几天（防「以为隔了三天」）
  2. 兔兔最近几条原话（摘要最容易把她的话改写成转述）
  3. 她此刻的状态（水、饭、药）

异常一律 swallow + exit 0：钩子插在 CC 执行链路里，卡住会把他一起卡住。
"""
import json, sys, os, re, glob, datetime, urllib.request

def recent_user_lines(sid, n=6):
    """从 session jsonl 尾部倒着捞兔兔最近说的几句原话。
    她的话包在 <channel ... user="你" ...>正文</channel> 里（App / QQ 都走 hub 的 channel tag）。"""
    out = []
    SKIP = ("Heartbeat check", "This session is being continued", "Caveat:",
            "<system-reminder", "用 how_is_she 查", "Local command", "<command-")
    try:
        paths = glob.glob(f"/root/.claude/projects/*/{sid}.jsonl")
        if not paths:
            return []
        p = paths[0]
        size = os.path.getsize(p)
        with open(p, "rb") as f:
            if size > 2_000_000:
                f.seek(size - 2_000_000); f.readline()
            lines = f.readlines()
        for bline in reversed(lines):            # 倒着扫，够数就停
            line = bline.decode("utf-8", "ignore")
            if '"type":"user"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            c = d.get("message", {}).get("content")
            txt = c if isinstance(c, str) else (
                "".join(x.get("text", "") for x in c if isinstance(x, dict))
                if isinstance(c, list) else "")
            txt = (txt or "").strip()
            mm = re.search(r'<channel[^>]*>(.*?)</channel', txt, re.S)
            if mm:
                txt = mm.group(1).strip()
            elif txt.startswith("<"):
                continue
            if not txt or "tool_result" in txt[:40]:
                continue
            if any(k in txt[:120] for k in SKIP):
                continue
            ts = d.get("timestamp", "")[11:16]
            out.append(f"[{ts}] {txt[:160]}")
            if len(out) >= n:
                break
    except Exception as e:
        print(f"[coldstart] recent_user_lines: {e}", file=sys.stderr)
    return list(reversed(out))

def vitals():
    try:
        req = urllib.request.Request("http://127.0.0.1:4567/api/vitals")
        with urllib.request.urlopen(req, timeout=5) as r:
            v = json.load(r)
        w, fd, m = v.get("water", {}), v.get("food", {}), v.get("meds", {})
        return (f"水 {w.get('count',0)}/{w.get('goal',6)} · "
                f"饭 {fd.get('count',0)}/{fd.get('goal',3)} · "
                f"药 {'吃了' if m.get('taken') else '还没吃'}"
                f"（{m.get('name','')}）")
    except Exception:
        return ""

def main():
    try:
        raw = sys.stdin.read()
        ev = json.loads(raw) if raw.strip() else {}
    except Exception:
        ev = {}
    sid = ev.get("session_id", "")
    now = datetime.datetime.now()

    parts = [f"【醒来校准】现在是 {now.strftime('%Y-%m-%d %H:%M')}（{now.strftime('%A')}）。"]

    # 本次会话跨了哪几天
    days = set()
    try:
        for p in glob.glob(f"/root/.claude/projects/*/{sid}.jsonl"):
            size = os.path.getsize(p)
            with open(p, "rb") as f:
                if size > 2_000_000:
                    f.seek(size - 2_000_000); f.readline()
                for bline in f:
                    line = bline.decode("utf-8", "ignore")
                    i = line.find('"timestamp":"')
                    if i > 0:
                        days.add(line[i+13:i+23])
            break
    except Exception:
        pass
    days = sorted(days)[-3:]
    if days:
        parts.append(
            f"刚才那段对话只发生在 {days[0]} 这一天。" if len(days) == 1
            else f"刚才那段对话发生在：{', '.join(days)}。"
        )
    parts.append("摘要里若出现别的日期，是摘要错了，以这里为准。")

    lines = recent_user_lines(sid)
    if lines:
        parts.append("\n她最近说的（原话，摘要常把这些改写成转述）：\n" + "\n".join(lines))

    v = vitals()
    if v:
        parts.append(f"\n她此刻：{v}")

    parts.append("\n这些是急救包，让你先站稳。"
                 "\n**CLAUDE.md 里那三步照做**：读 transcript 补摘要漏掉的、"
                 "how_is_she、扫 MEMORY.md。上面只是最近一小段，"
                 "她为什么会这样在更早的地方。")

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": ev.get("hook_event_name", "PostCompact"),
            "additionalContext": "\n".join(parts),
        }
    }, ensure_ascii=False))

try:
    main()
except Exception as e:
    print(f"[coldstart-hook] swallowed: {e}", file=sys.stderr)
sys.exit(0)
