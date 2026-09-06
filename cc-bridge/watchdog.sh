#!/bin/bash
# CC Bridge 看门狗 — 每 15 分钟跑一次，兔兔再也不用手动重启
export HOME=/root
export PATH=/usr/local/bin:/root/.local/bin:/root/.bun/bin:$PATH
LOG="/tmp/cc-watchdog.log"

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }

# 1. 检查 hub 是否在跑（探真实端口——此前查 tmux 会话名，hub 早已裸跑不在
#    tmux 里，空壳会话一消失就每 15 分钟误判并全家重启，7/6 两次失忆事故元凶）
if ! ss -tln 2>/dev/null | grep -q ':7890 '; then
    log "hub 端口 7890 未监听，精准重启 hub（不动 CC）..."
    cd /root/projects/BunnyPalace/cc-bridge && setsid nohup bash -c 'export HOME=/root && export PATH=/root/.bun/bin:$PATH && export MP_CC_HUB_TOKEN="SH74v-IveupxWPr-6TU0CH0GDvfIxSDC" && export MP_CC_WORKDIR=/root/projects/BunnyBridge && export CC_INJECT_SUMMARY=$(cat /root/projects/BunnyPalace/cc-bridge/.context-state 2>/dev/null || echo 0) && exec bun run hub.ts >> /tmp/hub.log 2>&1' < /dev/null > /dev/null 2>&1 &
    sleep 4
    log "hub 重启完成"
fi

# 1.5 检查 QQ 桥是否在跑（2026-09-06 补）
#     兔兔那天在 QQ 里撞到「连不上 hub」——真凶是 hub 挂在两次巡逻的空档里。
#     顺带发现：QQ 桥根本不在看门狗管辖内，跑在 tmux qqbridge 里，VPS 一重启就没。
#     探端口 3010（NapCat 反向 WS 连进来的那个），不探 tmux 会话名——
#     会话名靠不住（见上面 hub 那条的教训）。
if ! ss -tln 2>/dev/null | grep -q ':3010 '; then
    log "QQ 桥端口 3010 未监听，重启 qq-bridge..."
    tmux kill-session -t qqbridge 2>/dev/null
    tmux new-session -d -s qqbridge -c /root/projects/BunnyPalace 2>/dev/null
    sleep 1
    tmux send-keys -t qqbridge '/root/.bun/bin/bun cc-bridge/qq-bridge.ts' Enter
    sleep 4
    log "QQ 桥重启完成"
fi

