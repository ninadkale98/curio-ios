"""
Papers source — one channel, two discovery paths merged by arxiv_id:

  1. HuggingFace Daily Papers — community-curated (~50/day), signal = upvotes.
  2. Semantic Scholar citation search — most-cited recent CS papers, signal =
     citation velocity (citations per month since publication). This is the
     "importance" axis: raw recency surfaces garbage, but citations are the
     field's own verdict on what mattered. We require an arXiv ID so papers
     dedup cleanly with the HF path (and S2's own duplicate records collapse).

Both paths use source='arxiv' + source_key=arxiv_id, so a paper is never
double-queued. HF is processed first; a paper in both keeps the HF row.

Like the GitHub source this is a discovery + metadata layer only — no PDF
downloads. The writer wing fetches the full paper at write time.
"""

import logging
import os
import time
from datetime import date, datetime, timedelta, timezone

import requests

from ..queue_item import QueueItem

log = logging.getLogger(__name__)

HF_HEADERS = {"User-Agent": "Curio-Bot/1.0 (paper discovery)"}
HF_DAILY_API = "https://huggingface.co/api/daily_papers"

S2_BULK_SEARCH = "https://api.semanticscholar.org/graph/v1/paper/search/bulk"
S2_KEY = os.getenv("SEMANTIC_SCHOLAR_KEY", "")
S2_FIELDS = "title,abstract,externalIds,publicationDate,year,citationCount,influentialCitationCount,authors,fieldsOfStudy"

# AI/CS query terms aligned to Curio's audience — each is one S2 bulk-search call.
S2_TOPICS = [
    "large language model", "ai agent", "reinforcement learning", "computer vision",
    "natural language processing", "diffusion model", "retrieval augmented generation",
    "robotics", "multimodal learning", "speech recognition", "reasoning",
    "code generation", "graph neural network", "3d reconstruction",
    "recommendation system", "adversarial robustness", "model quantization",
    "distributed training",
]

# Recent-enough that citations have had time to accrue, fresh enough to stay
# reel-worthy. Curio's existing stories are explainers, not breaking news, so a
# landmark paper from the last ~18 months is exactly right.
S2_YEAR_RANGE = "2025-2026"

HF_BACKFILL_DAYS = 180
HF_INCREMENTAL_DAYS = 3
S2_BACKFILL_PER_TOPIC = 150
S2_INCREMENTAL_PER_TOPIC = 50


def _arxiv_url(arxiv_id: str) -> str:
    return f"https://arxiv.org/abs/{arxiv_id}"


def _thumbnail(arxiv_id: str) -> str:
    # HF's social-preview CDN — reliable only for HF-curated papers (verified:
    # arxiv-only ids time out), so only the HF path uses this.
    return f"https://cdn-thumbnails.huggingface.co/social-thumbnails/papers/{arxiv_id}.png"


# ---------------------------------------------------------------------------
# HuggingFace Daily Papers (curated / upvotes)
# ---------------------------------------------------------------------------

def fetch_daily_papers(date_str: str) -> list[dict]:
    try:
        r = requests.get(HF_DAILY_API, params={"date": date_str}, headers=HF_HEADERS, timeout=15)
        if r.status_code != 200:
            log.warning(f"HF daily {date_str}: HTTP {r.status_code}")
            return []
        entries = r.json()
        if not isinstance(entries, list):
            return []
    except requests.RequestException as e:
        log.warning(f"HF daily fetch failed for {date_str}: {e}")
        return []

    papers = []
    for entry in entries:
        p = entry.get("paper", {})
        arxiv_id = p.get("id")
        if not arxiv_id:
            continue
        papers.append({
            "arxiv_id": arxiv_id,
            "title": (p.get("title") or "").strip(),
            "upvotes": p.get("upvotes", 0) or 0,
            "github_repo": p.get("githubRepo") or None,
            "github_stars": p.get("githubStars", 0) or 0,
            "ai_summary": p.get("ai_summary") or p.get("summary") or None,
            "ai_keywords": p.get("ai_keywords") or [],
            "num_comments": entry.get("numComments", 0) or 0,
            "author_participating": bool(entry.get("isAuthorParticipating", False)),
            "submitted_by": (entry.get("submittedBy") or {}).get("name"),
            "daily_date": date_str,
            "published_at": p.get("publishedAt"),
        })
    return papers


def fetch_date_range(days_back: int) -> list[dict]:
    today = date.today()
    seen: dict[str, dict] = {}
    for i in range(days_back):
        date_str = (today - timedelta(days=i)).isoformat()
        for p in fetch_daily_papers(date_str):
            aid = p["arxiv_id"]
            if aid not in seen or p["upvotes"] > seen[aid]["upvotes"]:
                seen[aid] = p
        time.sleep(0.2)
    log.info(f"HF: {len(seen)} unique papers across last {days_back} days")
    return sorted(seen.values(), key=lambda p: p["upvotes"], reverse=True)


