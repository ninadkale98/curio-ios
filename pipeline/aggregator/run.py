"""
Aggregator orchestrator.

  python -m aggregator.run --backfill --only github            # one-time deep pull
  python -m aggregator.run --backfill --only github --resume   # continue a crashed backfill
  python -m aggregator.run --only github                       # steady-state (what the cron runs)

Per topic: results are appended to a local JSONL (state/<source>.jsonl) for
inspection AND upserted to content_queue, then the topic is recorded in a
checkpoint file. So progress always persists — a crash or rate-limit stop can
be continued with --resume, and finished topics are skipped.
"""

import argparse
import json
import logging
import os
import pathlib

import requests

from . import db
from .queue_item import QueueItem
from .sources import github, papers, articles, hn

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

STATE_DIR = pathlib.Path(__file__).parent / "state"

# name -> per-topic generator: (backfill, existing_keys, existing_story_urls, done_topics) -> yields (topic, [QueueItem])
SOURCES = {
    "github": github.iter_topics,
    "arxiv": papers.iter_topics,
    "rss": articles.iter_rss,
    "blog": articles.iter_blog,
    "hn": hn.iter_topics,
}


def _checkpoint_path(source: str, backfill: bool) -> pathlib.Path:
    return STATE_DIR / f"{source}_{'backfill' if backfill else 'incremental'}.checkpoint.json"


def _load_done(path: pathlib.Path, resume: bool) -> set[str]:
    if resume and path.exists():
        return set(json.loads(path.read_text()).get("done_topics", []))
    return set()


def _save_done(path: pathlib.Path, done: set[str]):
    path.write_text(json.dumps({"done_topics": sorted(done)}, indent=2))


def _append_jsonl(path: pathlib.Path, items: list[QueueItem]):
    with path.open("a") as f:
        for it in items:
            f.write(json.dumps(it.__dict__) + "\n")


def run_source(name: str, backfill: bool, resume: bool, story_urls: set[str]):
    STATE_DIR.mkdir(exist_ok=True)
    ckpt = _checkpoint_path(name, backfill)
    jsonl = STATE_DIR / f"{name}.jsonl"

    done = _load_done(ckpt, resume)
    existing = db.existing_keys(name)
    log.info(f"{name}: {len(existing)} already queued, {len(story_urls)} already published"
             + (f", resuming ({len(done)} topics done)" if done else ""))

    total = 0
    for topic, items in SOURCES[name](backfill, existing, story_urls, done_topics=done):
        if items:
            _append_jsonl(jsonl, items)
            db.upsert(items)
            total += len(items)
        done.add(topic)
        _save_done(ckpt, done)
        log.info(f"{name}/{topic}: +{len(items)} (running total {total})")

    log.info(f"{name}: done — {total} new candidates queued this run")
    return total


def _notify(added: dict[str, int]):
    """Pushover summary of what the run added. No-op unless PUSHOVER_TOKEN/USER
    are set (the daily GitHub Action sets them; local runs stay quiet)."""
    token, user = os.getenv("PUSHOVER_TOKEN"), os.getenv("PUSHOVER_USER")
    if not (token and user):
        return
    total = sum(added.values())
    lines = [f"{k}: +{v}" for k, v in added.items() if v]
    body = ("\n".join(lines) or "nothing new") + f"\n\ntotal: +{total}"
    try:
        requests.post("https://api.pushover.net/1/messages.json", data={
            "token": token, "user": user,
            "title": f"Curio pipeline: +{total} queued" if total else "Curio pipeline: nothing new",
            "message": body,
        }, timeout=15)
    except requests.RequestException as e:
        log.warning(f"pushover notify failed: {e}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backfill", action="store_true", help="deep one-time historical pull instead of the incremental skim")
    parser.add_argument("--resume", action="store_true", help="continue from the checkpoint, skipping finished topics")
    parser.add_argument("--only", action="append", choices=SOURCES.keys(), help="run just these sources (repeatable)")
    parser.add_argument("--skip", action="append", choices=SOURCES.keys(), default=[], help="skip these sources")
    args = parser.parse_args()

    targets = args.only or list(SOURCES.keys())
    targets = [s for s in targets if s not in args.skip]

    story_urls = db.existing_story_urls()
    added: dict[str, int] = {}
    for name in targets:
        log.info(f"=== {name} ({'backfill' if args.backfill else 'incremental'}) ===")
        added[name] = run_source(name, args.backfill, args.resume, story_urls)

    # Refresh rank_score so the writer's 'top' strategy sees current signals.
    try:
        requests.post(f"{db.SUPABASE_URL}/rest/v1/rpc/refresh_rank_scores",
                      headers={"apikey": db.SERVICE_ROLE_KEY, "Authorization": f"Bearer {db.SERVICE_ROLE_KEY}",
                               "Content-Type": "application/json"}, json={}, timeout=180)
        log.info("rank scores refreshed")
    except requests.RequestException as e:
        log.warning(f"rank refresh failed: {e}")

    if not args.backfill:  # only notify on the steady-state (cron) runs
        _notify(added)


if __name__ == "__main__":
    main()
