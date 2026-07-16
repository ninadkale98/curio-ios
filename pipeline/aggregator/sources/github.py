"""
GitHub source — ported from content/github_sync.py's fetch logic, retargeted
to produce QueueItems instead of writing to the old repos/feed_items schema.

Strategy:
  - Search each topic, sorted by stars desc. Since stars accumulate over a
    repo's lifetime, "sorted by stars" already surfaces old-but-great repos
    alongside new breakouts — there's no separate GitHub search filter for
    "historically relevant," so depth (how many pages we pull) is the lever:
      * backfill: 3 pages/topic (~150 repos/topic, up to ~4,000 total)
      * incremental: 1 page/topic (~50 repos/topic — new entrants climb into
        the top 50 fast enough that this catches them within a few cycles)
  - Only fetch a repo's full README (the expensive, rate-limited call) for
    repos NOT already in content_queue — existing rows are left completely
    untouched (no upsert at all) so we never overwrite a stored README with
    a blank one on rediscovery.
  - No "is this repo good enough" judgment here — that's the writer wing's
    job once it exists. The aggregator is deliberately inclusive.
"""

import logging
import os
import time
from datetime import datetime, timedelta, timezone

import requests

from ..queue_item import QueueItem

log = logging.getLogger(__name__)

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")

HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}
if GITHUB_TOKEN:
    HEADERS["Authorization"] = f"Bearer {GITHUB_TOKEN}"

# Audience-focused list (~40) — Curio's existing stories are all AI / systems /
# infra / robotics, so the generic web-dev topics from the old scraper
# (react/nextjs/nodejs/typescript) are dropped in favor of the 2026 AI-systems
# clusters (mcp, rag, llm-inference, local-llm, ...). Grouped only for humans;
# fetch() iterates ALL_TOPICS flat. Any slug that returns 0 results is simply
# skipped at run time.
TOPICS = {
    "ai-core": ["llm", "machine-learning", "deep-learning", "computer-vision", "nlp",
                "generative-ai", "diffusion-models", "reinforcement-learning", "neural-network"],
    "ai-systems": ["ai-agents", "mcp", "rag", "llm-inference", "vector-database",
                   "vector-search", "fine-tuning", "local-llm"],
    "systems": ["kernel", "operating-system", "os-dev", "compiler", "embedded",
                "wasm", "memory-management"],
    "infra": ["database", "postgresql", "redis", "distributed-systems", "kubernetes",
              "gpu", "cuda", "observability"],
    "robotics": ["robotics", "slam", "autonomous-driving", "arduino", "raspberry-pi", "iot"],
    "security": ["cybersecurity", "cryptography", "reverse-engineering"],
    "langs": ["rust", "zig"],
}
ALL_TOPICS = [t for group in TOPICS.values() for t in group]

# How far back "recent breakouts" reaches for the freshness pass.
BREAKOUT_WINDOW_DAYS = 180

# Pages of all-time results per topic. Backfill goes deep (thorough one-time
# pull); incremental just skims the top since new entrants climb fast.
BACKFILL_PAGES = 5
INCREMENTAL_PAGES = 1

# Authed search API is capped at 30 req/min; 2.5s between calls keeps us at
# ~24/min with headroom. Unauthed is 10/min → 6s.
SEARCH_PAUSE = 2.5 if GITHUB_TOKEN else 6


def _get(url: str, params: dict = None, retries: int = 3):
    for attempt in range(retries):
        try:
            r = requests.get(url, headers=HEADERS, params=params, timeout=15)
            if r.status_code == 403 and "rate limit" in r.text.lower():
                reset = int(r.headers.get("X-RateLimit-Reset", time.time() + 60))
                wait = max(reset - time.time(), 1)
                log.warning(f"Rate limited. Sleeping {wait:.0f}s")
                time.sleep(wait)
                continue
            if r.status_code == 200:
                return r.json()
            log.warning(f"GET {url} -> {r.status_code}: {r.text[:200]}")
            return None
        except requests.RequestException as e:
            log.warning(f"Request error (attempt {attempt + 1}): {e}")
            time.sleep(2 ** attempt)
    return None


