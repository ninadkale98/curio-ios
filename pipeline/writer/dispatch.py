#!/usr/bin/env python3
"""
Curio writer dispatcher — decides WHAT to write this tick, claims it
deterministically, then hands it to the writer (which only writes).

Writer engine is headless Claude Code (`claude -p`), billed against the
account's Claude Pro subscription — a rolling 5-hour (and 7-day) usage
window, not pay-per-token. Two things follow from that:

1. DYNAMIC SLOT COUNT, time-of-day based (see current_slot_plan()): the user
   works with Claude interactively at night and wants the writer to stay out
   of the way then, but push hard the rest of the time so the window's
   capacity doesn't just reset unused. QUIET_START_HOUR-QUIET_END_HOUR (local
   time) runs a light/reserved slot count; outside it runs boosted.

2. REACTIVE CIRCUIT BREAKER (see is_blocked()/parse_writer_output()): each
   writer runs with --output-format stream-json so the dispatcher can read
   the real `rate_limit_event` Anthropic sends back (status/resetsAt), not
   guess from error text. On an actual block, every future tick is skipped
   until the real reset time instead of retrying (and failing) every 30 min
   for days — which is what happened under the previous engine (Codex) once
   its usage limit was hit, burning cycles for a week+ doing nothing.

Across a day's ticks the job selection itself still shapes the feed:
  1. FRESH: any item queued today (aggregator's daily adds) is written the
     same day, uncapped — it always gets its slots regardless of volume.
  2. BALANCED BACKLOG (capped at DAILY_BACKLOG_CAP, tracked separately from
     fresh so a high-volume fresh day can't starve it to zero): the modality
     written LEAST today (equal distribution) with a weighted-random strategy
     (velocity / random / recency) drains old, previously-queued content.

Claiming happens HERE via the atomic RPC, so the source/strategy are exact and
the writer only does the creative writing. Stale claims (a crashed writer) are reset
to pending at the top of each tick.
"""
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.expanduser("~/Library/Logs/curio-writer.log")
LOG_MAX = 10 * 1024 * 1024
RATE_LIMIT_STATE_FILE = os.path.join(HERE, ".rate_limit_state.json")

# --- Time-of-day dynamic scheduling (local time — this runs on the user's own
# Mac, so system local time is the user's actual wall clock). ---
QUIET_START_HOUR = 20   # 8pm: reserve capacity for the user's own Claude usage
QUIET_END_HOUR = 24     # midnight: boosted mode resumes right after
QUIET_FRESH_SLOTS = 1
QUIET_BACKLOG_SLOTS = 0
BOOST_FRESH_SLOTS = 3
BOOST_BACKLOG_SLOTS = 8
# One tick's worth of throttling after an "approaching the limit" warning
# (soft signal — not a hard block, but a reason to ease off proactively).
WARNING_BACKLOG_SLOTS = 2
WARNING_COOLDOWN_SEC = 60 * 60

DAILY_BACKLOG_CAP = 150  # safety ceiling on backlog blogs/day (fresh is uncapped, separately)
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


# --- Rate-limit circuit breaker state (local file, gitignored) ---

