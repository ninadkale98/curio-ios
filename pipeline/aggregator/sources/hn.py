"""
Hacker News source — high-signal AI/tech stories via the Algolia HN search API
(no key). Unlike RSS, HN has a real engagement signal: story `points`. So the
ranking signal here is `score` (points) + comment count — the community's own
verdict on what's worth reading.

Dedup key = HN objectID (hn_id). The story's external link (the article/repo it
points to) is the actual content; we store it as `url` when present, falling
back to the HN discussion for Ask/Show HN. Metadata-only: the writer wing reads
the linked article itself.
"""

import logging
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

import requests

from ..queue_item import QueueItem

log = logging.getLogger(__name__)

HN_API = "https://hn.algolia.com/api/v1/search"
HEADERS = {"User-Agent": "Curio-Bot/1.0 (HN discovery)"}

# AI/ML/tech query terms — broad enough to catch the field, narrow enough to
# skip generic news.
SEARCH_QUERIES = [
    "LLM", "large language model", "machine learning", "artificial intelligence",
    "neural network", "RAG retrieval augmented", "diffusion model", "PyTorch",
    "Hugging Face", "transformer model", "open source AI", "GPU inference",
    "vector database", "reinforcement learning", "robotics AI",
]

# Backfill reaches deep for the all-time notable stories; incremental catches
# fresh risers. Higher score bar on backfill keeps it to genuinely notable posts.
BACKFILL_DAYS = 2000
BACKFILL_MIN_SCORE = 150
INCREMENTAL_DAYS = 3
INCREMENTAL_MIN_SCORE = 50


def _parse_story(hit: dict, query: str) -> dict | None:
    hn_id = hit.get("objectID")
    if not hn_id:
        return None
    url = hit.get("url") or None
    domain = urlparse(url).netloc.lstrip("www.") if url else None
    created_at = None
    if hit.get("created_at"):
        try:
            created_at = datetime.fromisoformat(hit["created_at"].replace("Z", "+00:00"))
        except ValueError:
            pass
    tags = hit.get("_tags", [])
    story_type = "ask_hn" if "ask_hn" in tags else "show_hn" if "show_hn" in tags else "story"
    return {
        "hn_id": str(hn_id),
        "title": (hit.get("title") or "").strip(),
        "external_url": url,
        "domain": domain,
        "hn_url": f"https://news.ycombinator.com/item?id={hn_id}",
        "author": hit.get("author"),
        "score": hit.get("points", 0) or 0,
        "num_comments": hit.get("num_comments", 0) or 0,
        "story_type": story_type,
        "created_at": created_at,
        "matched_query": query,
    }


def fetch_stories_for_query(query: str, min_score: int, days_back: int) -> list[dict]:
    cutoff = int((datetime.now(timezone.utc) - timedelta(days=days_back)).timestamp())
    params = {
        "query": query,
        "tags": "story",
        "numericFilters": f"points>={min_score},created_at_i>{cutoff}",
        "hitsPerPage": 1000,
    }
    try:
        r = requests.get(HN_API, params=params, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return [s for h in r.json().get("hits", []) if (s := _parse_story(h, query))]
    except requests.RequestException as e:
        log.warning(f"HN fetch failed for '{query}': {e}")
        return []


def _to_queue_item(s: dict) -> QueueItem:
    return QueueItem(
        source="hn",
        source_key=s["hn_id"],
        url=s["external_url"] or s["hn_url"],  # the linked article is the content
        title=s["title"],
        summary=None,
        raw_text=None,
        raw_json={
            "discovered_via": "hn",
            "score": s["score"],
            "num_comments": s["num_comments"],
            "hn_url": s["hn_url"],
            "external_url": s["external_url"],
            "domain": s["domain"],
            "story_type": s["story_type"],
            "author": s["author"],
            "matched_query": s["matched_query"],
        },
        image_url=None,
        topic=s["matched_query"],
        published_at=s["created_at"].isoformat() if s["created_at"] else None,
    )


def iter_topics(backfill, existing_keys, existing_story_urls=frozenset(), done_topics=frozenset()):
    min_score = BACKFILL_MIN_SCORE if backfill else INCREMENTAL_MIN_SCORE
    days_back = BACKFILL_DAYS if backfill else INCREMENTAL_DAYS
    seen: set[str] = set()

    for query in SEARCH_QUERIES:
        if query in done_topics:
            continue
        items = []
        for s in fetch_stories_for_query(query, min_score, days_back):
            # Require an external link — an Ask/Tell HN that only points to its
            # own discussion thread is conversation, not content. Show HN that
            # links to a real project/repo keeps its external url and stays.
            if not s["external_url"]:
                continue
            hid = s["hn_id"]
            if hid in existing_keys or hid in seen or s["external_url"] in existing_story_urls or not s["title"]:
                continue
            seen.add(hid)
            items.append(_to_queue_item(s))
        yield query, items
        time.sleep(0.5)
