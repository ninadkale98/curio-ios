import logging
import os

import requests
from dotenv import load_dotenv

from .queue_item import QueueItem

load_dotenv()

log = logging.getLogger(__name__)

SUPABASE_URL = os.environ["SUPABASE_URL"]
SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

HEADERS = {
    "apikey": SERVICE_ROLE_KEY,
    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
    "Content-Type": "application/json",
    # merge-duplicates + only the columns below in each row means an
    # on-conflict update touches title/summary/raw_text/... but never
    # status/claimed_at/done_at/error — a re-crawl can't un-claim or
    # un-finish a row the writer wing already picked up.
    "Prefer": "resolution=merge-duplicates,return=representation",
}

UPSERT_COLUMNS = (
    "source",
    "source_key",
    "url",
    "title",
    "summary",
    "raw_text",
    "raw_json",
    "image_url",
    "topic",
    "published_at",
)


def upsert(items: list[QueueItem]) -> list[dict]:
    """Insert or refresh queue rows. Returns the rows as stored server-side."""
    if not items:
        return []

    rows = [{col: getattr(item, col) for col in UPSERT_COLUMNS} for item in items]
    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/content_queue",
        params={"on_conflict": "source,source_key"},
        headers=HEADERS,
        json=rows,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def existing_keys(source: str) -> set[str]:
    """All source_keys already queued for a source, regardless of status — used to skip re-fetching detail for known items."""
    return {row["source_key"] for row in _paginate("content_queue", "source_key", {"source": f"eq.{source}"})}


def existing_story_urls() -> set[str]:
    """source_url of every already-published story — from the earlier single-routine
    pipeline (and the original 7 seed stories, if they ever get one). Keeps the
    aggregator from queueing something already live in the app."""
    rows = _paginate("stories", "source_url", {"source_url": "not.is.null"})
    return {row["source_url"] for row in rows if row["source_url"]}


def _paginate(table: str, select: str, params: dict, page_size: int = 1000) -> list[dict]:
    """Fetch every matching row via Range headers — PostgREST caps a single
    response at ~1000 rows, so a plain GET silently truncates larger tables."""
    out: list[dict] = []
    offset = 0
    while True:
        resp = requests.get(
            f"{SUPABASE_URL}/rest/v1/{table}",
            params={"select": select, **params},
            headers={
                "apikey": SERVICE_ROLE_KEY,
                "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
                "Range-Unit": "items",
                "Range": f"{offset}-{offset + page_size - 1}",
            },
            timeout=30,
        )
        resp.raise_for_status()
        batch = resp.json()
        out.extend(batch)
        if len(batch) < page_size:
            return out
        offset += page_size
