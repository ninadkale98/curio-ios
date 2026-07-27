#!/usr/bin/env python3
"""
Curio writer dispatcher — decides WHAT to write this tick, claims it
deterministically, then hands it to the writer (which only writes).

Up to FRESH_SLOTS + BACKLOG_SLOTS writers per tick (every 30 min). Across a
day's ticks it shapes the feed:
  1. FRESH: any item queued today (aggregator's daily adds) is written the
     same day, uncapped — it always gets its slots regardless of volume.
  2. BALANCED BACKLOG (capped at DAILY_BACKLOG_CAP, tracked separately from
     fresh so a high-volume fresh day can't starve it to zero): the modality
     written LEAST today (equal distribution) with a weighted-random strategy
     (velocity / random / recency) drains old, previously-queued content.

Target: ~100 blogs/day, split across both today's new content and the older
backlog — not fresh-only.

Claiming happens HERE via the atomic RPC, so the source/strategy are exact and
the writer only does the creative writing. Stale claims (a crashed writer) are reset
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

FRESH_SLOTS = 3       # writers per tick dedicated to today's newly-queued items
BACKLOG_SLOTS = 4     # writers per tick draining the backlog (old, previously-queued content)
DAILY_BACKLOG_CAP = 70  # safety ceiling on backlog blogs/day (fresh is uncapped, separately)
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
    # Write only to the file — under launchd, stdout is already redirected to
    # this same file, so also print()ing would double every line.
    line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {msg}"
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


def backlog_written_today():
    # Only rows queued BEFORE today (created_at < today) count as "backlog" —
    # a fresh item finished today must not eat into the backlog cap, or a
    # high-volume aggregator day starves backlog down to zero (the original
    # bug: the cap was checked against combined fresh+backlog totals).
    return _count({"status": "eq.done", "done_at": f"gte.{_day_start()}", "created_at": f"lt.{_day_start()}"})


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


def _weighted_strategy():
    return random.choices([s for s, _ in STRATEGY_WEIGHTS], weights=[w for _, w in STRATEGY_WEIGHTS])[0]


def plan_jobs():
    """Claim this tick's items: up to FRESH_SLOTS fresh, then up to BACKLOG_SLOTS
    backlog across the least-written modalities. Returns [(item, label)]."""
    jobs = []

    # Fresh — today's newly-queued items (uncapped). Claim up to FRESH_SLOTS.
    for _ in range(FRESH_SLOTS):
        if not has_pending(fresh=True):
            break
        item = claim("fresh", None, "recent")
        if not item:
            break
        jobs.append((item, "fresh/recent"))

    # Backlog — BACKLOG_SLOTS across the least-written modalities (spreads
    # them), capped for the day by backlog-only completions (fresh doesn't
    # count against this, so a busy fresh day can't starve the backlog out).
    counts = written_today()
    if backlog_written_today() < DAILY_BACKLOG_CAP:
        picks = sorted([s for s in MODALITIES if has_pending(source=s)], key=lambda s: counts[s])[:BACKLOG_SLOTS]
        for src in picks:
            strat = _weighted_strategy()
            item = claim("backlog", src, strat)
            if item:
                jobs.append((item, f"backlog/{src}/{strat}"))

    return jobs


def run_batch(jobs):
    """Spawn all writers in parallel, then collect each result."""
    procs = []
    for item, label in jobs:
        fd, path = tempfile.mkstemp(prefix="curio-claim-", suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(item, f)
        log(f"spawn [{label}] {item['source']}/{item['source_key']} — {(item.get('title') or '')[:50]}")
        p = subprocess.Popen(["/bin/bash", os.path.join(HERE, "run_writer.sh")],
                             env=dict(os.environ, CLAIM_FILE=path),
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        procs.append((p, path, item, label))

    for p, path, item, label in procs:
        tag = f"{item['source']}/{item['source_key']}"
        try:
            out, _ = p.communicate(timeout=WRITER_TIMEOUT)
            log(f"[{label}] {tag}: {(out or '').strip()[-300:]}")
            if p.returncode != 0:
                log(f"ERROR writer exit {p.returncode} on {tag}")
                notify("Curio writer FAILED", f"exit {p.returncode} on {tag} (see {LOG})")
        except subprocess.TimeoutExpired:
            p.kill()
            log(f"ERROR writer timed out on {tag}")
            notify("Curio writer FAILED", f"timed out on {tag} (see {LOG})")
        finally:
            try:
                os.remove(path)
            except OSError:
                pass


def main():
    reset_stale_claims()
    counts = written_today()
    log(f"tick — today: {counts} (total {sum(counts.values())})")
    jobs = plan_jobs()
    if not jobs:
        log("nothing to do this tick")
        return
    log(f"batch of {len(jobs)}: {[l for _, l in jobs]}")
    run_batch(jobs)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"ERROR dispatcher: {e}")
        notify("Curio writer FAILED", f"dispatcher error: {e}")
        sys.exit(1)
