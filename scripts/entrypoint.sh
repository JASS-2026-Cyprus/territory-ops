#!/bin/bash
set -e

cd /app

REPO="JASS-2026-Cyprus/Territory_maintenance"

start_agent() {
    python main.py &
    AGENT_PID=$!
    echo "[ops] Agent started (PID $AGENT_PID)"
}

LAST_SHA=$(git rev-parse HEAD)
start_agent

while true; do
    sleep 600

    # --- check Territory_maintenance for updates ---
    CURRENT_SHA=$(curl -sf \
        -H "Authorization: token ${GH_PAT}" \
        "https://api.github.com/repos/${REPO}/commits/main" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])" 2>/dev/null || true)

    if [ -n "$CURRENT_SHA" ] && [ "$CURRENT_SHA" != "$LAST_SHA" ]; then
        echo "[ops] New commit $CURRENT_SHA — pulling and reloading..."
        git pull "https://x-access-token:${GH_PAT}@github.com/${REPO}.git" main
        pip install -q --no-cache-dir -r requirements.txt
        kill "$AGENT_PID" 2>/dev/null; wait "$AGENT_PID" 2>/dev/null || true
        LAST_SHA="$CURRENT_SHA"
        start_agent
    fi

    # restart agent if it crashed
    if ! kill -0 "$AGENT_PID" 2>/dev/null; then
        echo "[ops] Agent exited unexpectedly — restarting..."
        start_agent
    fi

    # --- check blackboard ---
    COUNT=$(curl -sf "https://blackboard.jass.school/api/log" \
        | python3 -c "
import json, sys
entries = json.loads(sys.stdin.read())
last_idx = -1
for i, e in enumerate(entries):
    if 'blackboard_context_compressor' in e:
        last_idx = i
print(len(entries) - last_idx - 1)
" 2>/dev/null || echo 0)

    if [ "${COUNT:-0}" -ge 10 ]; then
        echo "[ops] $COUNT messages since last summary — running summarizer..."
        python -m llm_blackboard || echo "[ops] summarizer failed"
    fi
done