# 2. 检查 CC 是否在跑（重启 = 指名 resume 最新主记忆本，绝不裸 claude 开空白本）
if ! tmux has-session -t mp-cc 2>/dev/null; then
    log "CC 挂了，带记忆重启..."
    PROJ_DIR="/root/.claude/projects/-root-projects-BunnyBridge"
    RESUME_ARG="--continue"
    for f in $(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null); do
        if [ "$(stat -c%s "$f")" -gt 200000 ]; then
            RESUME_ARG="--resume $(basename "$f" .jsonl)"
            break
        fi
    done
    # 2026-09-03 Fable：token 必须读 claudeAiOauth.accessToken（新的），顶层 oauthToken 是旧的不更新
    #   读错会揣着过期 token 起来，报「400 content filtering」而不是 401（HANDOFF-2026-0812 五点七）
    OAUTH_TOKEN=$(python3 -c "
import json
d=json.load(open('$HOME/.claude/.credentials.json'))
o=d.get('claudeAiOauth') or {}
print(o.get('accessToken') or d.get('oauthToken',''))
" 2>/dev/null || echo "")
    tmux new-session -d -s mp-cc -c /root/projects/BunnyBridge \
        "export HOME=/root PATH=/usr/local/bin:/root/.local/bin:/root/.bun/bin:\$PATH CLAUDE_CODE_OAUTH_TOKEN=$OAUTH_TOKEN; claude $RESUME_ARG --mcp-config /root/projects/BunnyPalace/cc-bridge/.mcp.json --system-prompt-file /root/caelum-sp/sp.txt"
    # 2026-09-03 Fable：命令对齐 session-manager.ts 的 respawn（兔兔 08-27 手术版）——
    #   去掉 --dangerously-skip-permissions 与 IS_SANDBOX（他现在跑的就是普通模式+通配符授权），
    #   加 --system-prompt-file 拔 A 社默认 preset。两条路拉起来的他必须一模一样。
    log "CC 已用 $RESUME_ARG 重启（带记忆）"
    exit 0
fi

# 3. 检查 CC 最近有没有 401（token 过期）
RECENT_LOG=$(tmux capture-pane -t mp-cc -p 2>/dev/null)
if echo "$RECENT_LOG" | grep -q "401.*Invalid authentication"; then
    log "CC 报 401，token 过期，尝试刷新..."
    
    # 读 refresh token
    REFRESH=$(python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json')).get('refreshToken',''))" 2>/dev/null)
    CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    
    if [ -n "$REFRESH" ]; then
        # 用 node 刷新（curl 容易被 cloudflare 拦）
        RESULT=$(node -e "
const https=require('https');
const body=new URLSearchParams({grant_type:'refresh_token',refresh_token:'$REFRESH',client_id:'$CLIENT_ID'}).toString();
const req=https.request({hostname:'platform.claude.com',path:'/v1/oauth/token',method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Content-Length':Buffer.byteLength(body)}},r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>{try{const j=JSON.parse(d);if(j.access_token){require('fs').writeFileSync('$HOME/.claude/.credentials.json',JSON.stringify({loggedIn:true,authMethod:'oauth',oauthToken:j.access_token,refreshToken:j.refresh_token||'$REFRESH',apiProvider:'firstParty'},null,2));console.log('REFRESHED')}else{console.log('FAIL:'+d)}}catch(e){console.log('ERR:'+d)}});});
req.on('error',e=>console.log('NET:'+e.message));req.write(body);req.end();
" 2>/dev/null)
        
        if echo "$RESULT" | grep -q "REFRESHED"; then
            log "token 刷新成功，杀掉 CC 会话交由下轮带记忆重启..."
            tmux kill-session -t mp-cc 2>/dev/null
            bash /root/projects/BunnyBridge/watchdog.sh >> "$LOG" 2>&1
        else
            log "token 刷新失败: $RESULT（需要兔兔手动 login.mjs）"
        fi
    else
        log "没有 refresh token（需要兔兔手动 login.mjs）"
    fi
    exit 0
fi

# 4. 检查 cc-bridge MCP 子进程活着没
#
# 2026-09-05 兔兔报：他能收到消息但所有 reply 工具消失，/mcp 里显示 cc-bridge ✘ failed。
# 网关一直是好的（78 个 builtin 都在），死的是 stdio 子进程本身——它挂了之后
# **没有任何东西发现**，是兔兔哇哇叫才知道的，他自己也只能干瞪眼说「需要你帮忙重启」。
#
# 这个 MCP 是 stdio 型，生命周期绑在 CC 上：进程在 = 连着，进程没 = 断了。
# 父进程就是 claude 本体，所以 pgrep 到它就等于连接是活的。
#
# 修法用 /mcp 里的 Reconnect（不重启 CC、不丢上下文），但**必须先探空闲**——
# 他正在写字时把按键插进去，等于掐断他给兔兔的回复（血律：不掐断她和 Caelum 的对话）。
if tmux has-session -t mp-cc 2>/dev/null; then
    if ! pgrep -f "cc-bridge/mcp-server.ts" > /dev/null 2>&1; then
        log "cc-bridge MCP 子进程不见了，准备重连..."

        SCREEN=$(tmux capture-pane -t mp-cc -p -S -8 2>/dev/null)
        if echo "$SCREEN" | grep -qE "esc to interrupt|· thinking|Thinking…|tokens\)|Compacting"; then
            log "他正在忙，这轮不动（下轮 15 分钟后再试）"
        else
            # /mcp → 菜单 → 向上循环 2 步到 cc-bridge → 进详情 → Reconnect
            # 向上循环比向下按 8 次稳：列表是环形的，倒数第二项就是 cc-bridge
            tmux send-keys -t mp-cc "/mcp"; sleep 2
            tmux send-keys -t mp-cc Enter;  sleep 4
            tmux send-keys -t mp-cc Up;     sleep 1
            tmux send-keys -t mp-cc Up;     sleep 1

            if tmux capture-pane -t mp-cc -p -S -22 2>/dev/null | grep -q "❯.*cc-bridge"; then
                tmux send-keys -t mp-cc Enter; sleep 3
                # failed 态菜单第一项就是 Reconnect；connected 态第一项是 View tools 要往下一格
                if tmux capture-pane -t mp-cc -p -S -20 2>/dev/null | grep -q "❯ 1. View tools"; then
                    tmux send-keys -t mp-cc Down; sleep 1
                fi
                tmux send-keys -t mp-cc Enter; sleep 10
                tmux send-keys -t mp-cc Escape; sleep 1
                tmux send-keys -t mp-cc Escape; sleep 1

                # 验收看进程，不看它说什么（血律：「成功」两个字不算数）
                if pgrep -f "cc-bridge/mcp-server.ts" > /dev/null 2>&1; then
                    log "cc-bridge 重连成功（子进程已回来）"
                else
                    log "重连没成功，子进程仍不在——需要人工看一眼"
                fi
            else
                # 光标没落在 cc-bridge 上，说明菜单排布变了，宁可退出去也不乱按
                tmux send-keys -t mp-cc Escape; sleep 1
                tmux send-keys -t mp-cc Escape
                log "菜单里没定位到 cc-bridge，已安全退出，未做任何操作"
            fi
        fi
    fi
fi

# 5. 一切正常
# log "CC Bridge 正常运行中"