def read_rate_limit_state():
    try:
        with open(RATE_LIMIT_STATE_FILE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def update_rate_limit_state(**kwargs):
    state = read_rate_limit_state()
    state.update(kwargs)
    try:
        with open(RATE_LIMIT_STATE_FILE, "w") as f:
            json.dump(state, f)
    except OSError:
        pass


def is_blocked():
    """True if a real rate_limit_event told us we're rejected until some
    future time — ground truth from the API, not a guess."""
    state = read_rate_limit_state()
    blocked_until = state.get("blocked_until")
    return bool(blocked_until and time.time() < blocked_until), state


def current_slot_plan():
    """How many fresh/backlog writers this tick, based on time-of-day (stay
    out of the user's way during their own working hours, push hard the rest
    of the time) and any recent "approaching the limit" warning."""
    hour = datetime.now().hour
    if QUIET_START_HOUR <= hour < QUIET_END_HOUR:
        return QUIET_FRESH_SLOTS, QUIET_BACKLOG_SLOTS, "quiet"

    state = read_rate_limit_state()
    warned_until = state.get("warned_until")
    if warned_until and time.time() < warned_until:
        return BOOST_FRESH_SLOTS, WARNING_BACKLOG_SLOTS, "boost+throttled"

    return BOOST_FRESH_SLOTS, BOOST_BACKLOG_SLOTS, "boost"


def plan_jobs():
    """Claim this tick's items: up to fresh_slots fresh, then up to
    backlog_slots backlog across the least-written modalities (both dynamic,
    see current_slot_plan()). Returns [(item, label)]."""
    fresh_slots, backlog_slots, mode = current_slot_plan()
    log(f"mode={mode} fresh_slots={fresh_slots} backlog_slots={backlog_slots}")
    jobs = []

    # Fresh — today's newly-queued items (uncapped). Claim up to fresh_slots.
    for _ in range(fresh_slots):
        if not has_pending(fresh=True):
            break
        item = claim("fresh", None, "recent")
        if not item:
            break
        jobs.append((item, "fresh/recent"))

    # Backlog — backlog_slots across the least-written modalities (spreads
    # them), capped for the day by backlog-only completions (fresh doesn't
    # count against this, so a busy fresh day can't starve the backlog out).
    counts = written_today()
    if backlog_slots > 0 and backlog_written_today() < DAILY_BACKLOG_CAP:
        picks = sorted([s for s in MODALITIES if has_pending(source=s)], key=lambda s: counts[s])[:backlog_slots]
        for src in picks:
            strat = _weighted_strategy()
            item = claim("backlog", src, strat)
            if item:
                jobs.append((item, f"backlog/{src}/{strat}"))

    return jobs


_RATE_LIMIT_TEXT_RE = re.compile(r"usage limit|rate.?limit exceeded|you.?ve hit your", re.I)


def parse_writer_output(raw_text):
    """Pull the human-readable summary and any rate-limit signal out of a
    writer's --output-format stream-json stdout. Returns
    (summary_text_or_None, block_info_or_None, warned_bool).
    block_info, if present, has 'resetsAt' (epoch seconds or None) and
    'rateLimitType' — this is the real signal from Anthropic, not a guess."""
    summary = None
    block_info = None
    warned = False
    for line in raw_text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "rate_limit_event":
            info = obj.get("rate_limit_info", {})
            status = info.get("status")
            if status == "rejected":
                block_info = info
            elif status == "allowed_warning":
                warned = True
        elif obj.get("type") == "result":
            summary = obj.get("result") or summary
            if obj.get("is_error") and not summary:
                summary = f"error: {obj.get('subtype')}"
            if block_info is None and _RATE_LIMIT_TEXT_RE.search(json.dumps(obj)):
                block_info = {"status": "rejected", "resetsAt": None, "rateLimitType": "unknown"}
    return summary, block_info, warned


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
            summary, block_info, warned = parse_writer_output(out or "")

            if block_info is not None:
                resets_at = block_info.get("resetsAt") or (time.time() + 2 * 3600)
                rl_type = block_info.get("rateLimitType", "unknown")
                update_rate_limit_state(blocked_until=resets_at, rate_limit_type=rl_type, detected_at=time.time())
                readable = datetime.fromtimestamp(resets_at).strftime("%Y-%m-%d %H:%M")
                log(f"[{label}] {tag}: RATE LIMIT HIT ({rl_type}) — pausing the writer until {readable}, no more ticks until then")
                # Expected/handled, not a bug — no Pushover spam for this one.
            elif p.returncode != 0:
                log(f"[{label}] {tag}: {(summary or out or '').strip()[-300:]}")
                log(f"ERROR writer exit {p.returncode} on {tag}")
                notify("Curio writer FAILED", f"exit {p.returncode} on {tag} (see {LOG})")
            else:
                if warned:
                    update_rate_limit_state(warned_until=time.time() + WARNING_COOLDOWN_SEC)
                    log(f"[{label}] {tag}: (approaching the usage limit — throttling next tick) {(summary or '').strip()[-300:]}")
                else:
                    log(f"[{label}] {tag}: {(summary or out or '').strip()[-300:]}")
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
    blocked, state = is_blocked()
    if blocked:
        readable = datetime.fromtimestamp(state["blocked_until"]).strftime("%Y-%m-%d %H:%M")
        log(f"still rate-limited ({state.get('rate_limit_type', '?')}) until {readable} — skipping tick (no writers spawned)")
        return

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
