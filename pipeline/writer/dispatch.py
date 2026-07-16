#!/usr/bin/env python3
"""
Curio writer dispatcher — decides WHAT to write this tick, claims it
deterministically, then hands it to the writer (which only writes).

One blog per tick. Across a day's ticks it shapes the feed:
  1. FRESH FIRST: any item queued today (aggregator's daily adds) is written the
     same day, before any backlog. Fresh always wins, even past the daily cap.
  2. BALANCED BACKLOG (capped at DAILY_CAP): otherwise the modality written
     LEAST today (equal distribution) with a weighted-random strategy
     (velocity / random / recency).

Claiming happens HERE via the atomic RPC, so the source/strategy are exact and
claude only does the creative writing. Stale claims (a crashed writer) are reset
to pending at the top of each tick.
"""
import json
import os
import random
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.expanduser("~/Library/Logs/curio-writer.log")
LOG_MAX = 10 * 1024 * 1024

DAILY_CAP = 30
MODALITIES = ["github", "arxiv", "rss", "blog", "hn"]
STRATEGY_WEIGHTS = [("top", 45), ("random", 35), ("recent", 20)]
WRITER_TIMEOUT = 900
STALE_CLAIM_MIN = 20

SUPABASE_URL = os.environ["SUPABASE_URL"]
SB_SERVICE = os.environ["SB_SERVICE"]
PUSHOVER_TOKEN = os.environ.get("PUSHOVER_TOKEN", "")
PUSHOVER_USER = os.environ.get("PUSHOVER_USER", "")
SH = {"apikey": SB_SERVICE, "Authorization": f"Bearer {SB_SERVICE}", "Content-Type": "application/json"}


def log(msg):
    line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {msg}"
    print(line, flush=True)
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > LOG_MAX:
            os.replace(LOG, LOG + ".1")
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def notify(title, message):
    if PUSHOVER_TOKEN and PUSHOVER_USER:
        try:
            requests.post("https://api.pushover.net/1/messages.json", data={
                "token": PUSHOVER_TOKEN, "user": PUSHOVER_USER, "title": title, "message": message}, timeout=15)
        except requests.RequestException:
            pass


def _day_start():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT00:00:00Z")


def _count(params):
    r = requests.get(f"{SUPABASE_URL}/rest/v1/content_queue",
                     headers={**SH, "Prefer": "count=exact", "Range": "0-0"},
                     params={**params, "select": "id"}, timeout=30)
    return int(r.headers.get("content-range", "*/0").split("/")[-1])


def reset_stale_claims():
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=STALE_CLAIM_MIN)).strftime("%Y-%m-%dT%H:%M:%SZ")
    r = requests.patch(f"{SUPABASE_URL}/rest/v1/content_queue",
                       headers={**SH, "Prefer": "return=minimal"},
                       params={"status": "eq.claimed", "claimed_at": f"lt.{cutoff}"},
                       json={"status": "pending"}, timeout=30)
    if r.status_code < 300:
        log("reset stale claims (>%dmin) to pending" % STALE_CLAIM_MIN)


def written_today():
    return {s: _count({"source": f"eq.{s}", "status": "eq.done", "done_at": f"gte.{_day_start()}"}) for s in MODALITIES}


def has_pending(source=None, fresh=False):
    p = {"status": "eq.pending"}
    if source:
        p["source"] = f"eq.{source}"
    if fresh:
        p["created_at"] = f"gte.{_day_start()}"
    return _count(p) > 0


def claim(mode, source, strategy):
    body = {"p_mode": mode, "p_strategy": strategy, "p_source": source}
    r = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/claim_next_item", headers=SH, json=body, timeout=30)
    r.raise_for_status()
    return r.json()  # dict, or None


def write(item, mode, source, strategy):
    log(f"claimed {item['source']}/{item['source_key']} — {(item.get('title') or '')[:55]} [{mode}/{source}/{strategy}]")
    fd, path = tempfile.mkstemp(prefix="curio-claim-", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(item, f)
    env = dict(os.environ, CLAIM_FILE=path)
    try:
        r = subprocess.run(["/bin/bash", os.path.join(HERE, "run_writer.sh")],
                           env=env, capture_output=True, text=True, timeout=WRITER_TIMEOUT)
        log((r.stdout or "")[-600:])
        if r.returncode != 0:
            log(f"ERROR writer exit {r.returncode}")
            notify("Curio writer FAILED", f"exit {r.returncode} on {item['source']}/{item['source_key']} (see {LOG})")
    except subprocess.TimeoutExpired:
        log("ERROR writer timed out")
        notify("Curio writer FAILED", f"timed out on {item['source']}/{item['source_key']} (see {LOG})")
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def main():
    reset_stale_claims()
    counts = written_today()
    total = sum(counts.values())
    log(f"tick — today: {counts} (total {total}/{DAILY_CAP})")

    # 1. FRESH FIRST
    if has_pending(fresh=True):
        item = claim("fresh", None, "recent")
        if item:
            write(item, "fresh", "any", "recent")
            return

    # 2. BALANCED BACKLOG, capped
    if total >= DAILY_CAP:
        log("daily cap reached")
        return
    available = [s for s in MODALITIES if has_pending(source=s)]
    if not available:
        log("no pending backlog")
        return
    source = min(available, key=lambda s: counts[s])
    strategy = random.choices([s for s, _ in STRATEGY_WEIGHTS], weights=[w for _, w in STRATEGY_WEIGHTS])[0]
    item = claim("backlog", source, strategy)
    if item:
        write(item, "backlog", source, strategy)
    else:
        log(f"claim returned null for {source}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"ERROR dispatcher: {e}")
        notify("Curio writer FAILED", f"dispatcher error: {e}")
        sys.exit(1)
