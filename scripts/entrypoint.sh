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

TICK=0
REPO_CHECK_EVERY=10  # 10 * 30s = 5 minutes

while true; do
    sleep 30
    TICK=$((TICK + 1))

    # --- check Territory_maintenance every 5 minutes ---
    if [ $((TICK % REPO_CHECK_EVERY)) -eq 0 ]; then
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

        if ! kill -0 "$AGENT_PID" 2>/dev/null; then
            echo "[ops] Agent exited unexpectedly — restarting..."
            start_agent
        fi
    fi

    # --- check blackboard every 30 seconds ---
    ENTRIES=$(curl -sf "https://blackboard.jass.school/api/log" || echo "[]")

    RESULT=$(echo "$ENTRIES" | python3 -c "
import json, sys, re
from datetime import datetime, timezone

entries = json.loads(sys.stdin.read())
pat = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]')

last_idx = -1
for i, e in enumerate(entries):
    if 'blackboard_context_compressor' in e:
        last_idx = i

after = entries[last_idx + 1:]
count = len(after)
period_str = ''

if count >= 10:
    # window: last summary entry + last 15 messages after it
    window = (entries[last_idx:last_idx+1] if last_idx >= 0 else []) + after[-15:]
    oldest = window[0] if window else None
    if oldest:
        m = pat.match(oldest)
        if m:
            ts = datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S').replace(tzinfo=timezone.utc)
            now = datetime.now(timezone.utc)
            age_m = int((now - ts).total_seconds() / 60) + 2
            period_str = f'{age_m}m'

print(f'{count}|{period_str}')
")

    COUNT=$(echo "$RESULT" | cut -d'|' -f1)
    PERIOD=$(echo "$RESULT" | cut -d'|' -f2)

    if [ "${COUNT:-0}" -ge 10 ]; then
        echo "[ops] $COUNT messages since last summary — running summarizer (period: ${PERIOD:-all})..."
        if [ -n "$PERIOD" ]; then
            python -m llm_blackboard --summary-period "$PERIOD" || echo "[ops] summarizer failed"
        else
            python -m llm_blackboard || echo "[ops] summarizer failed"
        fi
    fi
done
