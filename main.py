import os
import re
import subprocess
import time
from datetime import datetime, timezone

import requests

REPO = "JASS-2026-Cyprus/Territory_maintenance"
MAINTENANCE_DIR = "/maintenance"
GH_PAT = os.environ["GH_PAT"]
LLM_API_KEY = os.environ["LLM_API_KEY"]


def get_remote_sha():
    r = requests.get(
        f"https://api.github.com/repos/{REPO}/commits/main",
        headers={"Authorization": f"token {GH_PAT}"},
        timeout=10,
    )
    return r.json()["sha"]


def pull_repo():
    subprocess.run(
        ["git", "pull", f"https://x-access-token:{GH_PAT}@github.com/{REPO}.git", "main"],
        cwd=MAINTENANCE_DIR, check=True,
    )
    subprocess.run(
        ["pip", "install", "-q", "--no-cache-dir", "-r", "requirements.txt"],
        cwd=MAINTENANCE_DIR, check=True,
    )


def start_agent():
    p = subprocess.Popen(["python", "main.py"], cwd=MAINTENANCE_DIR)
    print(f"[ops] Agent started (PID {p.pid})", flush=True)
    return p


def check_blackboard():
    r = requests.get("https://blackboard.jass.school/api/log", timeout=10)
    entries = r.json()
    last_idx = -1
    for i, e in enumerate(entries):
        if "blackboard_context_compressor" in e:
            last_idx = i
    count = len(entries) - last_idx - 1
    return entries, last_idx, count


def run_summarizer(entries, last_idx):
    after = entries[last_idx + 1:]
    window = (entries[last_idx : last_idx + 1] if last_idx >= 0 else []) + after[-15:]
    period_arg = []
    if window:
        m = re.match(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]", window[0])
        if m:
            ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            age_m = int((datetime.now(timezone.utc) - ts).total_seconds() / 60) + 2
            period_arg = ["--summary-period", f"{age_m}m"]
    subprocess.run(
        ["python", "-m", "llm_blackboard"] + period_arg,
        cwd=MAINTENANCE_DIR,
        env={**os.environ, "LLM_API_KEY": LLM_API_KEY},
    )


def main():
    last_sha = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=MAINTENANCE_DIR
    ).decode().strip()

    agent = start_agent()
    tick = 0

    while True:
        time.sleep(30)
        tick += 1

        # every 5 minutes: check Territory_maintenance for updates
        if tick % 10 == 0:
            try:
                sha = get_remote_sha()
                if sha != last_sha:
                    print(f"[ops] New commit {sha} — reloading...", flush=True)
                    agent.kill()
                    agent.wait()
                    pull_repo()
                    last_sha = sha
                    agent = start_agent()
            except Exception as e:
                print(f"[ops] Repo check failed: {e}", flush=True)

            if agent.poll() is not None:
                print("[ops] Agent exited — restarting...", flush=True)
                agent = start_agent()

        # every 30 seconds: check blackboard
        try:
            entries, last_idx, count = check_blackboard()
            if count >= 10:
                print(f"[ops] {count} messages since last summary — summarizing...", flush=True)
                run_summarizer(entries, last_idx)
        except Exception as e:
            print(f"[ops] Blackboard check failed: {e}", flush=True)


if __name__ == "__main__":
    main()