def _hf_to_queue_item(p: dict) -> QueueItem:
    aid = p["arxiv_id"]
    return QueueItem(
        source="arxiv",
        source_key=aid,
        url=_arxiv_url(aid),
        title=p["title"],
        summary=p["ai_summary"],
        raw_text=p["ai_summary"],  # writer fetches the full paper later
        raw_json={
            "discovered_via": "hf",
            "upvotes": p["upvotes"],
            "ai_keywords": p["ai_keywords"],
            "github_repo": p["github_repo"],
            "github_stars": p["github_stars"],
            "num_comments": p["num_comments"],
            "author_participating": p["author_participating"],
            "submitted_by": p["submitted_by"],
            "daily_date": p["daily_date"],
        },
        image_url=_thumbnail(aid),
        topic=(p["ai_keywords"][0] if p["ai_keywords"] else "paper"),
        published_at=p["published_at"],
    )


# ---------------------------------------------------------------------------
# Semantic Scholar citation search (importance / velocity)
# ---------------------------------------------------------------------------

def _s2_get(params: dict, retries: int = 2):
    # With a key the first request succeeds, so retries barely matter. Keyless
    # (the temporary state until SEMANTIC_SCHOLAR_KEY is set) the shared pool
    # throttles hard on CI's shared IPs — so back off briefly then GIVE UP fast.
    # A skipped topic is just picked up on the next daily run; better than one
    # slow topic dragging the whole cron out.
    headers = {"x-api-key": S2_KEY} if S2_KEY else {}
    for attempt in range(retries):
        try:
            r = requests.get(S2_BULK_SEARCH, params=params, headers=headers, timeout=30)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 429:
                wait = min(2 * (attempt + 1), 4)
                log.warning(f"S2 429, sleeping {wait}s (attempt {attempt + 1}/{retries})")
                time.sleep(wait)
                continue
            log.warning(f"S2 -> {r.status_code}: {r.text[:150]}")
            return None
        except requests.RequestException as e:
            log.warning(f"S2 fetch error (attempt {attempt + 1}): {e}")
            time.sleep(min(2 ** attempt, 3))
    log.warning("S2 throttled — skipping this query, will retry next run")
    return None


def _citations_per_month(citations: int, publication_date: str | None) -> float | None:
    if not publication_date:
        return None
    try:
        pub = datetime.fromisoformat(publication_date).replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    months = max((datetime.now(timezone.utc) - pub).days / 30.0, 1.0)
    return round(citations / months, 2)


def fetch_cited_papers(topic: str, limit: int) -> list[dict]:
    """Most-cited recent CS papers for a query term, that have an arXiv ID."""
    data = _s2_get({
        "query": topic,
        "fields": S2_FIELDS,
        "year": S2_YEAR_RANGE,
        "fieldsOfStudy": "Computer Science",
        "sort": "citationCount:desc",
    })
    if not data:
        return []

    out = []
    for p in data.get("data", []):
        arxiv_id = (p.get("externalIds") or {}).get("ArXiv")
        if not arxiv_id:  # require arXiv id — coherent identity + dedups S2's own dups
            continue
        out.append(p)
        if len(out) >= limit:
            break
    return out


def _s2_to_queue_item(topic: str, p: dict) -> QueueItem:
    arxiv_id = p["externalIds"]["ArXiv"]
    citations = p.get("citationCount") or 0
    pub = p.get("publicationDate")
    abstract = p.get("abstract")
    authors = [a.get("name") for a in (p.get("authors") or []) if a.get("name")]
    return QueueItem(
        source="arxiv",
        source_key=arxiv_id,
        url=_arxiv_url(arxiv_id),
        title=(p.get("title") or "").strip(),
        summary=(abstract[:400] + "...") if abstract and len(abstract) > 400 else abstract,
        raw_text=abstract,  # may be null (licensing) — writer fetches full paper then
        raw_json={
            "discovered_via": "s2",
            "citations": citations,
            "influential_citations": p.get("influentialCitationCount") or 0,
            "citations_per_month": _citations_per_month(citations, pub),
            "authors": authors,
            "fields_of_study": p.get("fieldsOfStudy") or [],
            "s2_query": topic,
        },
        image_url=None,  # no reliable image; writer sources it
        topic=topic,
        published_at=pub,
    )


# ---------------------------------------------------------------------------
# Orchestration — same generator contract as github.iter_topics
# ---------------------------------------------------------------------------

def iter_topics(
    backfill: bool,
    existing_keys: set[str],
    existing_story_urls: set[str] = frozenset(),
    done_topics: set[str] = frozenset(),
):
    seen: set[str] = set()

    def keep(aid: str) -> bool:
        if aid in existing_keys or aid in seen or _arxiv_url(aid) in existing_story_urls:
            return False
        seen.add(aid)
        return True

    # Path 1 — HF curated (processed first so it wins any overlap).
    if "hf-daily" not in done_topics:
        hf = fetch_date_range(HF_BACKFILL_DAYS if backfill else HF_INCREMENTAL_DAYS)
        items = [_hf_to_queue_item(p) for p in hf if keep(p["arxiv_id"])]
        yield "hf-daily", items

    # Path 2 — Semantic Scholar citation search, one unit per query term.
    per_topic = S2_BACKFILL_PER_TOPIC if backfill else S2_INCREMENTAL_PER_TOPIC
    for topic in S2_TOPICS:
        unit = f"s2:{topic}"
        if unit in done_topics:
            continue
        papers = fetch_cited_papers(topic, per_topic)
        items = [_s2_to_queue_item(topic, p) for p in papers if keep(p["externalIds"]["ArXiv"])]
        yield unit, items
        time.sleep(1)  # gentle pacing on the shared keyless pool