def search_repos(topic: str, page: int, per_page: int = 50, created_after: str | None = None) -> list[dict]:
    q = f"topic:{topic}"
    if created_after:
        q += f" created:>{created_after}"
    data = _get(
        "https://api.github.com/search/repositories",
        params={"q": q, "sort": "stars", "order": "desc", "per_page": per_page, "page": page},
    )
    return data.get("items", []) if data else []


def _stars_per_day(stars: int, created_at: str | None) -> float | None:
    """Velocity proxy the writer wing sorts on — stars accrued per day of the
    repo's life. A young repo with high stars/day is a stronger 'cover this now'
    signal than an old one with a huge but slow-earned total."""
    if not created_at:
        return None
    try:
        created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    age_days = max((datetime.now(timezone.utc) - created).days, 1)
    return round(stars / age_days, 2)


def _to_queue_item(topic: str, raw: dict) -> QueueItem:
    # No per-repo README fetch here — the aggregator is a discovery + metadata
    # layer only. The writer wing fetches the README / does its own research
    # when it drains this item, so raw_text is left empty for github.
    full_name = raw["full_name"]
    stars = raw["stargazers_count"]
    created_at = raw.get("created_at")
    return QueueItem(
        source="github",
        source_key=str(raw["id"]),
        url=raw["html_url"],
        title=full_name,
        summary=raw.get("description"),
        raw_text=None,
        raw_json={
            "full_name": full_name,
            "owner": raw["owner"]["login"],
            "stars": stars,
            "forks": raw["forks_count"],
            "stars_per_day": _stars_per_day(stars, created_at),
            "language": raw.get("language"),
            "license": (raw.get("license") or {}).get("name"),
            "homepage": raw.get("homepage") or None,
            "topics": raw.get("topics", []),
            "created_at": created_at,
            "pushed_at": raw.get("pushed_at"),
        },
        image_url=f"https://opengraph.githubassets.com/1/{full_name}",
        topic=topic,
        published_at=created_at,
    )


def iter_topics(
    backfill: bool,
    existing_keys: set[str],
    existing_story_urls: set[str] = frozenset(),
    done_topics: set[str] = frozenset(),
):
    """Yield (topic, [QueueItem]) one topic at a time so the caller can upsert +
    checkpoint incrementally — a crash mid-backfill never loses finished topics,
    and a --resume run skips whatever's in done_topics."""
    pages_per_topic = BACKFILL_PAGES if backfill else INCREMENTAL_PAGES
    breakout_cutoff = (datetime.now(timezone.utc) - timedelta(days=BREAKOUT_WINDOW_DAYS)).strftime("%Y-%m-%d")
    seen_ids: set[str] = set()

    for topic in ALL_TOPICS:
        if topic in done_topics:
            continue

        topic_items: list[QueueItem] = []

        def collect(results: list[dict]):
            for raw in results:
                repo_id = str(raw["id"])
                if repo_id in existing_keys or repo_id in seen_ids or raw["html_url"] in existing_story_urls:
                    continue
                seen_ids.add(repo_id)
                # All metadata comes from the search response — no per-repo call.
                topic_items.append(_to_queue_item(topic, raw))

        # Channel 1 — all-time greats (deep-paginated in backfill mode).
        for page in range(1, pages_per_topic + 1):
            results = search_repos(topic, page)
            if not results:
                break
            collect(results)
            time.sleep(SEARCH_PAUSE)

        # Channel 2 — recent breakouts (always just the top page; few high-star
        # repos are <6mo old, so deeper pages add little). Fixes the "same
        # famous repos forever" bias by surfacing risers before they're classics.
        collect(search_repos(topic, page=1, created_after=breakout_cutoff))
        time.sleep(SEARCH_PAUSE)

        yield topic, topic_items
